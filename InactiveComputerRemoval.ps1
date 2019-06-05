Import-Module activedirectory

$today = Get-Date
$daysInactiveDisable = 120
$daysInactiveDelete = 180
$window60days = $today.AddDays(-60)
$disableTime = ($today).Adddays(-($daysInactiveDisable))
$disableList = @()
$deleteTime = ($today).Adddays(-($daysInactiveDelete))
$ToBeDeletedList = @()
$deletedOU = "OU=Computers to be Deleted,OU=IT Dumpster,OU=Student Affairs,DC=dsa,DC=reldom,DC=tamu,DC=edu" #Move PCs to Computers to be deleted OU on disable
$hash_lastLogonTimestamp = @{Name="LastLogonTimeStamp";Expression={([datetime]::FromFileTime($_.LastLogonTimeStamp))}} #User Readable LastLogonTimeStamp from https://blogs.technet.microsoft.com/chadcox/2017/08/18/active-directory-powershell-quick-tip-lastlogontimestamp-and-pwdlastset/


#Reports
$ComputersNotMoved = ".\DisabledComputersNotMoved.csv"
$DisabledComputers = ".\ComputersThatWereDisabled.csv"
$ComputersMovedTBD = ".\ComputersSuccessfullyMovedToTBD.csv" 
$ComputersToBeDeleted = ".\ComputersThatShouldBeDeleted.csv"

#Check for computers currently enabled but last logon date >120 days -> disable and add description with date/time
function DisableComputers
{
    $description = "Computer disabled for inactivity on $today"
    
    #Enabled computers with last logon date >120 days
    $disableList = Get-ADComputer -Filter {LastLogonTimeStamp -lt $disableTime} -SearchBase "OU=Student Affairs,DC=dsa,DC=reldom,DC=tamu,DC=edu" -resultSetSize $null `
    -Properties Name, OperatingSystem, SamAccountName, DistinguishedName, LastLogonTimeStamp, Enabled | Where { $_.Enabled -eq $true}
    #Iterate through array, disable and add date/time to description
    foreach ($Computer in $disableList) 
    {
       Set-ADComputer ($Computer).Name -Description $description -Enabled $false -WhatIf
    }
    $disableList | select Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled | Export-Csv $DisabledComputers
}

#Check for disabled computers with last logon date >180 days -> Move to Computers To Be Deleted OU
function ComputersToBeDeleted
{
    $movedCorrectly =@()
    $disabledButNotMoved =@()
    $movedCorrectly = [System.Collections.ArrayList]@()
    $disabledButNotMoved = [System.Collections.ArrayList]@()

    #Create array of disabled computers with last logon date >180 days within Student Affairs OU
    $deleteList = Get-ADComputer -Filter {LastLogonTimeStamp -lt $deleteTime} -SearchBase "OU=Student Affairs,DC=dsa,DC=reldom,DC=tamu,DC=edu" -resultSetSize $null `
    -Properties Name, OperatingSystem, SamAccountName, whenChanged, DistinguishedName, LastLogonTimeStamp, Enabled | Where { $_.Enabled -eq $false}

    #Iterate through array, move to To Be Deleted OU
    foreach ($Computer in $deleteList) 
    {
        #Enforce a 60 day grace period after a machine was disabled, ensures enabled machines with LastLogonDate > 180 days will have 60 days after disabling before being moved to $deletedOU
        if ($Computer.whenChanged -le $window60days)
        {
            Move-ADObject -Identity ($Computer).DistinguishedName -TargetPath $deletedOU -WhatIf
            $movedCorrectly.Add($Computer)
        }
        else 
        {
            $disabledButNotMoved.Add($Computer)
            continue
        }
    }
    $deleteList | select Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled | Export-Csv $ComputersToBeDeleted
    $movedCorrectly | select Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled, whenChanged | Export-Csv $ComputersMovedTBD
    $disabledButNotMoved | select Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled, whenChanged | Export-Csv $ComputersNotMoved
}

function MailReport
{
    $AttachedReports = @($ComputersNotMoved, $ComputersMovedTBD, $DisabledComputers, $ComputersToBeDeleted)
    $From = "MonthlyADComputerCleanup@doit.tamu.edu"
    #Change to Service Desk after finish testing
    $To = "wdell@doit.tamu.edu"
    #AddCC to Send-MailMessage after finish testing
    $CC = "DSA - DL - DoIT Systems Group"
    $Subject = "AD Inactive Computer Removal -- Monthly Run Report"
    $Body = "Attached are the reports of the monthly AD inactive computer removal script. Special attention should be paid to:`n
    ComputersThatWereDisabled.csv `t Machines disabled by the run script for logon date >120 days.`n
    DisabledComputersNotMoved.csv `t These machines have been modified at some point in the last 60 days despite being disabled."
    $SMTPServer = "exchange.tamu.edu"
    $SMTPPort = "465"
    #Have to pass credentials to Send-MailMessage > Give bogus credentials
    $anonPassword = ConvertTo-SecureString -String "anonymous" -AsPlainText -Force
    $anonCredentials = New-Object System.Management.Automation.PSCredential($From,$anonPassword)

    #Change $To from test email address to DSA - DL - DoIT Service Desk Staff
    #Add -CC $CC
    Send-MailMessage -From $From -to $To -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Credential $anonCredentials `
    -Attachments $AttachedReports –DeliveryNotificationOption OnSuccess

}

function main
{
    ComputersToBeDeleted
    DisableComputers
    MailReport
}

main
