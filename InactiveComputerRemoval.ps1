#Before Production Implementation - comment out send-mailmessage lines with test email, uncomment mailmessage lines with Systems/SD DLs
#Before Production Implementation - Remove -WhatIf Parameters

Import-Module activedirectory

$today = Get-Date
$daysInactiveDisable = 120
$daysInactiveDelete = 180
$window60days = $today.AddDays(-60)
$disableTime = ($today).Adddays(-($daysInactiveDisable))
$disableList = @()
$deleteTime = ($today).Adddays(-($daysInactiveDelete))
$deletedOU = "OU=Computers to be Deleted,OU=REDACTED,DC=edu"                     #Move PCs to Computers to be deleted OU on disable
$hash_lastLogonTimestamp = @{Name="LastLogonTimeStamp";Expression={([datetime]::FromFileTime($_.LastLogonTimeStamp))}}          #User Readable LastLogonTimeStamp from https://blogs.technet.microsoft.com/chadcox/2017/08/18/active-directory-powershell-quick-tip-lastlogontimestamp-and-pwdlastset/


#Reports - Consider explicity defining filepath once script is in prod
$ComputersNotMoved = ".\DisabledComputersNotMoved.csv"
$DisabledComputers = ".\ComputersThatWereDisabled.csv"
$ComputersMovedTBD = ".\ComputersSuccessfullyMovedToTBD.csv" 
$ComputersToBeDeleted = ".\ComputersThatShouldBeDeleted.csv"

#Check for computers currently enabled but last logon date >120 days -> disable and add description with date/time
function DisableComputers
{
    $description = "Computer disabled for inactivity on $today"
    
    #Enabled computers with last logon date >120 days
    $disableList = Get-ADComputer -Filter {LastLogonTimeStamp -lt $disableTime} -SearchBase "OU=REDACTED,DC=edu" -resultSetSize $null `
    -Properties Name, DistinguishedName, LastLogonTimeStamp, Enabled | Where-Object { $_.Enabled -eq $true}
    #Iterate through array, disable and add date/time to description
    foreach ($Computer in $disableList) 
    {
       Set-ADComputer ($Computer).Name -Description $description -Enabled $false
    }
    $disableList | Select-Object Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled | Export-Csv $DisabledComputers
}

#Check for disabled computers with last logon date >180 days -> Move to Computers To Be Deleted OU
#ONLY checks disabled computers. If last logon >180 and machine is still enabled, will be caught by DisableComputers function
function ComputersToBeDeleted
{
    $movedCorrectly =@()
    $disabledButNotMoved =@()
    $movedCorrectly = [System.Collections.ArrayList]@()
    $disabledButNotMoved = [System.Collections.ArrayList]@()

    #Create array of disabled computers with last logon date >180 days within Student Affairs OU
    $deleteList = Get-ADComputer -Filter {LastLogonTimeStamp -lt $deleteTime} -SearchBase "OU=REDACTED,DC=edu" -resultSetSize $null `
    -Properties Name, whenChanged, DistinguishedName, LastLogonTimeStamp, Enabled | Where-Object { $_.Enabled -eq $false}

    #Iterate through array, move to To Be Deleted OU
    foreach ($Computer in $deleteList) 
    {
        #Enforce a 60 day grace period after a machine was disabled, ensures enabled machines with LastLogonDate > 180 days will have 60 days after disabling before being moved to $deletedOU
        #Consider removing 60 days after prod implementation if whenChanged is creating too many unwanted exceptions
        if ($Computer.whenChanged -le $window60days)
        {
            Move-ADObject -Identity ($Computer).DistinguishedName -TargetPath $deletedOU
            $movedCorrectly.Add($Computer)
        }
        else 
        {
            $disabledButNotMoved.Add($Computer)
            continue
        }
    }
    $deleteList | Select-Object Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled | Export-Csv $ComputersToBeDeleted
    $movedCorrectly | Select-Object Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled, whenChanged | Export-Csv $ComputersMovedTBD
    $disabledButNotMoved | Select-Object Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled, whenChanged | Export-Csv $ComputersNotMoved
}

function PrerunMailAlert
{
    $today = Get-Date
    $From = "WeeklyADComputerCleanup@REDACTED.edu"
    $To = "DISTRIBUTION LIST REDACTED"
    $Subject = "AD Inactive Computer Removal -- Beginning Cleanup Script"
    $Body = "Cleanup script to check for inactive computers was started at $today."
    $SMTPServer = "REDACTED.edu"
    $SMTPPort = "REDACTED"
    #Have to pass credentials to Send-MailMessage > Give bogus credentials
    $anonPassword = ConvertTo-SecureString -String "anonymous" -AsPlainText -Force
    $anonCredentials = New-Object System.Management.Automation.PSCredential($From,$anonPassword)

    Send-MailMessage -From $From -to $To -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Credential $anonCredentials –DeliveryNotificationOption OnSuccess
    #Send-MailMessage -From $From -to "REDACTED@REDACTED.EDU" -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Credential $anonCredentials –DeliveryNotificationOption OnSuccess
}

function MailReport
{
    $AttachedReports = @($ComputersNotMoved, $ComputersMovedTBD, $DisabledComputers, $ComputersToBeDeleted)
    $From = "WeeklyADComputerCleanup@REDACTED.edu"
    $To = "DL REDACTED"
    $CC = "DL REDACTED"
    $Subject = "AD Inactive Computer Removal -- Weekly Run Report"
    $Body = "Attached are the reports of the weekly AD inactive computer removal script. Special attention should be paid to:`n
    ComputersThatWereDisabled.csv `t Machines disabled by the run script for logon date >120 days.`n
    DisabledComputersNotMoved.csv `t These machines have been modified at some point in the last 60 days despite being disabled."
    $SMTPServer = "REDACTED.edu"
    $SMTPPort = "REDACTED"
    #Have to pass credentials to Send-MailMessage > Give bogus credentials
    $anonPassword = ConvertTo-SecureString -String "anonymous" -AsPlainText -Force
    $anonCredentials = New-Object System.Management.Automation.PSCredential($From,$anonPassword)

    Send-MailMessage -From $From -to $To -Cc $CC -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Credential $anonCredentials `
    -Attachments $AttachedReports –DeliveryNotificationOption OnSuccess
    # Send-MailMessage -From $From -to "REDACTED@REDACTED.edu" -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Credential $anonCredentials `
    # -Attachments $AttachedReports –DeliveryNotificationOption OnSuccess

}

function main
{
    PrerunMailAlert
    ComputersToBeDeleted
    DisableComputers
    MailReport
}

main
