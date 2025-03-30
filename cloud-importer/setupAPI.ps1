# Setup API Script - setupAPI.ps1

# Force working directory to script location
Set-Location -Path $PSScriptRoot

Write-Host "You need an API key with locations-based advanced permissions to use this script"
Write-Host "Please make sure your API key has create, view, modify, delete and search permissions for locations."

$apiKey = Read-Host "Enter your API Key"
$cloudTenancyAddress = Read-Host "Enter your cloud tenancy address (e.g., tenant.au.ysoft.cloud)"

$jsonData = @{ apiKey = $apiKey; cloudTenancyAddress = $cloudTenancyAddress } | ConvertTo-Json
$jsonData | Out-File -FilePath .\apiconfig.json
Write-Host "API configuration saved successfully."
Write-Host "Please note the API key is stored in plain text within $PSScriptRoot\apiconfig.json.  Please ensure this file is secure and not accessible to unauthorised users.  You can delete it immediately after using this script set if needed."

