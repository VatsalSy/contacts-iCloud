import Foundation
import Contacts
import Files

// MARK: - Contact Matching
struct ContactIdentifier: Hashable {
    let givenName: String
    let familyName: String
    let emails: Set<String>
    let phones: Set<String>
    
    init(contact: CNContact) {
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        self.emails = Set(contact.emailAddresses.map { $0.value as String })
        self.phones = Set(contact.phoneNumbers.map { $0.value.stringValue })
    }
    
    init(vCardContact: VCardContact) {
        self.givenName = vCardContact.givenName
        self.familyName = vCardContact.familyName
        self.emails = Set(vCardContact.emails.map { $0.value })
        self.phones = Set(vCardContact.phones.map { $0.value })
    }
}

// MARK: - VCard Parsing
struct VCardContact {
    var givenName: String = ""
    var familyName: String = ""
    var phones: [(type: String, value: String)] = []
    var emails: [(type: String, value: String)] = []
}

func sanitizePhoneNumber(_ phone: String) -> String {
    // Remove any non-digit characters except + (which can be at the start)
    var sanitized = phone.trimmingCharacters(in: .whitespaces)
    if sanitized.hasPrefix("+") {
        sanitized.removeFirst()
        return "+" + sanitized.filter { $0.isNumber }
    }
    return sanitized.filter { $0.isNumber }
}

func sanitizeEmail(_ email: String) -> String? {
    let sanitized = email.trimmingCharacters(in: .whitespaces).lowercased()
    // Basic email validation
    let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
    return emailPredicate.evaluate(with: sanitized) ? sanitized : nil
}

func sanitizeName(_ name: String) -> String {
    // Remove any control characters and trim whitespace
    return name.filter { !$0.isControl }.trimmingCharacters(in: .whitespaces)
}

func parseVCardFile(_ content: String) -> [VCardContact] {
    var contacts: [VCardContact] = []
    var currentContact: VCardContact?
    var skippedContacts = 0
    
    let lines = content.components(separatedBy: .newlines)
    for line in lines {
        let normalizedLine = line.trimmingCharacters(in: .whitespaces)
        
        if normalizedLine == "BEGIN:VCARD" {
            currentContact = VCardContact()
        } else if normalizedLine == "END:VCARD", var contact = currentContact {
            // Only add contacts that have at least a name and either a phone number or email
            if (!contact.givenName.isEmpty || !contact.familyName.isEmpty) &&
               (contact.phones.count > 0 || contact.emails.count > 0) {
                contacts.append(contact)
            } else {
                skippedContacts += 1
            }
            currentContact = nil
        } else if var contact = currentContact {
            let parts = normalizedLine.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let key = String(parts[0])
            let value = String(parts[1])
            
            switch key {
            case "N":
                let nameParts = value.split(separator: ";")
                if nameParts.count >= 2 {
                    contact.familyName = sanitizeName(String(nameParts[0]))
                    contact.givenName = sanitizeName(String(nameParts[1]))
                }
            case _ where key.hasPrefix("TEL"):
                let sanitizedPhone = sanitizePhoneNumber(value)
                if !sanitizedPhone.isEmpty {
                    let type = key.contains("CELL") ? "Mobile" : 
                              key.contains("WORK") ? "Work" : "Home"
                    // Only add if we don't already have this number
                    if !contact.phones.contains(where: { $0.value == sanitizedPhone }) {
                        contact.phones.append((type: type, value: sanitizedPhone))
                    }
                }
            case _ where key.hasPrefix("EMAIL"):
                if let sanitizedEmail = sanitizeEmail(value) {
                    let type = key.contains("WORK") ? "Work" : "Home"
                    // Only add if we don't already have this email
                    if !contact.emails.contains(where: { $0.value == sanitizedEmail }) {
                        contact.emails.append((type: type, value: sanitizedEmail))
                    }
                }
            default:
                break
            }
            
            currentContact = contact
        }
    }
    
    if skippedContacts > 0 {
        print("Skipped \(skippedContacts) contacts due to missing required information")
    }
    
    return contacts
}

// MARK: - iCloud Sync
class ContactSync {
    private let store = CNContactStore()
    private var existingContacts: [ContactIdentifier: CNContact] = [:]
    
    func requestAccess() async throws {
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            throw ContactError.accessDenied
        }
    }
    
    func loadExistingContacts() async throws {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey,
            CNContactIdentifierKey
        ] as [CNKeyDescriptor]
        
        // Get containers to identify iCloud
        let containers = try store.containers(matching: nil)
        print("\nAvailable containers:")
        for container in containers {
            print("- \(container.name) (type: \(container.type))")
        }
        
        let iCloudContainer = containers.first { $0.name == "iCloud" }
        if let container = iCloudContainer {
            print("\nFound iCloud container: \(container.name)")
        } else {
            print("\nWarning: No iCloud container found!")
        }
        
        // Get all contacts from the default container
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .userDefault
        
        try store.enumerateContacts(with: request) { contact, _ in
            // Check if the contact is in the iCloud container
            if let container = iCloudContainer {
                let predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
                if predicate.evaluate(with: contact) {
                    let identifier = ContactIdentifier(contact: contact)
                    self.existingContacts[identifier] = contact
                }
            }
        }
        
        print("\nLoaded \(existingContacts.count) existing contacts from iCloud account")
    }
    
    func syncContacts(from vcfPath: String) async throws {
        // Load VCF contacts
        let vcfContent = try String(contentsOfFile: vcfPath, encoding: .utf8)
        let vcfContacts = parseVCardFile(vcfContent)
        let vcfIdentifiers = Set(vcfContacts.map { ContactIdentifier(vCardContact: $0) })
        
        print("Loaded \(vcfContacts.count) contacts from VCF file")
        
        // Find contacts to add and remove
        let existingIdentifiers = Set(existingContacts.keys)
        let contactsToAdd = vcfContacts.filter { !existingIdentifiers.contains(ContactIdentifier(vCardContact: $0)) }
        let contactsToRemove = existingContacts.filter { !vcfIdentifiers.contains($0.key) }
        
        print("Found \(contactsToAdd.count) contacts to add")
        print("Found \(contactsToRemove.count) contacts to remove")
        
        // Safety check - ask for confirmation before making large changes
        if contactsToAdd.count > 100 || contactsToRemove.count > 10 {
            print("\nWARNING: This will make significant changes to your contacts:")
            print("- Adding \(contactsToAdd.count) new contacts")
            print("- Removing \(contactsToRemove.count) existing contacts")
            print("\nThese changes will sync to iCloud automatically.")
            print("Are you sure you want to continue? (y/N)")
            
            let response = readLine()?.lowercased()
            guard response == "y" || response == "yes" else {
                print("Operation cancelled by user")
                throw ContactError.userCancelled
            }
        }
        
        // Get iCloud container for adding contacts
        let containers = try store.containers(matching: nil)
        let iCloudContainer = containers.first { $0.name == "iCloud" }
        
        guard let container = iCloudContainer else {
            throw ContactError.noICloudAccount
        }
        
        // Perform updates in smaller batches with delays
        let batchSize = 25 // Reduced batch size
        var addedCount = 0
        var removedCount = 0
        var failedCount = 0
        
        // Add new contacts in batches
        for chunk in stride(from: 0, to: contactsToAdd.count, by: batchSize) {
            let endIndex = min(chunk + batchSize, contactsToAdd.count)
            let batchContacts = contactsToAdd[chunk..<endIndex]
            
            do {
                let saveRequest = CNSaveRequest()
                
                for vcfContact in batchContacts {
                    let contact = CNMutableContact()
                    contact.givenName = vcfContact.givenName
                    contact.familyName = vcfContact.familyName
                    
                    // Add phone numbers
                    contact.phoneNumbers = vcfContact.phones.map {
                        CNLabeledValue(
                            label: $0.type == "Mobile" ? CNLabelPhoneNumberMobile :
                                   $0.type == "Work" ? CNLabelWork : CNLabelHome,
                            value: CNPhoneNumber(stringValue: $0.value)
                        )
                    }
                    
                    // Add email addresses
                    contact.emailAddresses = vcfContact.emails.map {
                        CNLabeledValue(
                            label: $0.type == "Work" ? CNLabelWork : CNLabelHome,
                            value: $0.value as NSString
                        )
                    }
                    
                    saveRequest.add(contact, toContainerWithIdentifier: container.identifier)
                }
                
                try store.execute(saveRequest)
                addedCount += batchContacts.count
                print("Added \(addedCount) contacts so far...")
                
                // Add a small delay between batches
                if chunk + batchSize < contactsToAdd.count {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                }
            } catch {
                print("Error adding batch: \(error)")
                failedCount += batchContacts.count
                // Continue with next batch instead of failing completely
                continue
            }
        }
        
        // Remove old contacts in batches
        for chunk in stride(from: 0, to: contactsToRemove.count, by: batchSize) {
            let endIndex = min(chunk + batchSize, contactsToRemove.count)
            let batchContacts = Array(contactsToRemove)[chunk..<endIndex]
            
            do {
                let saveRequest = CNSaveRequest()
                
                for contact in batchContacts {
                    if let mutableContact = contact.value.mutableCopy() as? CNMutableContact {
                        saveRequest.delete(mutableContact)
                    }
                }
                
                try store.execute(saveRequest)
                removedCount += batchContacts.count
                print("Removed \(removedCount) contacts so far...")
                
                // Add a small delay between batches
                if chunk + batchSize < contactsToRemove.count {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                }
            } catch {
                print("Error removing batch: \(error)")
                failedCount += batchContacts.count
                // Continue with next batch instead of failing completely
                continue
            }
        }
        
        print("\nSync completed:")
        print("- Added \(addedCount) new contacts")
        print("- Removed \(removedCount) old contacts")
        if failedCount > 0 {
            print("- Failed to process \(failedCount) contacts")
        }
        print("\nChanges will sync to iCloud automatically.")
    }
}

// MARK: - Error Handling
enum ContactError: Error {
    case accessDenied
    case noICloudAccount
    case invalidVCFFile
    case userCancelled
}

// MARK: - Main
@main
struct SyncToICloud {
    static func main() async throws {
        // Validate arguments
        guard CommandLine.arguments.count == 2 else {
            print("Usage: sync-to-icloud <path_to_vcf_file>")
            throw ContactError.invalidVCFFile
        }
        
        let vcfPath = CommandLine.arguments[1]
        
        // Initialize sync
        let sync = ContactSync()
        
        // Request access
        print("Requesting access to Contacts...")
        try await sync.requestAccess()
        
        // Load existing contacts
        print("Loading existing contacts...")
        try await sync.loadExistingContacts()
        
        // Perform sync
        print("Starting sync...")
        try await sync.syncContacts(from: vcfPath)
    }
} 