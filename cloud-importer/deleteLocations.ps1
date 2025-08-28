# Delete Locations Script - DeleteLocations.ps1
# This script deletes all locations in the locations.json file
# If you don't have location data in the json file, use the export locations option first

# Force working directory to script location
Set-Location -Path $PSScriptRoot

$logFile = "$PSScriptRoot\deleteLocations.log"

$apiConfig = Get-Content .\apiconfig.json | ConvertFrom-Json
$apiKey = $apiConfig.apiKey
$baseURL = "https://$($apiConfig.cloudTenancyAddress):7300/api/v1"

# Load existing locations file if it exists, otherwise create empty hashtable
$json = @{}
if (Test-Path .\locations.json) {
    $json = Get-Content .\locations.json | ConvertFrom-Json -AsHashtable
}

# Summarize count of locations
$locationCount = $json.Count
Write-Host "This operation will delete the $locationCount locations you have currently configured in the cloud tenancy."
Add-Content -Path $logFile -Value "Starting deletion process for $locationCount locations."

# Confirm with the user
$confirm = Read-Host "Are you sure you want to do this? (y/n) [Default: n]"
if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -ne 'y') {
    Write-Host "Operation canceled. Returning to main menu."
    & .\manageLocations.ps1
    exit
}

# Proceed with deletion
$keysToDelete = $json.Keys | ForEach-Object { $_ } # Make a static copy of keys

foreach ($id in $keysToDelete) {
    $idString = $id.ToString()

    # Ensure ID is numeric
    if ($idString -notmatch '^[0-9]+$') {
        Add-Content -Path $logFile -Value "Skipping invalid ID: $idString"
        continue
    }

    try {
        # Attempt API deletion
        $response = Invoke-RestMethod -Uri "$baseURL/locations/$idString" -Method Delete -Headers @{"X-Api-Key"=$apiKey} -ContentType 'application/json'

        if ($response.errorCode -eq 0) {
            Write-Host "Successfully deleted location with ID: $idString"
            Add-Content -Path $logFile -Value "Deleted: $idString - Response: $($response | ConvertTo-Json -Depth 10)"

            # Remove entry only if API call is successful
            $json.Remove($idString)
        } else {
            Write-Host "Error deleting location with ID: $idString - ErrorCode: $($response.errorCode)"
            Add-Content -Path $logFile -Value "Error: $idString - Response: $($response | ConvertTo-Json -Depth 10)"
        }
    } catch {
        Write-Host "Error deleting location with ID: $idString"
        Add-Content -Path $logFile -Value "Error: $idString - $_"
    }
    Start-Sleep -Milliseconds 250 # Rate limit to 4 API requests per second
}

# Save the updated JSON file
$jsonString = $json.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ $_.Key = $_.Value } } | ConvertTo-Json -Depth 10
$jsonString | Out-File .\locations.json
Write-Host "Locations deleted successfully where applicable. JSON file updated."
Add-Content -Path $logFile -Value "Deletion process completed. JSON file updated."

# Return to main menu
& .\manageLocations.ps1
