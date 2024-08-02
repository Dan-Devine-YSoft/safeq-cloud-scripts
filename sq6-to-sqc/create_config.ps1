# Define the path to the configuration file
$configFilePath = "config.json"

# Check PowerShell version on Windows
if ($IsWindows) {
    if ($PSVersionTable.PSVersion -lt [Version]"7.4") {
        Write-Output "This script is not supported on versions of PowerShell prior to v7.4 on Windows. Please update your version of PowerShell before running this script."
        exit
    }
}

# Function to convert PSCustomObject to hashtable
function ConvertTo-Hashtable {
    param (
        [PSCustomObject]$obj
    )

    $hash = @{}
    $obj.PSObject.Properties | ForEach-Object {
        $hash[$_.Name] = $_.Value
    }
    return $hash
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

        # Create the SQL command to get distinct non-empty 'sign' values
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT DISTINCT sign FROM tenant_1.users WHERE sign IS NOT NULL AND sign <> ''"
        $reader = $command.ExecuteReader()

        $signValues = @()
        while ($reader.Read()) {
            $signValues += $reader["sign"]
        }

        $reader.Close()

        if ($signValues.Count -eq 0) {
            Write-Output "No valid 'sign' values found in the database."
            $connection.Close()
            exit
        }

        Write-Output "Select the Authentication Source:"
        $i = 1
        $signValues | ForEach-Object { Write-Output "$i. $_"; $i++ }
        $selection = Read-Host "Enter the number of the Authentication Source"
        $config['authSource'] = $signValues[$selection - 1]

        # Retrieve sample data including all columns for the final CSV output
        $command.CommandText = @"
SELECT TOP 5
    u.login,
    u.name + ' ' + u.surname AS full_name,
    u.email,
    ua.alias,
    CASE WHEN uc.card LIKE 'PIN%' THEN SUBSTRING(uc.card, 4, LEN(uc.card) - 3) ELSE uc.card END AS pin_or_card
FROM tenant_1.users u
LEFT JOIN tenant_1.users_aliases ua ON u.id = ua.user_id
LEFT JOIN tenant_1.users_cards uc ON u.id = uc.user_id
WHERE u.sign = '$($config.authSource)'
"@
        $reader = $command.ExecuteReader()
        $sampleData = @()
        while ($reader.Read()) {
            $sampleData += [PSCustomObject]@{
                login        = $reader["login"]
                full_name    = $reader["full_name"]
                email        = $reader["email"]
                alias        = $reader["alias"]
                pin_or_card  = $reader["pin_or_card"]
            }
        }

        $reader.Close()
        $connection.Close()

        # Display sample data and prompt for confirmation
        Write-Output "Sample data:"
        $sampleData | Format-Table -AutoSize
        $confirmation = Read-Host "Above is a sample of what will be exported. Please confirm if it looks correct? (y/n)"

        if ($confirmation -eq "y") {
            # Prompt for the CSV file name
            $csvFileNamePrompt = Read-Host "Enter the name of the CSV file (press enter to use sq6export.csv)"
            $config['csvFileName'] = if ($csvFileNamePrompt -eq "") { "sq6export.csv" } else { $csvFileNamePrompt }

            Write-Output "Configuration for SafeQ6 export saved."
            $config | Select-Object serverName, databaseName, username, authSource, csvFileName
        } else {
            Write-Output "Starting over with new configuration..."
            if (Test-Path $configFilePath) {
                Remove-Item -Path $configFilePath -Force
            }
            $config.Clear()  # Clear existing configuration in memory
            Set-SafeQ6Export -config $config
            return
        }

    } catch {
        Write-Error "An error occurred: $_"
        $connection.Close()
    }
}

# Function to prompt the user for SafeQ Cloud import configuration
function Set-SafeQCloudImport {
    param (
        [hashtable]$config
    )

    $config['ProviderId'] = Read-Host "Enter the Provider ID"
    $config['Domain'] = Read-Host "Enter your SafeQ Cloud domain (e.g., customer.au.ysoft.cloud)"

    $plainApiKey = Read-Host "Enter your API Key"
    $config['ApiKey'] = (ConvertTo-SecureString -String $plainApiKey -AsPlainText -Force) | ConvertFrom-SecureString

    $config['ApiUsername'] = Read-Host "Enter your API Username"

    $secureApiPassword = Read-Host "Enter your API Password" -AsSecureString
    $config['ApiPassword'] = $secureApiPassword | ConvertFrom-SecureString

    Write-Output "Configuration for SafeQ Cloud import saved."
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
        # Present the configuration menu to the user
        Write-Output "`nSelect an option:"
        Write-Output "1. Set export from SafeQ6"
        Write-Output "2. Set import to SafeQ Cloud"
        Write-Output "3. Delete the existing configuration and start over"
        Write-Output "4. Exit the script"
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
                    Write-Output "Configuration deleted. Starting over."
                } else {
                    Write-Output "No configuration is created, please pick an option to configure."
                }
            }
            "4" {
                Write-Output "Exiting the script."
                exit
            }
            default {
                Write-Output "Invalid choice. Please enter 1, 2, 3, or 4."
            }
        }

        # Save the configuration to a JSON file only once after making changes
        $config | ConvertTo-Json -Depth 32 | Set-Content -Path $configFilePath -Force
        Write-Output "Configuration saved to $configFilePath."
    }
}

# Execute the configuration function
Save-Configuration
