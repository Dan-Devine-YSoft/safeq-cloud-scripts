# Initialize log file
$logFilePath = "users_to_sqc.log"
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

# Function to load configuration
function Load-Configuration {
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
$config = Load-Configuration

# Extract configuration values
$outputCsv = $config.csvFileName
$providerId = $config.ProviderId
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
        Write-Log "Requesting user token at URL: $loginUrl with headers: $($headers | ConvertTo-Json) and body: $($body | ConvertTo-Json)"
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

# Function to get user information
function Get-UserInformation {
    param (
        [string]$username
    )

    $url = "$apiBaseUrl/users?username=$username&providerid=$providerId"
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Getting user information at URL: $url with headers: $($headers | ConvertTo-Json)"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -SkipCertificateCheck
        Write-Log "User information retrieved successfully for ${username}."
        return $response
    } catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -match "not found") {
            Write-Log "User with username=$username and providerId=$providerId not found." -level "INFO"
            return $null
        } else {
            Write-Log "Failed to get user information for ${username}: $_" -level "ERROR"
            if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                Write-Log "Error details: $responseBody" -level "ERROR"
            }
            return $null
        }
    }
}

# Function to update user details one at a time
function Update-UserDetails {
    param (
        [string]$username,
        [string]$fullName,
        [string]$email,
        [string]$alias,
        [string]$pin,
        [string]$cardNumber,
        [PSCustomObject]$currentUser
    )

    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    # Check and update only fields that differ from the current user details
    if ($fullName -and $fullName -ne $currentUser.fullName) {
        $url = "$apiBaseUrl/users/$username?providerId=$providerId&fullName=$($fullName -replace ' ', '%20')"
        try {
            Write-Log "Updating user's fullName at URL: $url with headers: $($headers | ConvertTo-Json)"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Put -SkipCertificateCheck
            Write-Log "Updated fullName for user ${username} successfully."
        } catch {
            Write-Log "Failed to update fullName for user ${username}: $_" -level "ERROR"
            Log-ErrorDetails
        }
    }

    if ($email -and $email -ne $currentUser.email) {
        $url = "$apiBaseUrl/users/$username?providerId=$providerId&email=$($email -replace ' ', '%20')"
        try {
            Write-Log "Updating user's email at URL: $url with headers: $($headers | ConvertTo-Json)"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Put -SkipCertificateCheck
            Write-Log "Updated email for user ${username} successfully."
        } catch {
            Write-Log "Failed to update email for user ${username}: $_" -level "ERROR"
            Log-ErrorDetails
        }
    }

    if ($cardNumber -and ($null -eq $currentUser.cards -or $cardNumber -notin $currentUser.cards)) {
        $url = "$apiBaseUrl/users/$username?providerId=$providerId&cardId=$cardNumber"
        try {
            Write-Log "Updating user's cardId at URL: $url with headers: $($headers | ConvertTo-Json)"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Put -SkipCertificateCheck
            Write-Log "Updated cardId for user ${username} successfully."
        } catch {
            Write-Log "Failed to update cardId for user ${username}: $_" -level "ERROR"
            Log-ErrorDetails
        }
    }

    if ($pin -and $pin -ne $currentUser.pin) {
        $url = "$apiBaseUrl/users/$username?providerId=$providerId&pin=$pin"
        try {
            Write-Log "Updating user's pin at URL: $url with headers: $($headers | ConvertTo-Json)"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Put -SkipCertificateCheck
            Write-Log "Updated pin for user ${username} successfully."
        } catch {
            Write-Log "Failed to update pin for user ${username}: $_" -level "ERROR"
            Log-ErrorDetails
        }
    }
}

# Helper function to log error details
function Log-ErrorDetails {
    if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Log "Error details: $responseBody" -level "ERROR"
    }
}

# Function to create a new user using query parameters
# Function to create a new user using query parameters
function New-User {
    param (
        [string]$username,
        [string]$fullName,
        [string]$email,
        [string]$alias,
        [string]$pin,
        [string]$cardNumber
    )

    $details = "username=$username&providerId=$providerId"
    if ($fullName) {
        $details += "&fullName=$($fullName -replace ' ', '%20')"
    }
    if ($email) {
        $details += "&email=$($email -replace ' ', '%20')"
    }
    if ($cardNumber) {
        $details += "&cardId=$($cardNumber)"
    }
    if ($pin) {
        $details += "&pin=$($pin)"
    }

    $url = "$apiBaseUrl/users?$details"
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Creating user at URL: $url with headers: $($headers | ConvertTo-Json)"
        Invoke-RestMethod -Uri $url -Headers $headers -Method Post -SkipCertificateCheck
        Write-Log "Created user ${username} successfully."
    } catch {
        Write-Log "Failed to create user ${username}: $_" -level "ERROR"
        Log-ErrorDetails
    }
}

# Read the CSV file and process each user
$csvData = Import-Csv -Path $outputCsv

$lineNumber = 0

foreach ($row in $csvData) {
    $lineNumber++
    $username = $row.$fieldSelection
    $fullName = $row.full_name
    $email = $row.email
    $alias = $row.alias
    $pin = if ($row.pin -ne "") { $row.pin } else { $null }
    $cardNumber = if ($row.card_number -ne "") { $row.card_number } else { $null }

    # Check if the username field is empty and log if necessary
    if (-not $username) {
        Write-Log "Line $lineNumber of the CSV contains an entry that is missing the username ($fieldSelection)." -level "WARNING"
        continue
    }

    $user = Get-UserInformation -username $username

    if ($null -ne $user) {
        # User exists, update details
        Update-UserDetails -username $username -fullName $fullName -email $email -alias $alias -pin $pin -cardNumber $cardNumber -currentUser $user
    } else {
        # User does not exist, create new user
        New-User -username $username -fullName $fullName -email $email -alias $alias -pin $pin -cardNumber $cardNumber
    }
}

# Log completion
Write-Log "Script execution completed."