# This PowerShell script lists all users from Microsoft Graph with '@local' suffix in their email

# Install the Microsoft.Graph module if not already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
}

# Import the Microsoft.Graph module
Import-Module Microsoft.Graph

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All"

# Get all users
$users = Get-MgUser -All

# Filter users with '@local' suffix in their email
$localUsers = $users | Where-Object { $_.Mail -like '*@local' }

# Display the users
$localUsers | Select-Object DisplayName, Mail

# Disconnect from Microsoft Graph
Disconnect-MgGraph