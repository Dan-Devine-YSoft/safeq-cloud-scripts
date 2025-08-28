# Menu Script - manage_locations.ps1

# Force working directory to script location
Set-Location -Path $PSScriptRoot

function Show-Menu {
    Write-Host ""
    Write-Host "--------------------------"
    Write-Host "1. Set up API"
    Write-Host "2. Create Devices"
    Write-Host "3. Delete Devices"
    Write-Host "--------------------------"
    Write-Host ""
    Write-Host "Be sure to put your csv files in $PSScriptRoot"
    Write-Host ""
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Please select an option"

    switch ($choice) {
        1 { & .\setupAPI.ps1 }
        2 { & .\createDevices.ps1 }
        3 { & .\deleteDevices.ps1 }
        default { Write-Host "Invalid option, please try again." }
    }
}
