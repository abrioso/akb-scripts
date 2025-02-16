##
# Create a USB Boot Device with MBR Partition Style from an ISO
##
# Based on the following article:
# https://www.thomasmaurer.ch/2024/07/create-an-usb-drive-for-windows-server-2025-installation/
##

# Get from arguments the path to the ISO file
param (
    [Parameter(Mandatory = $true)]
    [string]$ISOFile
)

# Check if the script is running with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "You need to run this script as an Administrator."
    exit
}

# Load the required module
Import-Module Storage
# Check if the ISO file exists
if (-not (Test-Path $ISOFile)) {
    Write-Error "The ISO file does not exist."
    exit
}

# Get the USB Drives and display them
$USBDrives = Get-Disk | Where-Object -FilterScript {$_.Bustype -Eq "USB"}
Write-Host "USB Drives found:"
foreach ($USBDrive in $USBDrives) {
    $sizeGB = [math]::Round($USBDrive.Size / 1GB, 2)
    Write-Host "$($USBDrive.Number): $($USBDrive.FriendlyName) - $sizeGB GB - $($USBDrive.PartitionStyle) - $($USBDrive.BusType) - $($USBDrive.DiskNumber)"
}

# Ask the user to select the USB Drive
$USBDriveNumber = Read-Host "Select the USB Drive Number"

# Get the USB Drive Where Number is the selected one
$USBDrive = $USBDrives | Where-Object -FilterScript { $_.Number -Eq $USBDriveNumber }

# Show the selected USB Drive
Write-Host "Selected USB Drive: $($USBDrive.FriendlyName)"

$NewUSBName = Read-Host "Enter the new name for the USB Drive"

# Inform the user that the USB Drive will be formatted and ask for confirmation
$confirm = Read-Host "The USB Drive will be formatted. Do you want to continue? (Y/N)"
if ($confirm -ne "Y") {
    Write-Host "The process was canceled."
    exit
}

# Clear the Disk without requiring administrator privileges
$USBDrive | Clear-Disk -RemoveData -Confirm:$false -PassThru
 
# Convert Disk to MBR
$USBDrive | Set-Disk -PartitionStyle MBR
 
# Create partition primary and format to NTFS
$Volume = $USBDrive | New-Partition -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel $NewUSBName
 
# Set Partiton to Active
$Volume | Get-Partition | Set-Partition -IsActive $true
 
# Mount ISO
$ISOMounted = Mount-DiskImage -ImagePath $ISOFile -StorageType ISO -PassThru
 
# Driver letter
$ISODriveLetter = ($ISOMounted | Get-Volume).DriveLetter
 
# Copy Files to USB
Copy-Item -Path ($ISODriveLetter +":\*") -Destination ($Volume.DriveLetter + ":\") -Recurse
 
# Dismount ISO
Dismount-DiskImage -ImagePath $ISOFile

Write-Host "The USB Drive was created successfully."
