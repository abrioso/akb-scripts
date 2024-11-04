# This PowerShell script lists all users from an On-Prem Active Directory with a specific suffix in their email

# Import the ActiveDirectory module
Import-Module ActiveDirectory

# Read the domain from the user
$domain = Read-Host -Prompt 'Enter the domain to search for users'
$date = Get-Date -Format "yyyyMMdd"

# Get all users from the On-Prem Active Directory
$users = Get-ADUser -Filter * -Property EmailAddress, UserPrincipalName, DisplayName, Enabled

# Filter users with the specified domain in their email
$localUsers = $users | Where-Object { $_.EmailAddress -like "*$domain" }

# Display the users
$localUsers | Select-Object UserPrincipalName, DisplayName, EmailAddress, Enabled

# Export the users to a CSV file
$localUsers | Select-Object UserPrincipalName, DisplayName, EmailAddress, Enabled | Export-Csv -Path "users_$($domain -replace '@', '')_$date.csv" -NoTypeInformation
