# Delete Embedded Devices - deleteEmbeddedDevices.ps1

# Force working directory to script location
Set-Location -Path $PSScriptRoot

$logFile = "$PSScriptRoot\deleteEmbeddedDevices.log"

# Load API configuration
$apiConfig = Get-Content .\apiconfig.json | ConvertFrom-Json
$apiKey = $apiConfig.apiKey
$cloudTenancyAddress = $apiConfig.cloudTenancyAddress
$baseURL = "https://$($cloudTenancyAddress):7300/api/v1"

# Load existing devices file
$devicesJson = @{}
if (Test-Path .\createdDevices.json) {
    $devicesJson = Get-Content .\createdDevices.json | ConvertFrom-Json -AsHashtable
} else {
    Write-Host "No createdDevices.json file found. Nothing to delete."
    exit
}

# Summarize count of devices
$deviceCount = $devicesJson.Count
Write-Host "This operation will delete $deviceCount devices and their associated print queues from the cloud tenancy."
Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [INFO] Starting deletion process for $deviceCount devices and their print queues."

# Confirm with the user
$confirm = Read-Host "Are you sure you want to do this? (y/n) [Default: n]"
if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -ne 'y') {
    Write-Host "Operation canceled."
    exit
}

# Keep track of which records to remove
$recordsToRemove = @()

# Process each device
foreach ($deviceName in $devicesJson.Keys) {
    $device = $devicesJson[$deviceName]
    $success = $true
    
    try {
        # Delete print queue first
        if ($device.queueId) {
            $queueResponse = Invoke-RestMethod -Uri "$baseURL/inputports/$($device.queueId)" `
                -Method Delete `
                -Headers @{"X-Api-Key"=$apiKey}

            if ($queueResponse.errorCode -eq 0) {
                Write-Host "Successfully deleted print queue for device: $deviceName (Queue ID: $($device.queueId))"
                Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [INFO] Deleted print queue: $deviceName - Queue ID $($device.queueId)"
            } else {
                Write-Host "Error deleting print queue: $deviceName - ErrorCode: $($queueResponse.errorCode)"
                Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [ERROR] Error deleting print queue: $deviceName - Response: $($queueResponse | ConvertTo-Json)"
                $success = $false
            }
        }

        # Delete device
        $deviceResponse = Invoke-RestMethod -Uri "$baseURL/outputports/$($device.deviceId)" `
            -Method Delete `
            -Headers @{"X-Api-Key"=$apiKey}

        if ($deviceResponse.errorCode -eq 0) {
            Write-Host "Successfully deleted device: $deviceName (Device ID: $($device.deviceId))"
            Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [INFO] Deleted device: $deviceName - Device ID $($device.deviceId)"
        } else {
            Write-Host "Error deleting device: $deviceName - ErrorCode: $($deviceResponse.errorCode)"
            Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [ERROR] Error deleting device: $deviceName - Response: $($deviceResponse | ConvertTo-Json)"
            $success = $false
        }

        # If both operations succeeded, mark record for removal
        if ($success) {
            $recordsToRemove += $deviceName
        }

    } catch {
        Write-Host "Error processing deletion for device: $deviceName - $_"
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd-HH:mm:ss') [ERROR] Error processing deletion: $deviceName - $_"
    }
    
    Start-Sleep -Milliseconds 250 # Rate limit to 4 API requests per second
}

# Remove successfully deleted records from JSON
foreach ($recordName in $recordsToRemove) {
    $devicesJson.Remove($recordName)
}

# Save the updated JSON file if there are any remaining records
if ($devicesJson.Count -gt 0) {
    $devicesJson | ConvertTo-Json -Depth 10 | Out-File .\createdDevices.json
} else {
    # If no records remain, delete the file
    if (Test-Path .\createdDevices.json) {
        Remove-Item .\createdDevices.json
    }
}

Write-Host "Deletion process completed. Check $logFile for details."

# Return to main menu
& .\manageLocations.ps1