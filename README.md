# Sample scripts for integration with SafeQ Cloud API

### Note all of these are tested on and require PowerShell 7.  The default PowerShell 5.1 which ships with most standard Windows distributions will not be sufficient to run these scripts due to missing command implementations

- **import_printers_and_ports** - Parse a CSV and create printer ports and queues for direct printing\\
- **import_users_and_cards** - Import users from a CSV with additional details\\
- **register_card_id** - Add a card ID to a user record\\
- **register_current_session_user** - add the current session user from a Windows workstation to a SafeQ Cloud tenancy as a user.  Useful for automation on smaller deployments\\
- **document_history** - Export document history into a csv file for reporting purposes
- **document_history_24hrs** - Export document history into a csv file for reporting purposes for the last 24hrs.  Useful for scheduling a nightly export of data

