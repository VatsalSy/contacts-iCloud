import Foundation

// Contact structure that supports multiple phones and emails
struct Contact {
    var givenName: String = ""
    var familyName: String = ""
    var fullName: String = ""
    var phones: [(type: String, value: String)] = []
    var emails: [(type: String, value: String)] = []
    
    // Maximum number of phones and emails to export
    static let maxPhones = 3
    static let maxEmails = 3
}

// Parse type and value from a vCard property line
func parseTypeAndValue(_ line: String, defaultType: String) -> (type: String, value: String) {
    let parts = line.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return (defaultType, "") }
    
    let keyParts = parts[0].split(separator: ";")
    var type = defaultType
    
    // Look for TYPE parameter
    for part in keyParts.dropFirst() {
        if part.uppercased().hasPrefix("TYPE=") {
            type = String(part.dropFirst(5))
                .replacingOccurrences(of: "\"", with: "")
                .capitalized
            break
        }
    }
    
    return (type, String(parts[1]).trimmingCharacters(in: .whitespaces))
}

// Parses one contact block from lines of a single vCard
func parseVCardBlock(lines: [String]) -> Contact {
    var contact = Contact()
    
    for line in lines {
        let normalizedLine = line.trimmingCharacters(in: .whitespaces)
        guard let colonIndex = normalizedLine.firstIndex(of: ":") else { continue }
        
        let keyPart = normalizedLine[..<colonIndex]
        let valuePart = normalizedLine[normalizedLine.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespaces)
        
        // Get the base key without parameters
        let baseKey = keyPart.split(separator: ";").first?.uppercased() ?? ""
        
        switch baseKey {
        case "FN":
            contact.fullName = valuePart
        case "N":
            let components = valuePart.split(separator: ";", maxSplits: 4, omittingEmptySubsequences: false)
            if components.count > 1 {
                contact.familyName = String(components[0])
                contact.givenName = String(components[1])
            }
        case "TEL":
            let (type, value) = parseTypeAndValue(normalizedLine, defaultType: "Mobile")
            if !value.isEmpty {
                contact.phones.append((type: type, value: value))
            }
        case "EMAIL":
            let (type, value) = parseTypeAndValue(normalizedLine, defaultType: "Home")
            if !value.isEmpty {
                contact.emails.append((type: type, value: value))
            }
        default:
            break
        }
    }
    
    // If no explicit full name was found, create one from components
    if contact.fullName.isEmpty {
        contact.fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
    }
    
    return contact
}

// Process a full .vcf file that may contain multiple vCard blocks
func parseVCardFile(content: String) -> [Contact] {
    var contacts: [Contact] = []
    var currentBlock: [String] = []
    var insideVCard = false
    
    let lines = content.components(separatedBy: .newlines)
    
    for line in lines {
        if line.uppercased().hasPrefix("BEGIN:VCARD") {
            insideVCard = true
            currentBlock = []
        } else if line.uppercased().hasPrefix("END:VCARD") {
            insideVCard = false
            contacts.append(parseVCardBlock(lines: currentBlock))
            currentBlock = []
        } else if insideVCard {
            currentBlock.append(line)
        }
    }
    
    return contacts
}

// Process all .vcf files in the given directory
func processDirectory(at folderPath: String) -> [Contact] {
    var allContacts: [Contact] = []
    
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: folderPath) else {
        print("Cannot open directory: \(folderPath)")
        return []
    }
    
    while let file = enumerator.nextObject() as? String {
        if file.lowercased().hasSuffix(".vcf") {
            let filePath = (folderPath as NSString).appendingPathComponent(file)
            do {
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                let contacts = parseVCardFile(content: content)
                allContacts.append(contentsOf: contacts)
                print("Processed: \(file) - Found \(contacts.count) contacts")
            } catch {
                print("Could not read file at path: \(filePath)")
                print("Error: \(error)")
            }
        }
    }
    
    return allContacts
}

// Generate CSV header for Google Contacts format
func generateCSVHeader() -> String {
    var headers = [
        "Name",
        "Given Name",
        "Family Name"
    ]
    
    // Add phone number columns
    for i in 1...Contact.maxPhones {
        headers.append("Phone \(i) - Type")
        headers.append("Phone \(i) - Value")
    }
    
    // Add email columns
    for i in 1...Contact.maxEmails {
        headers.append("E-mail \(i) - Type")
        headers.append("E-mail \(i) - Value")
    }
    
    return headers.joined(separator: ",")
}

// Convert a Contact to a CSV row
func contactToCSVRow(_ contact: Contact) -> String {
    var values = [
        contact.fullName,
        contact.givenName,
        contact.familyName
    ]
    
    // Add phone numbers (up to max)
    for i in 0..<Contact.maxPhones {
        if i < contact.phones.count {
            values.append(contact.phones[i].type)
            values.append(contact.phones[i].value)
        } else {
            values.append("")  // Type
            values.append("")  // Value
        }
    }
    
    // Add emails (up to max)
    for i in 0..<Contact.maxEmails {
        if i < contact.emails.count {
            values.append(contact.emails[i].type)
            values.append(contact.emails[i].value)
        } else {
            values.append("")  // Type
            values.append("")  // Value
        }
    }
    
    // Escape values and wrap in quotes
    return values.map { value in
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }.joined(separator: ",")
}

// Main entry point
func main() {
    guard CommandLine.arguments.count == 3 else {
        print("Usage: \(CommandLine.arguments[0]) <path_to_vcf_folder> <path_to_output_csv>")
        exit(1)
    }
    
    let vcfFolderPath = CommandLine.arguments[1]
    let outputCSVPath = CommandLine.arguments[2]
    
    print("Processing VCF files from: \(vcfFolderPath)")
    let contacts = processDirectory(at: vcfFolderPath)
    print("Found total of \(contacts.count) contacts")
    
    // Generate CSV content
    let header = generateCSVHeader()
    let rows = contacts.map { contactToCSVRow($0) }
    let csvContent = ([header] + rows).joined(separator: "\n")
    
    // Write to file
    do {
        try csvContent.write(toFile: outputCSVPath, atomically: true, encoding: .utf8)
        print("Successfully wrote CSV file to: \(outputCSVPath)")
    } catch {
        print("Failed to write CSV file: \(error)")
        exit(1)
    }
}

main() 