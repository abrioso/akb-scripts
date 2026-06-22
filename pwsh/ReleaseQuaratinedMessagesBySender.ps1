
## ReleaseQuaratinedMessagesBySender.ps1

## This script releases all quarantined messages from a specific sender in Exchange Online / Defender.
## Usage:
## 1. Set the $AdminUser variable to your admin UPN.
## 2. Set the $QuarantinedSender variable to the sender's email address you want to release messages from.
## 3. Run the script in PowerShell with the Exchange Online and Security & Compliance modules installed.
## 4. The script will connect to Exchange Online, retrieve quarantined messages from the specified sender, and release them to the intended recipients.
## 5. Review the output to ensure the messages have been released successfully.
## 6. Note: Ensure you have the necessary permissions to release quarantined messages.

# define admin user
$AdminUser = "akbrioso@iseg.ulisboa.pt"

# Define quarantined sender
$QuarantinedSender = "marketing@iseg.ulisboa.pt"

# Define the message quarantine release status
# Valid values: NOTRELEASED, RELEASED, REQUESTED, APPROVED, DENIED, PREPARINGTORELEASE, ERROR, TEMPORARYDELETED, PROCESSING, RESCANINCONCLUSIVE, RESCANMALICIOUS
$ReleaseStatus = "NOTRELEASED"

# Initialize an empty array to hold the messages
$Messages = @()

# Define the number of messages to retrieve per page (default is 100)
$PageSize = 1000

# Connect to Exchange Online / Defender
Connect-ExchangeOnline -UserPrincipalName $AdminUser
# Required for quarantine cmdlets (Security & Compliance)
Connect-IPPSSession -UserPrincipalName $AdminUser


# Get quarantined messages from that sender
$Messages = Get-QuarantineMessage -SenderAddress $QuarantinedSender -PageSize $PageSize -ReleaseStatus $ReleaseStatus

Write-Host "Mensagens encontradas:" $Messages.Count

# Print a preview of the messages to be released
Write-Host "As seguintes mensagens serão libertadas:"
$Messages | Select-Object Identity, Subject, RecipientAddress, ReceivedTime | Format-Table -AutoSize

# Check if there are messages to release
if ($Messages.Count -eq 0) {
    Write-Host "Nenhuma mensagem encontrada para o remetente $QuarantinedSender com status $ReleaseStatus."
    exit
}

# Confirm release
$confirmation = Read-Host "Deseja liberar todas as mensagens do remetente $QuarantinedSender? (S/N)"
if ($confirmation -ne "S") {
    Write-Host "Operação cancelada pelo utilizador."
    exit
}


# --- Release messages ---
$totalMessages = $Messages.Count
$processed = 0

foreach ($msg in $Messages) {
    $processed++
    $percentComplete = [int](($processed / $totalMessages) * 100)

    Write-Progress -Activity "A libertar mensagens em quarentena" `
        -Status "$processed de $totalMessages" `
        -CurrentOperation $msg.Subject `
        -PercentComplete $percentComplete

    Write-Host "A libertar:" $msg.Subject "->" $msg.RecipientAddress
    
    Release-QuarantineMessage -Identity $msg.Identity `
        -ReleaseToAll `
        -AllowSender `
        -Confirm:$false
}

Write-Progress -Activity "A libertar mensagens em quarentena" -Completed

Write-Host "Processo concluído."