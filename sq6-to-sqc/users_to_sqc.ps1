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

# Function to get or create configuration
function Get-Configuration {
    if (-Not (Test-Path $configFilePath)) {
        Write-Log "Configuration file not found. Creating a new one." -level "INFO"
        $config = @{}  # Initialize as a hashtable
    } else {
        $config = Get-Content -Path $configFilePath | ConvertFrom-Json
    }

    # Ensure the configuration is a hashtable to allow dynamic properties
    $config = [hashtable]$config

    if (-not $config.ContainsKey('ProviderId') -or -not $config['ProviderId']) {
        $config['ProviderId'] = Read-Host "Enter the Provider ID"
    }

    if (-not $config.ContainsKey('Domain') -or -not $config['Domain']) {
        $config['Domain'] = Read-Host "Enter your SafeQ Cloud domain (eg. customer.au.ysoft.cloud)"
    }

    if (-not $config.ContainsKey('ApiKey') -or -not $config['ApiKey']) {
        $plainApiKey = Read-Host "Enter your API Key"
        $config['ApiKey'] = (ConvertTo-SecureString -String $plainApiKey -AsPlainText -Force) | ConvertFrom-SecureString
    }

    if (-not $config.ContainsKey('ApiUsername') -or -not $config['ApiUsername']) {
        $config['ApiUsername'] = Read-Host "Enter your API Username"
    }

    if (-not $config.ContainsKey('ApiPassword') -or -not $config['ApiPassword']) {
        $securePassword = Read-Host "Enter your API Password" -AsSecureString
        $config['ApiPassword'] = $securePassword | ConvertFrom-SecureString
    }

    # Write back the updated configuration to the file
    $config | ConvertTo-Json -Depth 32 | Set-Content -Path $configFilePath -Force

    return $config
}

# Load configuration
$config = Get-Configuration

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

# Function to update user details using query parameters
function Update-UserDetails {
    param (
        [string]$username,
        [string]$fullName,
        [string]$email,
        [string]$alias,
        [string]$pinOrCard
    )

    $details = ""
    if ($fullName) {
        $details += "&fullName=$($fullName -replace ' ', '%20')"
    }
    if ($email) {
        $details += "&email=$($email -replace ' ', '%20')"
    }
    if ($pinOrCard -notlike "PIN*") {
        $details += "&cardId=$($pinOrCard)"
    }
    if ($pinOrCard -like "PIN*") {
        $details += "&pin=$($pinOrCard.Substring(3))"
    }

    $url = "$apiBaseUrl/users/$username?providerId=$providerId$details"
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Updating user details at URL: $url with headers: $($headers | ConvertTo-Json)"
        Invoke-RestMethod -Uri $url -Headers $headers -Method Put -SkipCertificateCheck
        Write-Log "Updated user ${username} successfully."
    } catch {
        Write-Log "Failed to update user ${username}: $_" -level "ERROR"
        if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Log "Error details: $responseBody" -level "ERROR"
        }
    }
}

# Function to create a new user using query parameters
function New-User {
    param (
        [string]$username,
        [string]$fullName,
        [string]$email,
        [string]$alias,
        [string]$pinOrCard
    )

    $details = "username=$username&providerId=$providerId"
    if ($fullName) {
        $details += "&fullName=$($fullName -replace ' ', '%20')"
    }
    if ($email) {
        $details += "&email=$($email -replace ' ', '%20')"
    }
    if ($pinOrCard -notlike "PIN*") {
        $details += "&cardId=$($pinOrCard)"
    }
    if ($pinOrCard -like "PIN*") {
        $details += "&pin=$($pinOrCard.Substring(3))"
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
        if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Log "Error details: $responseBody" -level "ERROR"
        }
    }
}

# Read the CSV file and process each user
$csvData = Import-Csv -Path $outputCsv

foreach ($row in $csvData) {
    $username = $row.$fieldSelection
    $fullName = $row.full_name
    $email = $row.email
    $alias = $row.alias
    $pinOrCard = $row.pin_or_card

    $user = Get-UserInformation -username $username

    if ($null -ne $user) {
        # User exists, update details
        Update-UserDetails -username $username -fullName $fullName -email $email -alias $alias -pinOrCard $pinOrCard
    } else {
        # User does not exist, create new user
        New-User -username $username -fullName $fullName -email $email -alias $alias -pinOrCard $pinOrCard
    }
}

# Log completion
Write-Log "Script execution completed."