# Define the path to the configuration file
$configFilePath = "config.json"

# Function to load configuration from the file
function Load-Configuration {
    if (-Not (Test-Path $configFilePath)) {
        Write-Output "Configuration file not found. Please run the configuration script first."
        exit
    }
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json
    $securePassword = $config.password | ConvertTo-SecureString
    $config.Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    return $config
}

# Load configuration
$config = Load-Configuration

# Check if the csvFileName property exists and prompt the user if it doesn't
if (-Not $config.PSObject.Properties.Match('csvFileName')) {
    $csvFileNamePrompt = Read-Host "Enter the name of the CSV file (press enter to use sq6export.csv)"
    $config.csvFileName = if ($csvFileNamePrompt -eq "") { "sq6export.csv" } else { $csvFileNamePrompt }

    # Save the updated configuration with the CSV file name
    $config | ConvertTo-Json | Set-Content -Path $configFilePath
}

# Extract configuration values
$serverName = $config.serverName
$databaseName = $config.databaseName
$username = $config.username
$password = $config.Password
$authSource = $config.authSource
$outputCsv = $config.csvFileName  # Path to the output CSV file

# Create SQL query with JOINs and filtering
$query = @"
SELECT u.login, u.name + ' ' + u.surname AS full_name, u.email, ua.alias,
       CASE WHEN uc.card LIKE 'PIN%' THEN SUBSTRING(uc.card, 4, LEN(uc.card) - 3) ELSE uc.card END AS pin_or_card
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
$connection.Open()

# Create SQL command
$command = $connection.CreateCommand()
$command.CommandText = $query

# Execute the query and get results
$reader = $command.ExecuteReader()

# Create a DataTable to hold the query results
$dataTable = New-Object System.Data.DataTable

# Load the data into the DataTable
$dataTable.Load($reader)

# Close the reader and the connection
$reader.Close()
$connection.Close()

# Export the DataTable to CSV
$dataTable | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8

# Inform the user
Write-Output "Data has been exported to $outputCsv"