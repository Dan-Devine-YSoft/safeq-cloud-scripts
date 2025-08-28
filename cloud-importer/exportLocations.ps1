# Export Locations Script - exportLocations.ps1
# This script exports locations from the locations.json file to a .csv file

# Force working directory to script location
Set-Location -Path $PSScriptRoot

# Prompt user for export filename
$exportFileName = Read-Host "Enter filename for export (press Enter for default 'exported_locations.csv')"
if ([string]::IsNullOrWhiteSpace($exportFileName)) {
    $exportFileName = 'exported_locations.csv'
}

$apiConfig = Get-Content .\apiconfig.json | ConvertFrom-Json
$apiKey = $apiConfig.apiKey
$baseURL = "https://$($apiConfig.cloudTenancyAddress):7300/api/v1"

$output = @()

# Load existing locations file if it exists, otherwise create empty hashtable
$json = @{}
if (Test-Path .\locations.json) {
    $json = Get-Content .\locations.json | ConvertFrom-Json -AsHashtable
}

foreach ($id in $json.Keys) {
    try {
        # Retrieve location details from API
        $response = Invoke-RestMethod -Uri "$baseURL/locations/$id" -Method Get -Headers @{"X-Api-Key"=$apiKey} -ContentType 'application/json'

        # Process identifiers based on locationType
        foreach ($identifier in $response.identifiers) {
            foreach ($data in $identifier.stringData) {
                $gatewayData = ""
                $subnetData = ""
                $ipRangeData = ""
                $wifiData = ""

                switch ($identifier.locationType) {
                    1 { $gatewayData = $data }
                    2 { $subnetData = $data }
                    3 { $ipRangeData = $data }
                    4 { $wifiData = $data }
                }

                # Append location data to output
                $output += [PSCustomObject]@{
                    locationId = $id
                    locationName = $response.name
                    locationGatewayData = $gatewayData
                    locationSubnetData = $subnetData
                    locationIpRangeData = $ipRangeData
                    locationWifiData = $wifiData
                }
            }
        }
    } catch {
        Write-Host "Error exporting location with ID: $id - $_"
    }
    Start-Sleep -Seconds 1 # Rate limit to 1 API request per second
}

# Export results to CSV
$output | Export-Csv -Path .\$exportFileName -NoTypeInformation
Write-Host "Export completed successfully to $exportFileName."

# Return to main menu
& .\manageLocations.ps1