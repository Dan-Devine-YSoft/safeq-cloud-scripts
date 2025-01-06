# Create Locations Script - createLocations.ps1

# Type is one of the following:

# Type 1 - Gateway IPv4 - the ip address of the gateway on the network eg "192.168.0.1"
# Type 2 - Subnet IPv4 - the subnet of the network in CIDR notation eg "192.168.0.1/24"
# Type 3 - IP Range - a range of IP addresses eg "192.168.0.1-192.168.0.50"
# Type 4 - SSID - a wifi SSID eg "MyWifi"

# Dummy CSV format for locations.csv - one of the 'Data' fields MUST exist
# locationName,locationGatewayData,locationSubnetData,locationIpRangeData,locationWifiData
# Location1,,10.2.130.0/24,,
# Location2,192.168.1.1,,,

# Force working directory to script location
Set-Location -Path $PSScriptRoot

$logFile = "$PSScriptRoot\createLocations.log"

$apiConfig = Get-Content .\apiconfig.json | ConvertFrom-Json
$apiKey = $apiConfig.apiKey
$baseURL = "https://$($apiConfig.cloudTenancyAddress):7300/api/v1"

# Download existing locations from API
Write-Host "Fetching existing locations..."
$response = Invoke-RestMethod -Uri "$baseURL/locations" -Method Get -Headers @{"X-Api-Key"=$apiKey} -ContentType 'application/json'
$existingLocations = @{}

if ($response) {
    foreach ($loc in $response) {
        $existingLocations[$loc.id.ToString()] = $loc
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

# Prompt user for CSV filename
$csvFileName = Read-Host "Enter CSV filename to parse (press Enter for default 'locations.csv')"
if ([string]::IsNullOrWhiteSpace($csvFileName)) {
    $csvFileName = 'locations.csv'
}

# Read CSV data
$data = Import-Csv -Path .\$csvFileName

# Process each row and group by location name
$groupedData = $data | Group-Object -Property locationName

foreach ($group in $groupedData) {
    $locationName = $group.Name
    $identifiers = @()

    foreach ($row in $group.Group) {
        if (-not [string]::IsNullOrWhiteSpace($row.locationGatewayData)) {
            $identifiers += @{ locationType = 1; stringData = @($row.locationGatewayData) }
        }
        if (-not [string]::IsNullOrWhiteSpace($row.locationSubnetData)) {
            $identifiers += @{ locationType = 2; stringData = @($row.locationSubnetData) }
        }
        if (-not [string]::IsNullOrWhiteSpace($row.locationIpRangeData)) {
            $identifiers += @{ locationType = 3; stringData = @($row.locationIpRangeData) }
        }
        if (-not [string]::IsNullOrWhiteSpace($row.locationWifiData)) {
            $identifiers += @{ locationType = 4; stringData = @($row.locationWifiData) }
        }
    }

    if ($identifiers.Count -eq 0) {
        Write-Host "Skipping location '$locationName' - No valid data provided."
        Add-Content -Path $logFile -Value "Skipped: $locationName - No valid data provided."
        continue
    }

    # Check if the location already exists
    $existingLocation = $json.Values | Where-Object { $_.name -eq $locationName }

    if ($existingLocation) {
        # Update existing location
        $id = $existingLocation.id
        $location = @{ name = $locationName; sortOrder = 0; identifiers = $identifiers }
        $body = $location | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-RestMethod -Uri "$baseURL/locations/$id" -Method Put -Headers @{"X-Api-Key"=$apiKey} -Body $body -ContentType 'application/json'
            $json[$id.ToString()] = $location
            Write-Host "Updated location '$locationName' - location ID: $id"
            Add-Content -Path $logFile -Value "Updated: $locationName - ID $id"
        } catch {
            Write-Host "Error updating location '$locationName': $_"
            Add-Content -Path $logFile -Value "Error updating: $locationName - $_"
        }
    } else {
        # Create new location
        $location = @{ name = $locationName; sortOrder = 0; identifiers = $identifiers }
        $body = $location | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-RestMethod -Uri "$baseURL/locations" -Method Post -Headers @{"X-Api-Key"=$apiKey} -Body $body -ContentType 'application/json'
            $json[$response.id.ToString()] = $location
            Write-Host "Added location '$locationName' - location ID: $($response.id)"
            Add-Content -Path $logFile -Value "Added: $locationName - ID $($response.id)"
        } catch {
            Write-Host "Error creating location '$locationName': $_"
            Add-Content -Path $logFile -Value "Error creating: $locationName - $_"
        }
    }

    Start-Sleep -Milliseconds 250 # Rate limit to 4 API requests per second
}

$json | ConvertTo-Json -Depth 10 | Out-File .\locations.json
Write-Host "Locations processed and saved successfully."

# Return to main menu
& .\manageLocations.ps1
