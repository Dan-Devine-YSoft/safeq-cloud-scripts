# 🔄 SafeQ6 to SafeQ Cloud Migration Scripts

A comprehensive set of PowerShell scripts to facilitate data migration from YSoft SafeQ6 to YSoft SafeQ Cloud.

## ⚡ Prerequisites

- PowerShell 7 or higher required
- For detailed requirements and setup instructions, see our [Wiki Documentation](https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki)

## 📋 Scripts Overview

### Configuration
| Script | Description |
|--------|-------------|
| `create_config` | 🔧 Initial setup script that configures all required parameters for other scripts. **Run this first!** |

### User Management
| Script | Description |
|--------|-------------|
| `export_users_from_sq6` | 📤 Exports user details (username, email, card number, alias, PIN) from SafeQ6 |
| `import_users_to_sqc` | 📥 Imports previously exported user data into SafeQ Cloud |
| `delete_users_from_sqc` | 🗑️ Removes user information from SafeQ Cloud based on export data |

### Device Management  
| Script | Description |
|--------|-------------|
| `export_devices_from_sq6` | 📤 Exports devices and direct queues from SafeQ6 |
| `import_devices_and_queues_to_sqc` | 📥 Imports previously exported device data into SafeQ Cloud |
| `delete_devices_and_queues_from_sqc` | 🗑️ Removes devices and queues from SafeQ Cloud based on export data |

## 📚 Documentation

For detailed instructions and usage examples for each script, please refer to our [Wiki Documentation](https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki).