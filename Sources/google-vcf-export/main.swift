import Foundation
import Vapor
import SwiftSoup
import Files

// MARK: - Environment Configuration
struct GoogleConfig {
    let clientId: String
    let clientSecret: String
    let redirectUri: String
    let token: String?
    
    static func load() throws -> GoogleConfig {
        // Try to load from environment first
        if let clientId = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"],
           let clientSecret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"],
           let redirectUri = ProcessInfo.processInfo.environment["GOOGLE_REDIRECT_URI"] {
            let token = ProcessInfo.processInfo.environment["GOOGLE_TOKEN"]
            return GoogleConfig(clientId: clientId, clientSecret: clientSecret, redirectUri: redirectUri, token: token)
        }
        
        // If not in environment, try to load from .envlocal file
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let envPath = (currentPath as NSString).appendingPathComponent(".envlocal")
        
        guard fileManager.fileExists(atPath: envPath),
              let envContents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            throw EnvError.missingConfiguration
        }
        
        var config: [String: String] = [:]
        envContents.components(separatedBy: .newlines).forEach { line in
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                config[key] = value
            }
        }
        
        guard let clientId = config["GOOGLE_CLIENT_ID"],
              let clientSecret = config["GOOGLE_CLIENT_SECRET"],
              let redirectUri = config["GOOGLE_REDIRECT_URI"] else {
            
            print("Please ensure your .envlocal file contains:")
            print("GOOGLE_CLIENT_ID=your_client_id")
            print("GOOGLE_CLIENT_SECRET=your_client_secret")
            print("GOOGLE_REDIRECT_URI=http://localhost:8080/oauth/callback")
            throw EnvError.missingConfiguration
        }
        
        let token = config["GOOGLE_TOKEN"]
        return GoogleConfig(clientId: clientId, clientSecret: clientSecret, redirectUri: redirectUri, token: token)
    }
    
    static func saveToken(_ token: String) throws {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let envPath = (currentPath as NSString).appendingPathComponent(".envlocal")
        
        guard fileManager.fileExists(atPath: envPath),
              var envContents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            throw EnvError.missingConfiguration
        }
        
        // Split into lines and process
        var lines = envContents.components(separatedBy: .newlines)
        var tokenFound = false
        
        // Update or add token
        for (index, line) in lines.enumerated() {
            if line.starts(with: "GOOGLE_TOKEN=") {
                lines[index] = "GOOGLE_TOKEN=\(token)"
                tokenFound = true
                break
            }
        }
        
        if !tokenFound {
            lines.append("GOOGLE_TOKEN=\(token)")
        }
        
        // Write back to file
        envContents = lines.joined(separator: "\n")
        try envContents.write(toFile: envPath, atomically: true, encoding: .utf8)
    }
}

enum EnvError: Error {
    case missingConfiguration
    case invalidArguments
}

// MARK: - OAuth Handler
class OAuthHandler {
    private let config: GoogleConfig
    private let app: Application
    private var accessToken: String?
    private let semaphore = DispatchSemaphore(value: 0)
    
    init(config: GoogleConfig) async throws {
        self.config = config
        self.app = try await Application.make()
        self.accessToken = config.token
        
        setupRoutes()
    }
    
    private func setupRoutes() {
        app.get("oauth", "callback") { req -> Response in
            if let code = try? req.query.get(String.self, at: "code") {
                Task {
                    await self.exchangeCodeForToken(code)
                }
            }
            return Response(status: .ok, body: .init(string: "Authorization successful! You can close this window."))
        }
    }
    
    private func exchangeCodeForToken(_ code: String) async {
        do {
            let tokenURL = "https://oauth2.googleapis.com/token"
            var request = URLRequest(url: URL(string: tokenURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            let parameters = [
                "client_id": config.clientId,
                "client_secret": config.clientSecret,
                "code": code,
                "redirect_uri": config.redirectUri,
                "grant_type": "authorization_code"
            ]
            
            request.httpBody = parameters
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
                .data(using: .utf8)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let token = json?["access_token"] as? String {
                self.accessToken = token
                try GoogleConfig.saveToken(token)
                semaphore.signal()
            }
        } catch {
            print("Error exchanging code for token: \(error)")
            semaphore.signal()
        }
    }
    
    func authorize() throws -> String {
        // If we already have a token, return it
        if let existingToken = accessToken {
            return existingToken
        }
        
        let scopes = ["https://www.googleapis.com/auth/contacts.readonly"]
        let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
        + "?client_id=\(config.clientId)"
        + "&redirect_uri=\(config.redirectUri)"
        + "&response_type=code"
        + "&scope=\(scopes.joined(separator: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
        
        print("Please open this URL in your browser to authorize the application:")
        print(authURL)
        
        try app.server.start(address: .hostname("localhost", port: 8080))
        
        semaphore.wait()
        
        app.server.shutdown()
        
        guard let token = accessToken else {
            throw EnvError.missingConfiguration
        }
        
        return token
    }
}

// MARK: - Contact Fetcher
struct Contact: Codable {
    let names: [ContactName]?
    let phoneNumbers: [PhoneNumber]?
    let emailAddresses: [EmailAddress]?
    
    struct ContactName: Codable {
        let givenName: String?
        let familyName: String?
    }
    
    struct PhoneNumber: Codable {
        let value: String
        let type: String?
    }
    
    struct EmailAddress: Codable {
        let value: String
        let type: String?
    }
}

class ContactFetcher {
    private let accessToken: String
    
    init(accessToken: String) {
        self.accessToken = accessToken
    }
    
    func fetchContacts() async throws -> [Contact] {
        var contacts: [Contact] = []
        var pageToken: String?
        
        repeat {
            let (newContacts, nextPageToken) = try await fetchContactsPage(pageToken: pageToken)
            contacts.append(contentsOf: newContacts)
            pageToken = nextPageToken
        } while pageToken != nil
        
        return contacts
    }
    
    private func fetchContactsPage(pageToken: String?) async throws -> ([Contact], String?) {
        var urlComponents = URLComponents(string: "https://people.googleapis.com/v1/people/me/connections")!
        urlComponents.queryItems = [
            URLQueryItem(name: "personFields", value: "names,phoneNumbers,emailAddresses"),
            URLQueryItem(name: "pageSize", value: "1000")
        ]
        
        if let pageToken = pageToken {
            urlComponents.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("Response status code: \(httpResponse.statusCode)")
        }
        
        print("Response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode response")")
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let connections = json?["connections"] as? [[String: Any]] ?? []
        let nextPageToken = json?["nextPageToken"] as? String
        
        print("Found \(connections.count) connections in this page")
        
        let contacts = try connections.compactMap { connection -> Contact? in
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: connection)
                return try JSONDecoder().decode(Contact.self, from: jsonData)
            } catch {
                print("Error decoding contact: \(error)")
                print("Problematic contact data: \(connection)")
                return nil
            }
        }
        
        print("Successfully parsed \(contacts.count) contacts from this page")
        return (contacts, nextPageToken)
    }
}

// MARK: - VCard Generator
class VCardGenerator {
    func generateVCard(from contacts: [Contact]) -> String {
        var vcard = ""
        
        for contact in contacts {
            vcard += "BEGIN:VCARD\n"
            vcard += "VERSION:3.0\n"
            
            if let name = contact.names?.first {
                let givenName = name.givenName ?? ""
                let familyName = name.familyName ?? ""
                vcard += "N:\(familyName);\(givenName);;;\n"
                vcard += "FN:\(givenName) \(familyName)\n"
            }
            
            if let phones = contact.phoneNumbers {
                for phone in phones {
                    let type = phone.type?.uppercased() ?? "HOME"
                    vcard += "TEL;TYPE=\(type):\(phone.value)\n"
                }
            }
            
            if let emails = contact.emailAddresses {
                for email in emails {
                    let type = email.type?.uppercased() ?? "HOME"
                    vcard += "EMAIL;TYPE=\(type):\(email.value)\n"
                }
            }
            
            vcard += "END:VCARD\n"
        }
        
        return vcard
    }
}

// MARK: - Main
@main
struct GoogleVCFExport {
    static func main() async throws {
        // Validate arguments
        guard CommandLine.arguments.count == 2 else {
            print("Usage: google-vcf-export <output.vcf>")
            throw EnvError.invalidArguments
        }
        
        let outputPath = CommandLine.arguments[1]
        
        // Load configuration
        let config = try GoogleConfig.load()
        
        // Authorize and get access token
        let oauthHandler = try await OAuthHandler(config: config)
        let accessToken = try oauthHandler.authorize()
        
        // Fetch contacts
        print("Fetching contacts...")
        let fetcher = ContactFetcher(accessToken: accessToken)
        let contacts = try await fetcher.fetchContacts()
        
        // Generate VCard
        print("Generating VCard file...")
        let generator = VCardGenerator()
        let vcardContent = generator.generateVCard(from: contacts)
        
        // Save to file
        try vcardContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("Successfully exported \(contacts.count) contacts to \(outputPath)")
    }
}
