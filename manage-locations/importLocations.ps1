# Import Locations Script - importLocations.ps1

# Force working directory to script location
Set-Location -Path $PSScriptRoot

$logFile = "$PSScriptRoot\importLocations.log"

$apiConfig = Get-Content .\apiconfig.json | ConvertFrom-Json
$apiKey = $apiConfig.apiKey
$baseURL = "https://$($apiConfig.cloudTenancyAddress):7300/api/v1"

# Download existing locations from API
Write-Host "Fetching existing locations..."
$response = Invoke-RestMethod -Uri "$baseURL/locations" -Method Get -Headers @{"X-Api-Key"=$apiKey} -ContentType 'application/json' -SkipCertificateCheck
$existingLocations = @{}

if ($response) {
    foreach ($loc in $response) {
        $existingLocations[$loc.id] = $loc
    }
} else {
    Write-Host "No existing locations found in the API."
}

# Load existing locations file if it exists, otherwise create empty hashtable
$json = @{}
if (Test-Path .\locations.json) {
    $json = Get-Content .\locations.json | ConvertFrom-Json -AsHashtable
}

# Ensure $json is initialized as a hashtable
if (-not $json) {
    $json = @{}
}

# Update JSON with new locations from API if they don't already exist
foreach ($id in $existingLocations.Keys) {
    $idString = $id.ToString()
    if (-not $json.ContainsKey($idString)) {
        $json[$idString] = $existingLocations[$id]
        Add-Content -Path $logFile -Value "Imported: $($existingLocations[$id].name) - ID $id"
    } else {
        Add-Content -Path $logFile -Value "Skipped (already exists): $($existingLocations[$id].name) - ID $id"
    }
}

# Save updated locations.json
$json | ConvertTo-Json -Depth 10 | Out-File .\locations.json
Write-Host "Locations imported and saved successfully."

# Return to main menu
& .\manageLocations.ps1
