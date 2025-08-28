# Create Locations Script - createLocations.ps1

# Force working directory to script location
Set-Location -Path $PSScriptRoot

$logFile = "$PSScriptRoot\createLocations.log"

$apiConfig = Get-Content .\apiconfig.json | ConvertFrom-Json
$apiKey = $apiConfig.apiKey
$baseURL = "https://$($apiConfig.cloudTenancyAddress):7300/api/v1"

# Helper function to get a unique key for an identifier
function Get-IdentifierKey {
    param (
        [PSCustomObject]$identifier
    )
    "$($identifier.locationType):$($identifier.stringData -join ',')"
}

# Helper function to compare identifier arrays and remove duplicates
function Merge-Identifiers {
    param (
        [Array]$existing,
        [Array]$new
    )

    # Use a hashtable to ensure uniqueness
    $uniqueIdentifiers = @{}

    # Add all existing identifiers first
    foreach ($identifier in $existing) {
        $key = Get-IdentifierKey -identifier $identifier
        if (-not $uniqueIdentifiers.ContainsKey($key)) {
            $uniqueIdentifiers[$key] = $identifier
        }
    }

    # Add new identifiers, only if they don't exist
    foreach ($identifier in $new) {
        $key = Get-IdentifierKey -identifier $identifier
        if (-not $uniqueIdentifiers.ContainsKey($key)) {
            $uniqueIdentifiers[$key] = $identifier
        }
    }

    # Return all unique identifiers as an array
    return $uniqueIdentifiers.Values
}

# Download existing locations from API
Write-Host "Fetching existing locations..."
$response = Invoke-RestMethod -Uri "$baseURL/locations" -Method Get -Headers @{"X-Api-Key"=$apiKey} -ContentType 'application/json'
$existingLocations = @{}

if ($response) {
    foreach ($loc in $response) {
        $existingLocations[$loc.name] = $loc  # Store by name for easier lookup
    }
    Write-Host "Found $($existingLocations.Count) existing locations."
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

# Read CSV data and add locationId column if it doesn't exist
$csvContent = Get-Content .\$csvFileName
$csvData = $csvContent | ConvertFrom-Csv

# Check if locationId column exists, if not, add it
$headers = ($csvData | Get-Member -MemberType NoteProperty).Name
if ($headers -notcontains 'locationId') {
    $csvData | Add-Member -NotePropertyName 'locationId' -NotePropertyValue ''
}

# Process each row
foreach ($row in $csvData) {
    # Skip if locationName is empty and log the information
    if ([string]::IsNullOrWhiteSpace($row.locationName)) {
        if (-not [string]::IsNullOrWhiteSpace($row.locationSubnetData)) {
            Add-Content -Path $logFile -Value "[INFO] $($row.locationSubnetData) has no locationName - please action this manually."
        }
        continue
    }

    $identifiers = @()

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

    if ($identifiers.Count -eq 0) {
        Write-Host "Skipping location '$($row.locationName)' - No valid data provided."
        Add-Content -Path $logFile -Value "Skipped: $($row.locationName) - No valid data provided."
        continue
    }

    # Check if the location already exists in the API
    $existingLocation = $existingLocations[$row.locationName]

    if ($existingLocation) {
        # Update existing location with merged identifiers (removing duplicates)
        $id = $existingLocation.id
        $mergedIdentifiers = Merge-Identifiers -existing $existingLocation.identifiers -new $identifiers

        # Create sets of unique identifiers for comparison
        $existingKeys = @{}
        $existingLocation.identifiers | ForEach-Object {
            $key = Get-IdentifierKey -identifier $_
            $existingKeys[$key] = $true
        }

        $mergedKeys = @{}
        $mergedIdentifiers | ForEach-Object {
            $key = Get-IdentifierKey -identifier $_
            $mergedKeys[$key] = $true
        }

        # Find genuinely new identifiers
        $hasNewIdentifiers = $false
        foreach ($key in $mergedKeys.Keys) {
            if (-not $existingKeys.ContainsKey($key)) {
                $hasNewIdentifiers = $true
                break
            }
        }

        if ($hasNewIdentifiers) {
            $location = @{
                name = $row.locationName
                sortOrder = 0
                identifiers = $mergedIdentifiers
            }
            $body = $location | ConvertTo-Json -Depth 10

            try {
                $response = Invoke-RestMethod -Uri "$baseURL/locations/$id" -Method Put -Headers @{"X-Api-Key"=$apiKey} -Body $body -ContentType 'application/json'
                $json[$id.ToString()] = $location
                $row.locationId = $id  # Update locationId in CSV
                # Update our local cache with the new state
                $existingLocations[$row.locationName] = @{
                    id = $id
                    name = $row.locationName
                    identifiers = $mergedIdentifiers
                }
                Write-Host "Added new identifiers to EXISTING location '$($row.locationName)' - ID: $id"
                Add-Content -Path $logFile -Value "Updated: $($row.locationName) - ID $id"
            } catch {
                Write-Host "Error updating location '$($row.locationName)': $_"
                Add-Content -Path $logFile -Value "Error updating: $($row.locationName) - $_"
            }
        } else {
            Write-Host "Skipping update for '$($row.locationName)' - No new identifiers to add"
            Add-Content -Path $logFile -Value "Skipped update: $($row.locationName) - No new identifiers"
        }
    } else {
        # Create new location
        $location = @{ name = $row.locationName; sortOrder = 0; identifiers = $identifiers }
        $body = $location | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-RestMethod -Uri "$baseURL/locations" -Method Post -Headers @{"X-Api-Key"=$apiKey} -Body $body -ContentType 'application/json'
            $json[$response.id.ToString()] = $location
            $row.locationId = $response.id  # Update locationId in CSV
            # Add to existing locations hashtable
            $existingLocations[$row.locationName] = @{ id = $response.id; name = $row.locationName; identifiers = $identifiers }
            Write-Host "Created NEW location '$($row.locationName)' - ID: $($response.id)"
            Add-Content -Path $logFile -Value "Created: $($row.locationName) - ID $($response.id)"
        } catch {
            Write-Host "Error creating location '$($row.locationName)': $_"
            Add-Content -Path $logFile -Value "Error creating: $($row.locationName) - $_"
        }
    }

    Start-Sleep -Milliseconds 250 # Rate limit to 4 API requests per second
}

# Save updated locations to JSON file
$json | ConvertTo-Json -Depth 10 | Out-File .\locations.json

# Save updated CSV with locationIds
$csvData | Export-Csv -Path $csvFileName -NoTypeInformation
Write-Host "Locations processed and saved successfully."

# Return to main menu
& .\manageLocations.ps1