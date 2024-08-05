# To do -
# 1. check whether device exists first and if it does, then update rather than create
# 2. assign queue to device

# Initialize log file
$logFilePath = "import_devices_and_queues_from_sq6_to_sqc.log"
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
    $requiredKeys = @('Domain', 'ApiKey', 'ApiUsername', 'ApiPassword', 'csvDeviceFileName')
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
$outputPortsUrl = "${apiBaseUrl}/outputports"
$inputPortsUrl = "${apiBaseUrl}/inputports"

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
        Write-Log "Error obtaining user token: $_" -level "ERROR"
        exit 1
    }
}

# Get the user token
$token = Get-UserToken -userid $userid -securePassword $securePassword -plainApiKey $plainApiKey

# Helper function to write error details
function Write-ErrorDetails {
    if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Log "Error details: $responseBody" -level "ERROR"
    }
}

# Vendor conversion mapping
$vendorConversion = @{
    "UNDEFINED"        = "unknown"
    "EPSON"            = "epson"
    "HP"               = "hp"
    "KONICA_MINOLTA"   = "km"
    "KONICA_MINOLTA_BSI" = "km"
    "FUJI_XEROX"       = "fujifilm"
    "FUJI_XEROX_XCP"   = "fujifilm"
    "FUJIFILM_BI"      = "fujifilm"
    "FUJIFILM_BI_AIP7" = "fujifilm"
    "RICOH"            = "ricoh"
    "RICOH_SOP"        = "ricoh"
}

# Function to map vendor and add additional parameters
function Map-VendorParameters {
    param (
        [string]$vendor
    )
    $apiVendor = $vendorConversion[$vendor]    
    $parameters = @{}

    if ($vendor -eq "RICOH") {
        $parameters['modelfamily'] = 0
    } elseif ($vendor -eq "RICOH_SOP") {
        $parameters['modelfamily'] = 1
    }

    if ($vendor -in $vendorConversion.Keys) {
        $parameters['embedded'] = 'true'
    }

    return $parameters, $apiVendor
}

# Function to create or update output ports
function Set-OutputPort {
    param (
        [string]$name,
        [string]$networkAddress,
        [string]$serialNumber,
        [string]$vendor
    )

    $vendorParams, $apiVendor = Map-VendorParameters -vendor $vendor

    # Prepare the form-encoded body for output ports
    $body = @()
    $body += "domainname=$domain"
    $body += "portname=$name"
    $body += "address=$networkAddress"
    $body += "deviceserial=$serialNumber"
    $body += "vendor=$apiVendor"
    $body += "porttype=1"
    $body += "printprotocol=0"

    foreach ($key in $vendorParams.Keys) {
        $body += "$key=$($vendorParams[$key])"
    }

    $bodyString = [String]::Join("&", $body)
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Sending request for output port $name with masked headers."
        Invoke-RestMethod -Uri $outputPortsUrl -Headers $headers -Method Put -ContentType "application/x-www-form-urlencoded" -Body $bodyString -SkipCertificateCheck
        Write-Log "Created or updated output port $name successfully."
    } catch {
        Write-Log "Failed to create or update output port ${name}: $_" -level "ERROR"
        Write-ErrorDetails
    }
}

# Function to create input ports
function Set-InputPort {
    param (
        [string]$portName
    )

    # Prepare the form-encoded body for input ports
    $body = @()
    $body += "domainname=$domain"
    $body += "portname=$portName"
    $body += "porttype=1"

    $bodyString = [String]::Join("&", $body)
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Sending request for input port $portName with masked headers."
        Invoke-RestMethod -Uri $inputPortsUrl -Headers $headers -Method Put -ContentType "application/x-www-form-urlencoded" -Body $bodyString -SkipCertificateCheck
        Write-Log "Created input port $portName successfully."
    } catch {
        Write-Log "Failed to create input port ${portName}: $_" -level "ERROR"
        Write-ErrorDetails
    }
}

# Read the CSV file and process each device
$csvData = Import-Csv -Path $config.csvDeviceFileName

foreach ($row in $csvData) {
    $name = $row.name
    $networkAddress = $row.network_address
    $networkPort = $row.network_port
    $serialNumber = $row.serial_number
    $vendor = $row.vendor

    # Set output port
    Set-OutputPort -name $name -networkAddress $networkAddress -serialNumber $serialNumber -vendor $vendor

    # Set input ports for each direct queue
    $queueIndex = 1
    while ($row.PSObject.Properties["direct_queue_$queueIndex"]) {
        $portName = $row.PSObject.Properties["direct_queue_$queueIndex"].Value
        if ($portName) {
            Set-InputPort -portName $portName
        }
        $queueIndex++
    }
}

# Log completion
Write-Log "Script execution completed."
