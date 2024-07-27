# Sample scripts for integration with SafeQ Cloud API

### POWERSHELL 7 REQUIRED
Please see https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki for further details

- **import_printers_and_ports** - Parse a CSV and create printer ports and queues for direct printing
- **import_users_and_cards** - Import users from a CSV with additional details
- **register_card_id** - Add a card ID to a user record
- **register_current_session_user** - add the current session user from a Windows workstation to a SafeQ Cloud tenancy as a user.  Useful for automation on smaller deployments
- **document_history** - Export document history into a csv file for reporting purposes.  Uses proper token-based user authentication and allows for extended reporting periods.  Instructions for this script are available here: https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki/Document-History
- **document_history_24hrs** - Export document history into a csv file for reporting purposes for the last 24hrs.  Useful for scheduling a nightly export of data

