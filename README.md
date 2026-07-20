# contacts-iCloud

A Swift command-line tool to convert Apple vCard (.vcf) files exported from iCloud.com into a Google Contacts compatible CSV format.

## Features

- Converts multiple .vcf files from a directory into a single CSV file
- Supports multiple phone numbers (up to 3) and email addresses (up to 3) per contact
- Preserves contact types (e.g., "Mobile", "Home", "Work")
- Handles both full names and structured names (given name/family name)
- Creates a CSV format that's ready for Google Contacts import
- Properly escapes special characters for CSV format

## Requirements

- macOS 12.0 or later
- Swift 5.5 or later

## Installation

1. Clone this repository:
```bash
git clone [repository-url]
cd contacts-iCloud
```

2. Build the package:
```bash
swift build
```

## Usage

Run the tool by providing two arguments:
1. Path to the directory containing your .vcf files
2. Path where you want to save the output CSV file

```bash
swift run contacts-iCloud ./contacts output.csv
```

For example, if your .vcf files are in a directory called "contacts" and you want to save the CSV as "google-contacts.csv":
```bash
swift run contacts-iCloud ./contacts google-contacts.csv
```

## Google Contacts Export

This tool also includes a utility to export contacts directly from Google Contacts to VCF format.

### Setup

1. Create a Google Cloud Project and enable the People API
2. Create OAuth 2.0 credentials
3. Create a `.envlocal` file in the project root with:
```bash
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
GOOGLE_REDIRECT_URI=http://localhost:8080/oauth/callback
GOOGLE_TOKEN=
```

### Usage

Run the Google export tool by providing the output file path:

```bash
swift run google-vcf-export output.vcf
```

This will:
1. Check for an existing authentication token in `.envlocal`
2. If no token exists:
   - Open your default browser for Google OAuth authentication
   - Request permission to access your contacts
   - Save the token in `.envlocal` for future use
3. Export all contacts to the specified VCF file

The tool will remember your authentication after the first use, so you won't need to re-authenticate each time. The token is stored locally in your `.envlocal` file and is not committed to git.

The exported VCF file can then be imported into other contact management systems.

## Sync to iCloud Contacts

This tool includes functionality to sync Google contacts (exported as VCF) to iCloud contacts. This is a one-way sync that will:
- Add new contacts from the VCF file to iCloud
- Remove iCloud contacts that don't exist in the VCF file
- Skip existing contacts that are already in iCloud

### Usage

After exporting your Google contacts to a VCF file, run:

```bash
swift run sync-to-icloud output.vcf
```

This will:
1. Request access to your macOS Contacts (you'll need to grant permission)
2. Load your existing iCloud contacts
3. Compare them with the contacts in the VCF file
4. Add any new contacts from the VCF file
5. Remove any iCloud contacts that don't exist in the VCF file

The tool will show progress and statistics about:
- Number of contacts loaded from iCloud
- Number of contacts in the VCF file
- Number of contacts added
- Number of contacts removed

### Notes
- This is a one-way sync from Google to iCloud
- The tool only modifies iCloud contacts
- Matching is done based on name, email addresses, and phone numbers
- The sync is performed locally on your machine
- No data is sent to external servers

## CSV Format

The generated CSV file includes the following columns:
- Name
- Given Name
- Family Name
- Phone 1-3 Type
- Phone 1-3 Value
- Email 1-3 Type
- Email 1-3 Value

This format is compatible with Google Contacts' import feature.

## Importing to Google Contacts

1. Go to [Google Contacts](https://contacts.google.com/)
2. Click on "Import" in the left sidebar
3. Select the generated CSV file
4. Click "Import"

## Contributing

We welcome contributions to contacts-iCloud! Here's how you can help:

### Reporting Issues

Found a bug? Have a feature request? We'd love to hear about it! You can:

- [🐛 Report a Bug](https://github.com/[username]/contacts-iCloud/issues/new?template=bug_report.md)
- [💡 Request a Feature](https://github.com/[username]/contacts-iCloud/issues/new?template=feature_request.md)
- [💬 Start a Discussion](https://github.com/[username]/contacts-iCloud/discussions)

When reporting bugs, please:
- Use the bug report template
- Include steps to reproduce the issue
- Provide sample .vcf files if possible (with personal information removed)
- Include your environment details (OS version, Swift version)

### Pull Requests

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Notes

- The tool processes all .vcf files in the specified directory
- Progress is shown as each file is processed
- The tool handles vCard encoding issues automatically
- Special characters are properly escaped in the CSV output

## Error Handling

The tool will:
- Print an error if the input directory cannot be accessed
- Show which files failed to process, if any
- Display a helpful usage message if arguments are missing

## License

This project is open source and available under the MIT License. 