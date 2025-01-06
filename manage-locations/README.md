# Manage Locations Scripts

This is a set of scripts designed to manage locations and related settings within YSoft SafeQ Cloud. The scripts are designed to be run from a Windows machine and require PowerShell 5.1 or later.

Run `manageLocations.ps1` to provide a menu for all options.

---

## 1. Import Locations

This option will import any locations you have in the API currently and store them in a local file called `locations.json`. This then allows you to, for example, delete all existing locations using option 4.

---

## 2. Create Locations

This option will create new locations for you based on the contents of a CSV file. The CSV file needs to contain the following columns. Note that there can be other columns as well; the script will search for the presence of the below specifically:

- **locationName**: Must exist

In addition, one of the following columns must exist:

- **locationGatewayData**: The IP address of the gateway for the location
- **locationSubnetData**: The subnet mask in CIDR format
- **locationIpRangeData**: An IP range
- **locationWifiData**: An SSID for a WiFi network

These can be combined. For example, you can have a location with a subnet mask and a WiFi network. If you need multiple entries of a type per location, e.g., multiple subnet masks for a single location, then create additional rows in the CSV for each subnet mask.

The script will prompt you for the CSV name. The script will also store all new locations in a file called `locations.json`. This file can be used to delete all locations created by the script using option 4.

---

## 3. Export Locations

This option will query the API for the latest location list and then export all locations to a CSV file.

---

## 4. Delete Locations

This option will delete all locations from the API based on the contents of `locations.json`.

---

## 5. Set up API

This option will request a SafeQ Cloud tenancy address and API key. Note that these details will be stored in plain text, in a file called `apiconfig.json`. If the `.json` file cannot be secured, then it is recommended to delete this file after using this script set. You can always create it again later using option 5.

---

