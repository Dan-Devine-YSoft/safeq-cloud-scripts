# Create Embedded Devices - createEmbeddedDevices.ps1

# Force working directory to script location
Set-Location -Path $PSScriptRoot

$logFile = "$PSScriptRoot\createEmbeddedDevices.log"

$apiConfig = Get-Content .\apiconfig.json | ConvertFrom-Json
$apiKey = $apiConfig.apiKey
$cloudTenancyAddress = $apiConfig.cloudTenancyAddress
$baseURL = "https://$($cloudTenancyAddress):7300/api/v1"

# Load locations data for subnet matching
$locationsJson = Get-Content .\locations.json | ConvertFrom-Json -AsHashtable

# Initialize or load existing devices JSON
$devicesJson = @{}
if (Test-Path .\createdDevices.json) {
    $devicesJson = Get-Content .\createdDevices.json | ConvertFrom-Json -AsHashtable
}

# Function to check if IP is in subnet
function Test-IpInSubnet {
    param (
        [string]$ip,
        [string]$subnet
    )
    
    try {
        $networkIP = $subnet.Split('/')[0]
        $maskLength = [int]$subnet.Split('/')[1]
        
        $ipBytes = ([System.Net.IPAddress]::Parse($ip)).GetAddressBytes()
        $networkBytes = ([System.Net.IPAddress]::Parse($networkIP)).GetAddressBytes()
        
        if ($ipBytes.Length -ne $networkBytes.Length) {
            return $false
        }
        
        $mask = [UInt32]([Math]::Pow(2, $maskLength) - 1) -shl (32 - $maskLength)

        $ipBits = ([UInt32]$ipBytes[0] -shl 24) -bor `
                  ([UInt32]$ipBytes[1] -shl 16) -bor `
                  ([UInt32]$ipBytes[2] -shl 8) -bor `
                  [UInt32]$ipBytes[3]

        $networkBits = ([UInt32]$networkBytes[0] -shl 24) -bor `
                      ([UInt32]$networkBytes[1] -shl 16) -bor `
                      ([UInt32]$networkBytes[2] -shl 8) -bor `
                      [UInt32]$networkBytes[3]

        return ($ipBits -band $mask) -eq ($networkBits -band $mask)
    }
    catch {
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [ERROR] Error in subnet calculation: $_"
        return $false
    }
}

# Function to find location ID for an IP address
function Get-LocationIdForIp {
    param (
        [string]$ipAddress
    )
    
    foreach ($locationId in $locationsJson.Keys) {
        $location = $locationsJson[$locationId]

        foreach ($identifier in $location.identifiers) {
            if ($identifier.locationType -eq 2) {  # Subnet type
                foreach ($subnet in $identifier.stringData) {
                    $result = Test-IpInSubnet -ip $ipAddress -subnet $subnet

                    if ($result) {
                        return $locationId
                    }
                }
            }
        }
    }
    return $null
}

# Function to handle API response errors
function Test-APIError {
    param (
        [PSCustomObject]$response,
        [string]$deviceName,
        [string]$operation
    )

    if ($response.errorCode -eq 1050) {
        $errorMessage = "License limit exceeded. Please check your device license count in the cloud tenant to make sure you have available device licenses."
        Write-Host "Error creating $operation for $deviceName - $errorMessage" -ForegroundColor Red
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [ERROR] Failed to create $operation for ${deviceName}: License limit exceeded (Error 1050)"
        return $false
    }
    elseif ($response.errorCode -ne 0) {
        Write-Host "Error creating $operation for $deviceName - ErrorCode: $($response.errorCode)" -ForegroundColor Yellow
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [ERROR] Failed to create $operation for ${deviceName}: $($response | ConvertTo-Json)"
        return $false
    }

    return $true
}

# Prompt user for CSV filename
$csvFileName = Read-Host "Enter CSV filename to parse (press Enter for default 'devices.csv')"
if ([string]::IsNullOrWhiteSpace($csvFileName)) {
    $csvFileName = 'devices.csv'
}

# Prompt for device type (only once)
$createEmbedded = Read-Host "Do you want to create embedded device records? (y/n)"
$createEmbedded = $createEmbedded.ToLower() -eq 'y'

# Prompt for print queue creation 
$createPrintQueues = Read-Host "Do you want a direct print queue created for each device? (y/n)"
$createPrintQueues = $createPrintQueues.ToLower() -eq 'y'

# Prompt for whether queues should be available by default
$printQueuesDefault = Read-Host "Do you want print queues to be available by default? (y/n)"
$printQueuesDefault = $printQueuesDefault.ToLower() -eq 'y'

# Read CSV data
$csvData = Import-Csv .\$csvFileName

# Process each row
foreach ($row in $csvData) {
    # Validate required fields - IP and Name are mandatory
    if ([string]::IsNullOrWhiteSpace($row.deviceIpAddress) -or 
        [string]::IsNullOrWhiteSpace($row.deviceName)) {
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [WARNING] Missing required data (IP or Name) for this row: $($row | ConvertTo-Json)"
        continue
    }

    # Optional deviceSerial - set to empty string if not provided
    if ([string]::IsNullOrWhiteSpace($row.deviceSerial)) {
        $row.deviceSerial = ""
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [INFO] No serial number provided for device: $($row.deviceName)"
    }

    try {
        # Step 1: Create device record
        $deviceBody = @{
            domainname = $cloudTenancyAddress
            portname = $row.deviceName
            address = $row.deviceIpAddress
            porttype = 1
            deviceserial = $row.deviceSerial
            vendor = "km"
            modelfamily = 1
            printprotocol = 0
            outputtype = 4
        }

        # Add embedded device properties if requested
        if ($createEmbedded) {
            $deviceBody.embedded = $true
            $deviceBody.embeddedconfiguration = 549 # Set this to the required configuration
            $formData = ($deviceBody.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$($_.Value)"
            }) -join "&"
            
            # Append embedded service IDs
            $formData = $formData + "&serviceid=100&serviceid=3"
        }
        else {
            $formData = ($deviceBody.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$($_.Value)"
            }) -join "&"
        }

        $deviceResponse = Invoke-RestMethod -Uri "$baseURL/outputports" `
            -Method Post `
            -Headers @{"X-Api-Key"=$apiKey} `
            -Body $formData `
            -ContentType 'application/x-www-form-urlencoded'

        # Check for errors in device creation
        if (-not (Test-APIError -response $deviceResponse -deviceName $row.deviceName -operation "device record")) {
            continue
        }

        $returnedDeviceId = $deviceResponse.id
        Write-Host "Created device record for $($row.deviceName) with ID: $returnedDeviceId"

        # Initialize device JSON object
        $deviceJsonObject = @{
            deviceId = $returnedDeviceId
            deviceName = $row.deviceName
            deviceSerial = $row.deviceSerial
            deviceIpAddress = $row.deviceIpAddress
            created = (Get-Date).ToString("o")
        }

        if ($createPrintQueues) {
            # Step 2: Find location ID based on IP address
            $locationId = Get-LocationIdForIp -ipAddress $row.deviceIpAddress
            if (-not $locationId) {
                Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [WARNING] Skipping queue creation for $($row.deviceName) ($($row.deviceIpAddress)) - No matching subnet found in locations.json"
                Write-Host "Skipping queue creation for $($row.deviceName) - No matching subnet found"
            }
            else {
                # Step 3: Create print queue record
                $queueBody = @{
                    domainname = $cloudTenancyAddress
                    portname = $row.deviceName
                    porttype = 1
                    outputportid = $returnedDeviceId
                    locationid = $locationId
                    portFlags = if ($printQueuesDefault) { 1 } else { 0 } 
                }

                # Convert queue body to form data format
                $queueFormData = ($queueBody.GetEnumerator() | ForEach-Object {
                    if ($_.Value -is [array]) {
                        $_.Value | ForEach-Object { "$($_.Key)=$_" }
                    } else {
                        "$($_.Key)=$($_.Value)"
                    }
                }) -join "&"

                $queueResponse = Invoke-RestMethod -Uri "$baseURL/inputports" `
                    -Method Put `
                    -Headers @{"X-Api-Key"=$apiKey} `
                    -Body $queueFormData `
                    -ContentType 'application/x-www-form-urlencoded'

                # Check for errors in queue creation
                if (Test-APIError -response $queueResponse -deviceName $row.deviceName -operation "print queue") {
                    Write-Host "Created print queue for $($row.deviceName)"
                    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [INFO] Successfully processed device and queue: $($row.deviceName)"
                    
                    # Add queue ID to device JSON object only if queue was created successfully
                    $deviceJsonObject.queueId = $queueResponse.id
                }
            }
        }

        # Store device information in JSON
        $devicesJson[$row.deviceName] = $deviceJsonObject

    } catch {
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [ERROR] Exception processing $($row.deviceName): $_"
        Write-Host "Error processing $($row.deviceName): $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 250 # Rate limit to 4 API requests per second
}

# Save updated devices to JSON file
$devicesJson | ConvertTo-Json -Depth 10 | Out-File .\createdDevices.json
Write-Host "Processing completed. Check $logFile for details."
Write-Host "Device creation results saved to createdDevices.json"

# Return to main menu
& .\manageLocations.ps1