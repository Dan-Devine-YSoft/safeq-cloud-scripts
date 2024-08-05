# Define the path to the configuration file
$configFilePath = "config.json"

# Function to retrieve configuration
function Get-Configuration {
    if (-Not (Test-Path $configFilePath)) {
        Write-Error "Configuration file not found. Please run create_config.ps1 to create it."
        exit
    }
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json

    # Ensure configuration hashtable has the necessary keys
    $requiredKeys = @('serverName', 'databaseName', 'username', 'password', 'authSource', 'csvFileName')
    $missingKeys = $requiredKeys | Where-Object { -not $config.PSObject.Properties.Match($_) -or -not $config.$_ }
    if ($missingKeys.Count -gt 0) {
        Write-Error "The configuration file is missing the following keys: $($missingKeys -join ', '). Please run the configuration script again."
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

# Function to open SQL connection
function Open-SqlConnection {
    param (
        [string]$connectionString
    )
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    try {
        $connection.Open()
        Write-Verbose "Database connection opened successfully." -Verbose
        return $connection
    } catch {
        Write-Error "Failed to open database connection: $_"
        exit
    }
}

# Open the connection
$connectionString = "Server=tcp:$serverName,1433;Database=$databaseName;User Id=$username;Password=$password;"
$connection = Open-SqlConnection -connectionString $connectionString

# Create SQL command
$command = $connection.CreateCommand()
$command.CommandText = $query

# Execute the query and get results
try {
    $reader = $command.ExecuteReader()
    Write-Verbose "Query executed successfully."  -Verbose
} catch {
    Write-Error "Failed to execute query: $_"
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
Write-Verbose "Database connection closed."  -Verbose

# Export the DataTable to CSV
try {
    $dataTable | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8
    Write-Output "Data has been exported to $outputCsv"
} catch {
    Write-Error "Failed to export data to CSV: $_"
}
