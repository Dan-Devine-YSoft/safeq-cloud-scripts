# Define the path to the configuration file
$configFilePath = "config.json"

# Check the PowerShell version on Windows
if ($PSVersionTable.PSVersion -lt [Version]"7.4") {
    Write-Host "This script is not supported on versions of PowerShell prior to v7.4 on Windows. Please update your version of PowerShell before running this script."
    Write-Host "Details on installing the latest version of PowerShell are available at https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows"
    exit
}

# Function to prompt the user for SafeQ6 export configuration
function Set-SafeQ6Export {
    param (
        [hashtable]$config
    )

    $config['serverName'] = Read-Host "Enter the SQL Server name (e.g., servername\\instance or servername)"
    $databaseNamePrompt = Read-Host "Enter the Database name (press enter for SQDB6)"
    $config['databaseName'] = if ($databaseNamePrompt -eq "") { "SQDB6" } else { $databaseNamePrompt }
    $config['username'] = Read-Host "Enter the SQL Username"

    # Security reminder
    Write-Host "Note: Your password will be stored securely. Ensure that the configuration file is protected from unauthorized access."

    $password = Read-Host "Enter the SQL Password" -AsSecureString
    $config['password'] = $password | ConvertFrom-SecureString

    # Convert the secure password to plain text for connection string
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

    # Form the connection string
    $connectionString = "Server=tcp:$($config.serverName),1433;Database=$($config.databaseName);User Id=$($config.username);Password=$plainPassword;"
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString

    try {
        # Open the connection
        $connection.Open()
        Write-Host "Connection to SQL Server successful."

        # Query for user export confirmation
        $exportUsers = Read-Host "Will you be exporting user information? (y/n)"

        if ($exportUsers -eq "y") {
            # Create the SQL command to get distinct non-empty 'sign' values
            $command = $connection.CreateCommand()
            $command.CommandText = "SELECT DISTINCT sign FROM tenant_1.users WHERE sign IS NOT NULL AND sign <> ''"

            try {
                $reader = $command.ExecuteReader()
                Write-Host "User query executed successfully."
            } catch {
                Write-Error "Error executing SQL query for users: $_"
                $connection.Close()
                return
            }

            $signValues = @()
            while ($reader.Read()) {
                $signValues += $reader["sign"]
            }

            $reader.Close()

            if ($signValues.Count -eq 0) {
                Write-Host "No valid 'sign' values found in the database."
                $connection.Close()
                exit
            }

            Write-Host "Select the Authentication Source:"
            $i = 1
            $signValues | ForEach-Object { Write-Host "$i. $_"; $i++ }
            $selection = Read-Host "Enter the number of the Authentication Source"
            $config['authSource'] = $signValues[$selection - 1]

            # Retrieve sample user data including all columns for the final CSV output
            $command.CommandText = @"
SELECT TOP 5
    u.login,
    u.name + ' ' + u.surname AS full_name,
    u.email,
    ua.alias,
    CASE
        WHEN uc.card LIKE 'PIN%' THEN SUBSTRING(uc.card, 4, LEN(uc.card) - 3)
        ELSE NULL
    END AS pin,
    CASE
        WHEN uc.card NOT LIKE 'PIN%' THEN uc.card
        ELSE NULL
    END AS card_number
FROM tenant_1.users u
LEFT JOIN tenant_1.users_aliases ua ON u.id = ua.user_id
LEFT JOIN tenant_1.users_cards uc ON u.id = uc.user_id
WHERE u.sign = '$($config.authSource)'
"@
            try {
                $reader = $command.ExecuteReader()
            } catch {
                Write-Error "Error executing SQL query for user sample data: $_"
                $connection.Close()
                return
            }

            $sampleData = @()
            while ($reader.Read()) {
                $sampleData += [PSCustomObject]@{
                    login        = $reader["login"]
                    full_name    = $reader["full_name"]
                    email        = $reader["email"]
                    alias        = $reader["alias"]
                    pin          = $reader["pin"]
                    card_number  = $reader["card_number"]
                }
            }

            $reader.Close()

            # Display sample user data and prompt for confirmation
            Write-Host "Sample user data:"
            $sampleData | Format-Table -AutoSize
            $confirmation = Read-Host "Above is a sample of what will be exported for users. Does it look correct? (y/n)"

            if ($confirmation -eq "y") {
                # Prompt for the CSV file name
                $csvFileNamePrompt = Read-Host "Enter the name of the CSV file for users (press enter to use sq6UserExport.csv)"
                $config['csvFileName'] = if ($csvFileNamePrompt -eq "") { "sq6UserExport.csv" } else { $csvFileNamePrompt }

                Write-Host "Configuration for SafeQ6 user export saved."
            } else {
                Write-Host "Starting over with new user configuration..."
                if (Test-Path $configFilePath) {
                    Remove-Item -Path $configFilePath -Force
                }
                $config.Clear()  # Clear existing configuration in memory
                return
            }
        }

        # Query for device export confirmation
        $exportDevices = Read-Host "Will you be exporting device information? (y/n)"

        if ($exportDevices -eq "y") {
            # Retrieve sample device data
            $command.CommandText = @"
SELECT d.name, d.network_address, d.network_port, d.location, t.vendor, t.serial_number, q.name as direct_queue
FROM tenant_1.devices d
LEFT JOIN tenant_1.terminals t ON d.id = t.device_id
LEFT JOIN tenant_1.direct_queues q ON d.id = q.device_id
WHERE d.status = 'ACTIVE'
"@

            try {
                $reader = $command.ExecuteReader()
            } catch {
                Write-Error "Error executing SQL query for device sample data: $_"
                $connection.Close()
                return
            }

            $devices = @{}
            $queueMap = @{}

            while ($reader.Read()) {
                $deviceName = $reader["name"]
                $queueName = $reader["direct_queue"]

                if (-not $devices[$deviceName]) {
                    $device = [PSCustomObject]@{
                        name            = $deviceName
                        network_address = $reader["network_address"]
                        network_port    = $reader["network_port"]
                        location        = $reader["location"]
                        vendor          = $reader["vendor"]
                        serial_number   = $reader["serial_number"]
                    }
                    $devices[$deviceName] = $device
                    $queueMap[$deviceName] = @()
                }

                if ($queueName) {
                    $queueMap[$deviceName] += $queueName
                }
            }

            $reader.Close()

            # Generate sample device data with dynamic columns for queues
            $sampleData = $devices.Values | ForEach-Object {
                $device = $_
                $queues = $queueMap[$device.name]
                $queueColumns = @{}
                for ($i = 0; $i -lt $queues.Count; $i++) {
                    $queueColumns["direct_queue_$($i + 1)"] = $queues[$i]
                }
                $newDevice = [PSCustomObject]@{
                    name            = $device.name
                    network_address = $device.network_address
                    network_port    = $device.network_port
                    location        = $device.location
                    vendor          = $device.vendor
                    serial_number   = $device.serial_number
                }

                foreach ($key in $queueColumns.Keys) {
                    Add-Member -InputObject $newDevice -NotePropertyName $key -NotePropertyValue $queueColumns[$key]
                }
                $newDevice
            }

            # Display sample device data and prompt for confirmation
            Write-Host "Sample device data:"
            $sampleData | Format-Table -AutoSize
            $confirmation = Read-Host "Above is a sample of what will be exported for devices.  Additional direct queues for a device will be handled.  Does the data look correct? (y/n)"

            if ($confirmation -eq "y") {
                # Prompt for the CSV file name for devices
                $csvFileNamePrompt = Read-Host "Enter the name of the CSV file for devices (press enter to use sq6DeviceExport.csv)"
                $config['csvDeviceFileName'] = if ($csvFileNamePrompt -eq "") { "sq6DeviceExport.csv" } else { $csvFileNamePrompt }

                Write-Host "Configuration for SafeQ6 device export saved."
            } else {
                Write-Host "Starting over with new device configuration..."
                if (Test-Path $configFilePath) {
                    Remove-Item -Path $configFilePath -Force
                }
                $config.Clear()  # Clear existing configuration in memory
                return
            }
        }

        $connection.Close()
        Write-Host "Database connection closed."

    } catch {
        Write-Error "An error occurred while connecting to the SQL Server: $_"
        return
    }
}

# Function to prompt the user for SafeQ Cloud import configuration
function Set-SafeQCloudImport {
    param (
        [hashtable]$config
    )

    $config['ProviderId'] = Read-Host "Enter the Provider ID"
    $config['Domain'] = Read-Host "Enter your SafeQ Cloud domain (e.g., customer.au.ysoft.cloud)"

    # Security reminder
    Write-Host "Note: Your API key and password will be stored securely. Ensure that the configuration file is protected from unauthorized access."

    $plainApiKey = Read-Host "Enter your API Key"
    $config['ApiKey'] = (ConvertTo-SecureString -String $plainApiKey -AsPlainText -Force) | ConvertFrom-SecureString

    $config['ApiUsername'] = Read-Host "Enter your API Username"

    $secureApiPassword = Read-Host "Enter your API Password" -AsSecureString
    $config['ApiPassword'] = $secureApiPassword | ConvertFrom-SecureString

    Write-Host "Configuration for SafeQ Cloud import saved."
    $config | Select-Object ProviderId, Domain, ApiUsername
}

# Main configuration function
function Save-Configuration {
    $config = @{}

    if (Test-Path $configFilePath) {
        $config = Get-Content -Path $configFilePath | ConvertFrom-Json
        $config = ConvertTo-Hashtable -obj $config
    }

    # Loop to keep presenting the menu until the user decides to exit
    while ($true) {
        # Save the configuration to a JSON file only once after making changes
        if ($config.Count -gt 0) {
            $config | ConvertTo-Json -Depth 32 | Set-Content -Path $configFilePath -Force
            Write-Host "Configuration saved to $configFilePath."
        }

        # Present the configuration menu to the user
        Write-Host "`nSelect an option:"
        Write-Host "1. Configure export from SafeQ6"
        Write-Host "2. Configure import to SafeQ Cloud"
        Write-Host "3. Delete the existing configuration and start over"
        Write-Host "4. Exit the script"
        $choice = Read-Host "Enter your choice (1, 2, 3, or 4)"

        switch ($choice) {
            "1" {
                Set-SafeQ6Export -config $config
            }
            "2" {
                Set-SafeQCloudImport -config $config
            }
            "3" {
                if (Test-Path $configFilePath) {
                    Remove-Item -Path $configFilePath -Force
                    $config.Clear()  # Clear existing configuration in memory
                    Write-Host "Configuration deleted. Starting over."
                } else {
                    Write-Host "No configuration is created, please pick an option to configure."
                }
            }
            "4" {
                Write-Host "Exiting the script."
                exit
            }
            default {
                Write-Host "Invalid choice. Please enter 1, 2, 3, or 4."
            }
        }
    }
}

# Execute the configuration function
Save-Configuration
