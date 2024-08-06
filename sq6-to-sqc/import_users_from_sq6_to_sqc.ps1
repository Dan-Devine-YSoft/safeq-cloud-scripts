# Initialize log file
$logFilePath = "import_users_from_sq6_to_sqc.log"
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
        Write-Log "Requesting user token at URL: $loginUrl with masked headers and body."
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
        Write-Log "Getting user information at URL: $url with masked headers."
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

# Helper function to write error details
function Write-ErrorDetails {
    if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Log "Error details: $responseBody" -level "ERROR"
    }
}

# Function to create a new user using form-encoded body
function Set-User {
    param (
        [string]$username,
        [string]$fullName,
        [string]$email,
        [string]$pin,
        [string]$cardNumber
    )

    # Prepare the form-encoded body for user creation
    $detailTypeMap = @{
        "fullName" = 0
        "email" = 1
        "cardNumber" = 4
        "pin" = 5
    }

    $body = @()
    $body += "username=$username"
    $body += "providerid=$providerId"

    # Add each user detail with its corresponding detailtype and detaildata
    $details = @{
        fullName = $fullName
        email = $email
        cardNumber = $cardNumber
        pin = $pin
    }

    foreach ($key in $details.Keys) {
        if ($details[$key]) {
            $detailType = $detailTypeMap[$key]
            $detailData = $details[$key]
            $body += "detailtype=$detailType"
            $body += "detaildata=$detailData"
        }
    }

    $bodyString = [String]::Join("&", $body)
    $url = "$apiBaseUrl/users"
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Sending request for user $username with masked headers."
        Invoke-RestMethod -Uri $url -Headers $headers -Method Put -ContentType "application/x-www-form-urlencoded" -Body $bodyString -SkipCertificateCheck
        Write-Log "Created user ${username} successfully."

        # Record created user ID in users.json
        $createdUserIds = @($username)
        $userJsonPath = "users.json"
        if (Test-Path $userJsonPath) {
            $existingUserIds = Get-Content -Path $userJsonPath | ConvertFrom-Json
            $createdUserIds += $existingUserIds
        }
        $createdUserIds | ConvertTo-Json | Set-Content -Path $userJsonPath -Force
    } catch {
        Write-Log "Failed to create user ${username}: $_" -level "ERROR"
        Write-ErrorDetails
    }
}

# Function to update an existing user using form-encoded body
function Update-User {
    param (
        [string]$username,
        [string]$currentFullName,
        [string]$currentEmail,
        [string[]]$currentCardNumbers,
        [string]$currentPin,
        [string]$newFullName,
        [string]$newEmail,
        [string]$newCardNumber,
        [string]$newPin
    )

    # Prepare the form-encoded body for updating user details
    $detailTypeMap = @{
        "fullName" = 0
        "email" = 1
        "cardNumber" = 4
        "pin" = 5
    }

    $url = "$apiBaseUrl/users/$username"
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    # Update each detail type if necessary
    $details = @{
        fullName = if ($currentFullName -ne $newFullName) { $newFullName } else { $null }
        email = if ($currentEmail -ne $newEmail) { $newEmail } else { $null }
        cardNumber = if ($currentCardNumbers -notcontains $newCardNumber) { $newCardNumber } else { $null }
        pin = if ($currentPin -ne $newPin) { $newPin } else { $null }
    }

    foreach ($key in $details.Keys) {
        if ($details[$key]) {
            $body = @()
            $body += "providerid=$providerId"
            $detailType = $detailTypeMap[$key]
            $detailData = $details[$key]
            $body += "detailtype=$detailType"
            $body += "detaildata=$detailData"
            $bodyString = [String]::Join("&", $body)

            try {
                Write-Log "Updating $key for user $username with masked headers."
                Invoke-RestMethod -Uri $url -Headers $headers -Method Post -ContentType "application/x-www-form-urlencoded" -Body $bodyString -SkipCertificateCheck
                Write-Log "Updated $key for user ${username} successfully."
            } catch {
                Write-Log "Failed to update $key for user ${username}: $_" -level "ERROR"
                Write-ErrorDetails
            }
        }
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
    $pin = if ($row.pin -ne "") { $row.pin } else { $null }
    $cardNumber = if ($row.card_number -ne "") { $row.card_number } else { $null }

    # Check if the username field is empty and log if necessary
    if (-not $username) {
        Write-Log "Line $lineNumber of the CSV contains an entry that is missing the username ($fieldSelection)." -level "WARNING"
        continue
    }

    # Get user information
    $user = Get-UserInformation -username $username

    if ($null -eq $user) {
        # User does not exist, create a new user
        Set-User -username $username -fullName $fullName -email $email -pin $pin -cardNumber $cardNumber
    } else {
        # User exists, update details
        $currentFullName = $user.fullName
        $currentEmail = $user.email
        $currentCardNumbers = $user.cards
        $currentPin = $user.pin

        Update-User -username $username `
                    -currentFullName $currentFullName `
                    -currentEmail $currentEmail `
                    -currentCardNumbers $currentCardNumbers `
                    -currentPin $currentPin `
                    -newFullName $fullName `
                    -newEmail $email `
                    -newCardNumber $cardNumber `
                    -newPin $pin
    }
}

# Log completion
Write-Log "Script execution completed."
