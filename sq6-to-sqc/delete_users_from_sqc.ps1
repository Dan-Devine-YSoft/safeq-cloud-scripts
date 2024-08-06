# Initialize log file
$logFilePath = "delete_users_from_sqc.log"
if (-not (Test-Path $logFilePath)) {
    $null = New-Item -ItemType File -Path $logFilePath -Force
}

function Write-Log {
    param (
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$level] - $message"
    Add-Content -Path $logFilePath -Value $logMessage
    Write-Host $logMessage
}

# Log start
Write-Log "Script execution started."

# Define the path to the configuration file
$configFilePath = "config.json"

# Function to retrieve configuration
function Get-Configuration {
    if (-Not (Test-Path $configFilePath)) {
        Write-Log "Configuration file not found. Please run create_config.ps1 to create it." -level "ERROR"
        exit
    }
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json

    # Check for required configuration keys
    $requiredKeys = @('ProviderId', 'Domain', 'ApiKey', 'ApiUsername', 'ApiPassword', 'csvFileName')
    $missingKeys = $requiredKeys | Where-Object { -not $config.PSObject.Properties.Match($_) -or -not $config.$_ }

    if ($missingKeys.Count -gt 0) {
        Write-Log "The configuration file is missing the following required keys: $($missingKeys -join ', '). Please run create_config.ps1 to update the configuration." -level "ERROR"
        exit
    }

    return $config
}

# Load configuration
$config = Get-Configuration

# Extract configuration values
$outputCsv = $config.csvFileName
$providerId = [int]$config.ProviderId # Ensuring providerId is treated as an integer
$domain = $config.Domain
$plainApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $config.ApiKey)))
$userid = $config.ApiUsername
$securePassword = ConvertTo-SecureString -String $config.ApiPassword

# Prompt user to select which field to use for the username
$fieldOptions = @("login", "email", "alias")
$fieldSelection = Read-Host "Select which field to use as the username (login/email/alias)"

if ($fieldOptions -notcontains $fieldSelection) {
    Write-Log "Invalid selection. Please run the script again and choose either 'login', 'email', or 'alias'." -level "ERROR"
    exit
}

# Define API base URL and authentication details
$apiBaseUrl = "https://${domain}:7300/api/v1"
$loginUrl = "$apiBaseUrl/login"

# Function to get user token
function Get-UserToken {
    param (
        [string]$userid,
        [SecureString]$securePassword,
        [string]$plainApiKey
    )
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    $headers = @{
        "X-Api-Key" = "$plainApiKey"
    }
    $body = @{
        authtype = 0
        userid   = $userid
        password = $password
    }
    try {
        Write-Log "Requesting user token."
        $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Headers $headers -ContentType "application/x-www-form-urlencoded" -Body $body -SkipCertificateCheck
        Write-Log "User token obtained successfully."
        return $response.token.access_token
    } catch {
        Write-Log "Error obtaining user token: $_" -level "ERROR"
        exit 1
    }
}

# Get the user token
$token = Get-UserToken -userid $userid -securePassword $securePassword -plainApiKey $plainApiKey

# Read the CSV file and process each user
$csvData = Import-Csv -Path $outputCsv

$lineNumber = 0

foreach ($row in $csvData) {
    $lineNumber++
    $username = $row.$fieldSelection

    # Check if the username field is empty and log if necessary
    if (-not $username) {
        Write-Log "Line $lineNumber of the CSV contains an entry that is missing the username ($fieldSelection)." -level "WARNING"
        continue
    }

    # Construct the URL with the username and providerId
    $url = "${apiBaseUrl}/users/${username}?providerid=${providerId}"

    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Deleting user $username."
        Invoke-RestMethod -Uri $url -Headers $headers -Method Delete -SkipCertificateCheck
        Write-Log "Deleted user ${username} successfully."
    } catch {
        Write-Log "Failed to delete user ${username}: $_" -level "ERROR"
        Write-ErrorDetails
    }
}

# Log completion
Write-Log "Script execution completed."

# Helper function to write error details
function Write-ErrorDetails {
    if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Log "Error details: $responseBody" -level "ERROR"
    }
}
