# Define the path to the configuration file
$configFilePath = "config.json"

# Function to retrieve configuration
function Get-Configuration {
    if (-Not (Test-Path $configFilePath)) {
        Write-Output "Configuration file not found. Please run the configuration script first."
        exit
    }
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json

    # Ensure configuration hashtable has the necessary keys
    if (-not $config.PSObject.Properties.Match('serverName') -or -not $config.PSObject.Properties.Match('databaseName') -or -not $config.PSObject.Properties.Match('username') -or -not $config.PSObject.Properties.Match('password') -or -not $config.PSObject.Properties.Match('authSource') -or -not $config.PSObject.Properties.Match('csvFileName')) {
        Write-Output "The configuration file is missing required keys. Please run the configuration script again."
        exit
    }

    $securePassword = $config.password | ConvertTo-SecureString
    $config.Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    return $config
}

# Load configuration
$config = Get-Configuration

# Extract configuration values
$serverName = $config.serverName
$databaseName = $config.databaseName
$username = $config.username
$password = $config.Password
$authSource = $config.authSource
$outputCsv = $config.csvFileName  # Path to the output CSV file

# Create SQL query with JOINs and filtering
$query = @"
SELECT
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
WHERE u.sign = '$authSource'
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

# Create SQL command
$command = $connection.CreateCommand()
$command.CommandText = $query

# Execute the query and get results
try {
    $reader = $command.ExecuteReader()
    Write-Output "Query executed successfully."
} catch {
    Write-Output "Failed to execute query: $_"
    $connection.Close()
    exit
}

# Create a DataTable to hold the query results
$dataTable = New-Object System.Data.DataTable

# Load the data into the DataTable
$dataTable.Load($reader)

# Close the reader and the connection
$reader.Close()
$connection.Close()
Write-Output "Database connection closed."

# Export the DataTable to CSV
try {
    $dataTable | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8
    Write-Output "Data has been exported to $outputCsv"
} catch {
    Write-Output "Failed to export data to CSV: $_"
}
