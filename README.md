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