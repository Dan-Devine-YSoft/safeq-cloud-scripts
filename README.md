# 🖨️ Sample Scripts for SafeQ Cloud API Integration

A collection of PowerShell scripts to help automate common SafeQ Cloud administration tasks.

## ⚠️ Prerequisites

- **PowerShell 7** is required
- For detailed setup instructions, visit our [Wiki](https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki)

## 📚 Available Scripts

### Printer Management
- **`import_printers_and_ports`** - Parse CSV files to create printer ports and queues for direct printing

### User Management
- **`import_users_and_cards`** - Bulk import users from CSV with additional details
- **`register_card_id`** - Add card IDs to user records
- **`register_current_session_user`** - Add current Windows session user to SafeQ Cloud tenant *(Ideal for small deployments)*

### Reporting & Analytics
- **`document_history`** - Export comprehensive document history to CSV
  - Uses token-based authentication
  - Supports extended reporting periods
  - [Detailed Instructions](https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki/Document-History)
- **`document_history_24hrs`** - Export last 24 hours of document history
  - Perfect for scheduled nightly data exports

### Migration Tools
- **`sq6_to_sqc`** - Suite of scripts to help migrate data from SafeQ6 to SafeQ Cloud

## 📖 Documentation
For detailed documentation and usage instructions, please visit our [Wiki](https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki).