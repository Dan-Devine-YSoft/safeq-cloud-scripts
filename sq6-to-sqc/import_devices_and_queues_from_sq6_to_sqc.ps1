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
$outputPortsJsonPath = "outputports.json"
$inputPortsJsonPath = "inputports.json"

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
        Write-Log "Error obtaining user token at line $($MyInvocation.ScriptLineNumber): $_" -level "ERROR"
        exit 1
    }
}

# Get the user token
$token = Get-UserToken -userid $userid -securePassword $securePassword -plainApiKey $plainApiKey

# Function to retrieve existing output ports
function Get-ExistingOutputPorts {
    param (
        [string]$token,
        [string]$plainApiKey
    )

    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Retrieving existing output ports with masked headers."
        $response = Invoke-RestMethod -Uri $outputPortsUrl -Headers $headers -Method Get -SkipCertificateCheck
        Write-Log "Successfully retrieved existing output ports."

        # Convert response to hash table using the address as the key
        $existingOutputPorts = @{}
        foreach ($port in $response) {
            $existingOutputPorts[$port.address] = $port.id
        }
        return $existingOutputPorts
    } catch {
        Write-Log "Failed to retrieve existing output ports at line $($MyInvocation.ScriptLineNumber): $_" -level "ERROR"
        Write-ErrorDetails
        return @{}
    }
}

# Function to retrieve existing input ports
function Get-ExistingInputPorts {
    param (
        [string]$token,
        [string]$plainApiKey
    )

    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "Retrieving existing input ports with masked headers."
        $response = Invoke-RestMethod -Uri $inputPortsUrl -Headers $headers -Method Get -SkipCertificateCheck

        Write-Log "Successfully retrieved existing input ports."

        # Convert response to hash table using the name as the key, filtering only portType 1
        $existingInputPorts = @{}
        foreach ($port in $response) {
            if ($port.portType -eq 1) {
                $existingInputPorts[$port.name] = $port.id
            }
        }

        # Log the existing input ports
        Write-Log "Existing Input Ports: $($existingInputPorts.Keys -join ', ')"

        return $existingInputPorts
    } catch {
        Write-Log "Failed to retrieve existing input ports: $_" -level "ERROR"
        Write-ErrorDetails
        return @{}
    }
}

# Helper function to write error details
function Write-ErrorDetails {
    if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Log "Error details at line $($MyInvocation.ScriptLineNumber): $responseBody" -level "ERROR"
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
        [string]$vendor,
        [hashtable]$existingOutputPorts,
        [ref]$outputPortIds
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

    # Check if output port already exists
    if ($existingOutputPorts.ContainsKey($networkAddress)) {
        $outputPortId = $existingOutputPorts[$networkAddress]
        $body += "id=$outputPortId"
        $logMessage = "Updating output port $name."
    } else {
        $logMessage = "Creating output port $name."
    }

    foreach ($key in $vendorParams.Keys) {
        $body += "$key=$($vendorParams[$key])"
    }

    $bodyString = [String]::Join("&", $body)
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "$logMessage Sending request with masked headers."
        $response = Invoke-RestMethod -Uri $outputPortsUrl -Headers $headers -Method Put -ContentType "application/x-www-form-urlencoded" -Body $bodyString -SkipCertificateCheck
        Write-Log "Successfully processed output port $name."

        # If it's a new output port, store the ID
        if (-not $existingOutputPorts.ContainsKey($networkAddress)) {
            $outputPortId = $response.id
            $outputPortIds.Value += $outputPortId
        }

        # Return the ID of the output port
        return $outputPortId
    } catch {
        Write-Log "Failed to process output port ${name} at line $($MyInvocation.ScriptLineNumber): $_" -level "ERROR"
        Write-ErrorDetails
    }
}

# Function to create or update input ports and associate with output ports
function Set-InputPort {
    param (
        [string]$portName,
        [string]$outputPortId,
        [hashtable]$existingInputPorts,
        [ref]$inputPortIds
    )

    # Log the port name being checked
    Write-Log "Checking if input port $portName exists."

    # Prepare the form-encoded body for input ports
    $body = @()
    $body += "domainname=$domain"
    $body += "portname=$portName"
    $body += "porttype=1"
    $body += "outputportid=$outputPortId"
    $body += "portFlags=1"

    # Check if input port already exists
    if ($existingInputPorts.ContainsKey($portName)) {
        $inputPortId = $existingInputPorts[$portName]
        $body += "id=$inputPortId"
        $logMessage = "Updating input port $portName."
    } else {
        $logMessage = "Creating input port $portName."
    }

    $bodyString = [String]::Join("&", $body)
    $headers = @{
        "Authorization" = "Bearer $token"
        "X-Api-Key"     = "$plainApiKey"
    }

    try {
        Write-Log "$logMessage Sending request with masked headers."
        $response = Invoke-RestMethod -Uri $inputPortsUrl -Headers $headers -Method Put -ContentType "application/x-www-form-urlencoded" -Body $bodyString -SkipCertificateCheck
        Write-Log "Successfully processed input port $portName."

        # If it's a new input port, store the ID
        if (-not $existingInputPorts.ContainsKey($portName)) {
            $inputPortId = $response.id
            $inputPortIds.Value += $inputPortId
        }
    } catch {
        Write-Log "Failed to process input port ${portName}: $_" -level "ERROR"
        Write-ErrorDetails
    }
}

# Read the CSV file and process each device
$csvData = Import-Csv -Path $config.csvDeviceFileName

# Retrieve existing ports
$existingOutputPorts = Get-ExistingOutputPorts -token $token -plainApiKey $plainApiKey
$existingInputPorts = Get-ExistingInputPorts -token $token -plainApiKey $plainApiKey

# Initialize arrays to store new IDs
$outputPortIds = [ref]@()
$inputPortIds = [ref]@()

foreach ($row in $csvData) {
    $name = $row.name
    $networkAddress = $row.network_address
    $networkPort = $row.network_port
    $serialNumber = $row.serial_number
    $vendor = $row.vendor

    # Set output port and retrieve output port ID
    $outputPortId = Set-OutputPort -name $name -networkAddress $networkAddress -serialNumber $serialNumber -vendor $vendor -existingOutputPorts $existingOutputPorts -outputPortIds $outputPortIds

    # Set input ports for each direct queue and associate with the output port
    $queueIndex = 1
    while ($row.PSObject.Properties["direct_queue_$queueIndex"]) {
        $portName = $row.PSObject.Properties["direct_queue_$queueIndex"].Value
        if ($portName) {
            Set-InputPort -portName $portName -outputPortId $outputPortId -existingInputPorts $existingInputPorts -inputPortIds $inputPortIds
        }
        $queueIndex++
    }
}

# Save the new output and input port IDs to JSON files
$outputPortIds.Value | ConvertTo-Json | Set-Content -Path $outputPortsJsonPath
$inputPortIds.Value | ConvertTo-Json | Set-Content -Path $inputPortsJsonPath

Write-Log "Output port IDs saved to $outputPortsJsonPath"
Write-Log "Input port IDs saved to $inputPortsJsonPath"

# Log completion
Write-Log "Script execution completed."

