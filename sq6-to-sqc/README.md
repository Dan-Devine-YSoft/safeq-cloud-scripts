# PowerShell 7 Required

Please see [further details](https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki)

This folder contains several scripts designed to assist with migration from YSoft SafeQ6 to YSoft SafeQ Cloud.

**create_config.ps1** - This script configures all parameters required for each other script in this folder.  Run this first.
**export_users_from_sq6.ps1** - This script exports user details including username, email, card number, alias and pin and prepares them for importing into SafeQ Cloud
**import_users_from_sq6_to_sqc.ps1** - This script uses the previously exported information from SafeQ6 to import user information into SafeQ Cloud

Further detail on each script is available in the wiki.