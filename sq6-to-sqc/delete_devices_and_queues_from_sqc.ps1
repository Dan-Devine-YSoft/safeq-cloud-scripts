# Initialize log file
$logFilePath = "delete_devices_and_queues_from_sqc.log"
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
$inputPortsJsonPath = "inputports.json"
$outputPortsJsonPath = "outputports.json"

# Function to retrieve configuration
function Get-Configuration {
    if (-Not (Test-Path $configFilePath)) {
        Write-Log "Configuration file not found. Please run create_config.ps1 to create it." -level "ERROR"
        exit
    }
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json

    # Check for required configuration keys
    $requiredKeys = @('Domain', 'ApiKey', 'ApiUsername', 'ApiPassword')
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
$domain = $config.Domain
$plainApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $config.ApiKey)))
$userid = $config.ApiUsername
$securePassword = ConvertTo-SecureString -String $config.ApiPassword

# Define API base URLs
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
        Write-Log "Requesting user token with masked headers and body."
        $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Headers $headers -ContentType "application/x-www-form-urlencoded" -Body $body -SkipCertificateCheck
        Write-Log "User token obtained successfully."
        return $response.token.access_token
    } catch {
        Write-Log "Error obtaining user token at line $($MyInvocation.ScriptLineNumber): $_" -level "ERROR"
        exit 1
    }
}

# Get the user token
$token = Get-UserToken -userid $userid -securePassword $securePassword -plainApiKey $plainApiKey

# Function to delete input ports
function Delete-InputPorts {
    if (-Not (Test-Path $inputPortsJsonPath)) {
        Write-Log "No input ports found to delete." -level "INFO"
        return
    }

    $inputPortIds = Get-Content -Path $inputPortsJsonPath | ConvertFrom-Json

    if ($inputPortIds.Count -eq 0) {
        Write-Log "No input ports found to delete." -level "INFO"
        return
    }

    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    foreach ($inputPortId in $inputPortIds) {
        $inputPortUrl = "$apiBaseUrl/inputports/$inputPortId"
        try {
            Write-Log "Deleting input port ID $inputPortId."
            Invoke-RestMethod -Uri $inputPortUrl -Headers $headers -Method Delete -SkipCertificateCheck
            Write-Log "Successfully deleted input port ID $inputPortId."
        } catch {
            Write-Log "Failed to delete input port ID $inputPortId at line $($MyInvocation.ScriptLineNumber): $_" -level "ERROR"
            Write-ErrorDetails
        }
    }
}

# Function to delete output ports
function Delete-OutputPorts {
    if (-Not (Test-Path $outputPortsJsonPath)) {
        Write-Log "No output ports found to delete." -level "INFO"
        return
    }

    $outputPortIds = Get-Content -Path $outputPortsJsonPath | ConvertFrom-Json

    if ($outputPortIds.Count -eq 0) {
        Write-Log "No output ports found to delete." -level "INFO"
        return
    }

    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    foreach ($outputPortId in $outputPortIds) {
        $outputPortUrl = "$apiBaseUrl/outputports/$outputPortId"
        try {
            Write-Log "Deleting output port ID $outputPortId."
            Invoke-RestMethod -Uri $outputPortUrl -Headers $headers -Method Delete -SkipCertificateCheck
            Write-Log "Successfully deleted output port ID $outputPortId."
        } catch {
            Write-Log "Failed to delete output port ID $outputPortId at line $($MyInvocation.ScriptLineNumber): $_" -level "ERROR"
            Write-ErrorDetails
        }
    }
}

# Prompt the user to delete input ports
$deleteInputPorts = Read-Host "Do you want to delete all input ports (print queues) created by this script set? (y/n)"
if ($deleteInputPorts -eq "y") {
    Delete-InputPorts
} else {
    Write-Host "Exiting script."
    exit
}

# Prompt the user to delete output ports
$deleteOutputPorts = Read-Host "Do you want to delete all output ports (print queues) created by this script set? (y/n)"
if ($deleteOutputPorts -eq "y") {
    Delete-OutputPorts
}

# Exit the script
Write-Host "Exiting script."
Write-Log "Script execution completed."

