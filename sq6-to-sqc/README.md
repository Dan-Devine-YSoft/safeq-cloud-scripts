# PowerShell 7 Required

Please see [further details](https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki)

This folder contains several scripts designed to assist with migration from YSoft SafeQ6 to YSoft SafeQ Cloud.

## create_config.ps1
This script configures all parameters required for each other script in this folder.  Run this first.
## export_users_from_sq6.ps1
This script exports user details including username, email, card number, alias and pin and prepares them for importing into SafeQ Cloud
## import_users_from_sq6_to_sqc.ps1
This script uses the previously exported user information from SafeQ6 to import user information into SafeQ Cloud
## delete_users_from_sqc.ps1
This script deletes user information from SafeQ Cloud based on the previously exported user information
## export_devices_from_sq6.ps1
This script exports devices and direct queues from SafeQ6 and prepares them for importing into SafeQ Cloud
## import_devices_and_queues_from_sq6_to_sqc.ps1
This script users the previously exported device information from SafeQ6 to import device information into SafeQ Cloud
## delete_devices_and_queues_from_sqc.ps1
This script deletes devices and queues from SafeQ Cloud based on the previously exported device information

Further detail on each script is available in the wiki.