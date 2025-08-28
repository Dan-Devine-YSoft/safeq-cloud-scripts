# Set the user email (or UPN)
$userEmail = "dan@mobilelab.work"

# Retrieve the user's details as JSON.
$userJson = az ad user show --id $userEmail --output json

if (-not $userJson) {
    Write-Error "Failed to retrieve details for $userEmail. Ensure you are logged in and the user exists."
    exit 1
}

# Convert JSON output to a PowerShell object.
$userInfo = $userJson | ConvertFrom-Json

# Retrieve the user object ID using the "id" property.
$userObjectId = $userInfo.id

if (-not $userObjectId) {
    Write-Error "Failed to retrieve the object ID for $userEmail. Retrieved data: $userJson"
    exit 1
}

Write-Output "User object ID: $userObjectId"

# Retrieve the list of groups the user is a member of.
$groupsJson = az ad user get-member-groups --id $userObjectId --output json

if (-not $groupsJson) {
    Write-Error "Failed to retrieve groups for user $userEmail"
    exit 1
}

# Convert the JSON output to a PowerShell object.
$groups = $groupsJson | ConvertFrom-Json

if (-not $groups) {
    Write-Error "Failed to parse group information for user $userEmail"
    exit 1
}

# Count the number of groups.
$groupCount = $groups.Count

Write-Output "User $userEmail is a member of $groupCount groups."
