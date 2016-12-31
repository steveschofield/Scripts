# Reference for error when disconnecting
# http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2092716

param
(
[String] $ConfigurationFile = $(throw “Please specify the configuration file for the Content move.`r`nExample:`r`n`tGet-MachineLookup.ps1 -ConfigurationFile `”E:\Directory\ChangeThisPath.xml`””)
)

switch (Test-Path $ConfigurationFile)
{
True {Write-Host “Using $ConfigurationFile For Script Variables”
$Properties = [xml](Get-Content $ConfigurationFile)
}
False {Write-Host “$ConfigurationFile Not Found For Script Variables – Quitting”
Exit
}
}

#Get Properties and assign to local variables
$vCenterServer=$Properties.Configuration.Properties.vCenterServer
$smtpServer = $Properties.Configuration.Properties.smtpServer
$MailFrom = $Properties.Configuration.Properties.MailFrom
$MailTo1 = $Properties.Configuration.Properties.MailTo1
$MailTo2 = $Properties.Configuration.Properties.MailTo2
$MailCC = $Properties.Configuration.Properties.MailCC
$Datacenter = $Properties.Configuration.Properties.Datacenter
$DisconnectFlag = $Properties.Configuration.Properties.DisconnectFlag
$Output=$Properties.Configuration.Properties.Output
$OutputErrors=$Properties.Configuration.Properties.OutputErrors

##Assuming you are running PowerCLI 6.x
Import-Module VMware.VimAutomation.Vds

function Log([string]$path, [string]$value)
{
Add-Content -Path “$($Path)$($LogDate).txt” -Value $value
}

#Determines if function will disconnect CD-Rom

function DisconnectCDrom ([string] $isoPathValue)
{
switch -wildcard ($isoPathValue)
{
“*Generic-ISO-Folder-Location*” {return $true}
default {return $false}
}
}

#This could probably use some refining 🙂
function VMMail ($MailTo, $VMList)
{
$msg = new-object Net.Mail.MailMessage
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$msg.From = $MailFrom
$msg.To.Add($MailTo1)
$msg.To.Add($MailTo2)
$msg.CC.Add($MailCC)
$msg.Subject = “CDRoms disconnected for $($Datacenter)”
$MailText = “This is a summary of VM’s with CD Rom Disconnected for $($Datacenter) `r`n $($VMList) ”
$msg.Body = $MailText
$smtp.Send($msg)
}

$StartDate = Get-Date
$LogDate = “$($StartDate.Month)-$($StartDate.Day)-$($StartDate.Year)-$($StartDate.Hour)-$($StartDate.Minute)-$($vCenterServer)”
Log -Path $Output -Value “Starting process as $($Cred.Username) connecting to $($vCenterServer) at $($StartDate)”

#Notice the -force is used, when running in task scheduler, set user # creds with the account
#With perms assigned in vCenter
Connect-VIServer -server $vCenterServer -force
$VMList = Get-Datacenter -Name $Datacenter | Get-VM

$ListOfVMs = @()

foreach($vm in $VMList)
{
if($vm.PowerState -eq “PoweredOn”)
{
Write-Host “Processing $($VM.Name)”
$CDStatus = Get-CDDrive -VM $VM.Name
if($CDStatus.IsoPath -ne $null)
{
$value1 = “$($VM.Name)!$($CDStatus.IsoPath)!$($CDStatus.HostDevice)!$($CDStatus.RemoteDevice)”
Write-Host $value1
$DisconnectCDRom = DisconnectCDrom -isoPathValue $CDStatus.IsoPath
if($DisconnectCDRom -eq $true)
{
Write-Host “Disconnect CDRom for $($VM.Name)”
if($DisconnectFlag -eq 1)
{
$VM | Get-CDDrive | Set-CDDrive -NoMedia -Confirm:$false
$DisconnectDateTime = Get-Date
$ListOfVMs += “$($VM.Name) : $($DisconnectDateTime)`r`n”
Log -Path $Output -Value $value1
}
else
{
Log -Path $Output -Value “$($VM.Name) – Disconnect Flag set to false”
}
}
}
else
{
$value1 = “$($VM.Name)!no CDRom attached!!”
Write-Host $value1
Log -Path $Output -Value $value1
}
}
else
{
$value1 = “$($VM.Name)!powered off!!”
Write-Host $value1
Log -Path $Output -Value “$($value1)”
}
}

#Send email to appropriate people
if($ListOfVMs -ne $null)
{
VMMail -MailTo $MailFrom -VMList $ListOfVMs
}

#End Logging date
$EndDate = Get-Date
Log -Path $Output -Value “Ending process as $($Cred.Username) connecting to $($vCenterServer) at $($EndDate)”
Disconnect-VIServer -Server $vCenterServer -confirm:$false
