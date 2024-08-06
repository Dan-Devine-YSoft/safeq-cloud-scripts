# Define the path to the configuration file
$configFilePath = "config.json"

# Function to retrieve configuration
function Get-Configuration {
    if (-Not (Test-Path $configFilePath)) {
        Write-Output "Configuration file not found. Please run create_config.ps1 to create it."
        exit
    }
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json

    # Ensure configuration hashtable has the necessary keys
    if (-not $config.PSObject.Properties.Match('serverName') -or -not $config.PSObject.Properties.Match('databaseName') -or -not $config.PSObject.Properties.Match('username') -or -not $config.PSObject.Properties.Match('password') -or -not $config.PSObject.Properties.Match('authSource')) {
        Write-Output "The configuration file is missing required keys. Please run the configuration script again."
        exit
    }

    $securePassword = $config.password | ConvertTo-SecureString
    $config.Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    return $config
}

# Load the configuration
$config = Get-Configuration

# Extract configuration values
$serverName = $config.serverName
$databaseName = $config.databaseName
$username = $config.username
$password = $config.Password
$authSource = $config.authSource
$deviceOutputCsv = "sq6DeviceExport.csv"  # Path to the device output CSV file

# Create SQL query for devices with JOINs and filtering
$deviceQuery = @"
SELECT
    d.id,
    d.name,
    d.network_address,
    d.network_port,
    d.location,
    t.vendor,
    t.serial_number
FROM tenant_1.devices d
LEFT JOIN tenant_1.terminals t ON d.id = t.device_id
WHERE d.status = 'ACTIVE'
"@

# Create SQL query for direct queues
$queueQuery = @"
SELECT
    d.id AS device_id,
    q.name AS queue_name
FROM tenant_1.devices d
LEFT JOIN tenant_1.direct_queues q ON d.id = q.device_id
WHERE d.status = 'ACTIVE'
"@

# Create a SQL connection using TCP
$connectionString = "Server=tcp:$serverName,1433;Database=$databaseName;User Id=$username;Password=$password;"
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString

# Open the connection
try {
    $connection.Open()
    Write-Output "Database connection opened successfully."
} catch {
    Write-Output "Failed to open database connection: $_"
    exit
}

# Create SQL command for devices
$deviceCommand = $connection.CreateCommand()
$deviceCommand.CommandText = $deviceQuery

# Execute the device query and get results
try {
    $deviceReader = $deviceCommand.ExecuteReader()
    Write-Output "Device query executed successfully."
} catch {
    Write-Output "Failed to execute device query: $_"
    $connection.Close()
    exit
}

# Create a DataTable to hold the device query results
$deviceTable = New-Object System.Data.DataTable

# Load the data into the DataTable
$deviceTable.Load($deviceReader)

# Close the device reader
$deviceReader.Close()

# Create SQL command for queues
$queueCommand = $connection.CreateCommand()
$queueCommand.CommandText = $queueQuery

# Execute the queue query and get results
try {
    $queueReader = $queueCommand.ExecuteReader()
    Write-Output "Queue query executed successfully."
} catch {
    Write-Output "Failed to execute queue query: $_"
    $connection.Close()
    exit
}

# Create a DataTable to hold the queue query results
$queueTable = New-Object System.Data.DataTable

# Load the data into the DataTable
$queueTable.Load($queueReader)

# Close the queue reader
$queueReader.Close()

# Process the queue data to handle multiple queue names per device
$queueData = @{}
foreach ($row in $queueTable.Rows) {
    $deviceId = $row["device_id"]
    $queueName = $row["queue_name"]

    if (-not $queueData.ContainsKey($deviceId)) {
        $queueData[$deviceId] = @()
    }

    $queueData[$deviceId] += $queueName
}

# Close the connection
$connection.Close()
Write-Output "Database connection closed."

# Add queue names to the device data only if they exist
foreach ($deviceRow in $deviceTable.Rows) {
    $deviceId = $deviceRow["id"]
    if ($queueData.ContainsKey($deviceId)) {
        $queues = $queueData[$deviceId]
        for ($i = 0; $i -lt $queues.Length; $i++) {
            $columnName = "direct_queue_$($i + 1)"
            if (-not $deviceTable.Columns.Contains($columnName)) {
                $deviceTable.Columns.Add($columnName, [string])
            }
            $deviceRow[$columnName] = $queues[$i]
        }
    }
}

# Export the device DataTable with queues to CSV
try {
    $deviceTable | Export-Csv -Path $deviceOutputCsv -NoTypeInformation -Encoding UTF8
    Write-Output "Device data with queues has been exported to $deviceOutputCsv"
} catch {
    Write-Output "Failed to export device data with queues to CSV: $_"
}
