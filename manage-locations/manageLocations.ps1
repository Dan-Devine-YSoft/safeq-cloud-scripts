# Menu Script - manage_locations.ps1

# Force working directory to script location
Set-Location -Path $PSScriptRoot

function Show-Menu {
    Write-Host ""
    Write-Host "-------------------"
    Write-Host "1. Import Locations"
    Write-Host "2. Create Locations"
    Write-Host "3. Export Locations"
    Write-Host "4. Delete Locations"
    Write-Host "5. Set up API"
    Write-Host "6. Exit"
    Write-Host "-------------------"
    Write-Host ""
    Write-Host "Be sure to put your csv files in $PSScriptRoot"
    Write-Host ""
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Please select an option"

    switch ($choice) {
        1 { & .\importLocations.ps1 }
        2 { & .\createLocations.ps1 }
        3 { & .\exportLocations.ps1 }
        4 { & .\deleteLocations.ps1 }
        5 { & .\setupAPI.ps1 }
        6 { exit }
        default { Write-Host "Invalid option, please try again." }
    }
}
