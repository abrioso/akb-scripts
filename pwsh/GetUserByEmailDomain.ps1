# This PowerShell script lists all users from Microsoft Graph with '@local' suffix in their email

# Install the Microsoft.Graph module if not already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
}

# Import the Microsoft.Graph module
Import-Module Microsoft.Graph

# Read the domain from the user
$domain = Read-Host -Prompt 'Enter the domain to search for users'
$date = Get-Date -Format "yyyyMMdd"

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All"

# Get all users
$users = Get-MgUser -All

# Filter users with the specified domain in their email
$localUsers = $users | Where-Object { $_.Mail -like "*$domain" }

# Display the users
$localUsers | Select-Object UserPrincipalName, DisplayName, Mail, AccountEnabled

# Export the users to a CSV file and properties to a cxv file
#$localUsers | Export-Csv -Path "users_$($domain -replace '@', '')_$date.csv" -NoTypeInformation
$localUsers | Select-Object UserPrincipalName, DisplayName, Mail, AccountEnabled | Export-Csv -Path "users_$($domain -replace '@', '')_$date.cxv" -NoTypeInformation

# Disconnect from Microsoft Graph
Disconnect-MgGraph