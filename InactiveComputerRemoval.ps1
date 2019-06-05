Import-Module activedirectory

$daysInactiveDisable = 120
$daysInactiveDelete = 180
$hash_lastLogonTimestamp = @{Name="LastLogonTimeStamp";Expression={([datetime]::FromFileTime($_.LastLogonTimeStamp))}} #User Readable LastLogonTimeStamp from https://blogs.technet.microsoft.com/chadcox/2017/08/18/active-directory-powershell-quick-tip-lastlogontimestamp-and-pwdlastset/
$today = Get-Date
$disableTime = ($today).Adddays(-($daysInactiveDisable))
$disableList = @()
$deleteTime = ($today).Adddays(-($daysInactiveDelete))
$ToBeDeletedList = @()
$deletedOU = "OU=Computers to be Deleted,OU=IT Dumpster,OU=Student Affairs,DC=dsa,DC=reldom,DC=tamu,DC=edu" #Move PCs to Computers to be deleted OU on disable

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
    $disableList | select Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled | Export-Csv "C:\TEMP\disabledComputers.csv"
}

#Check for disabled computers with last logon date >180 days -> Move to Computers To Be Deleted OU
function ComputersToBeDeleted
{
    $description = "Computer disabled for inactivity on $today"
    $computerDescription = "Get-ADComputer AD-test -Properties Description | Select-Object -ExpandProperty description" 
    #Create array of disabled computers with last logon date >180 days 
    $ToBeDeletedList = Get-ADComputer -Filter {LastLogonTimeStamp -lt $deleteTime} -SearchBase "OU=Student Affairs,DC=dsa,DC=reldom,DC=tamu,DC=edu" -resultSetSize $null `
    -Properties Name, OperatingSystem, SamAccountName, DistinguishedName, LastLogonTimeStamp, Enabled | Where { $_.Enabled -eq $false}

    #Iterate through array, move to To Be Deleted OU
    foreach ($Computer in $ToBeDeletedList) 
    {

       Move-ADObject -Identity ($Computer).DistinguishedName -TargetPath $deletedOU -WhatIf
    }
    $ToBeDeletedList | select Name, DistinguishedName, $hash_lastLogonTimestamp, Enabled | Export-Csv "C:\TEMP\toBeDeletedComputers.csv"
}
function main
{
    ComputersToBeDeleted
    DisableComputers
   
}

main
