 <#
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |w|w|w|.|r|l|e|v|c|h|e|n|k|o|.|c|o|m|
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                                                                                                    

::SCOM 2016 installation (OMServer,OMConsole,OMWebConsole)
::Tested on 2 nodes configuration : WS2016 + SQL Server 2016 (named instance + custom port 1500)
::Note that machines must be domain-joined, SCOM media copied to the <systemdrive>\SCOM2016

 #>
#region Variables
    $sqlsrv =read-host "Type SQL Server name (RL-SQL01, for example)"
    $sqluser=read-host "Type user name with admin rights on SQL Server (sqluser,for example)"
    $sqlpass=read-host "Type user password with admin rights on SQL Server"
    $ouname=read-host "Type OU name for placing accounts and group (Service Accounts,for example)"
    $svcpass=read-Host "Type password for SCOM/SQL service accounts"
    $sqlinstancename=read-host "Type SQL Server instance name (SCOM,for example)"
    $sqlserverport=read-host "Type SQL Server port (1433,for example)"
    $mgmtgroup=read-Host "Type SCOM management group name (RLLAB, for example)"
#endregion

#region Download and install Report Viewer Controls and Runtime
    New-Item $env:systemdrive\SCOM2016Reqs -ItemType Directory
    Invoke-WebRequest http://download.microsoft.com/download/A/1/2/A129F694-233C-4C7C-860F-F73139CF2E01/ENU/x86/ReportViewer.msi -OutFile $env:systemdrive\SCOM2016Reqs\ReportViewer.msi
    Invoke-WebRequest http://download.microsoft.com/download/F/E/E/FEE62C90-E5A9-4746-8478-11980609E5C2/ENU/x64/SQLSysClrTypes.msi -OutFile $env:systemdrive\SCOM2016Reqs\SQLSysClrTypes.msi
    Start-Process "$env:systemdrive\SCOM2016Reqs\SQLSysClrTypes.msi" /qn -Wait
    Start-Process "$env:systemdrive\SCOM2016Reqs\ReportViewer.msi" /quiet -Wait
    Write-Host "The Report Viewer Controls and Runtime have been installed" -ForegroundColor DarkCyan
#endregion
#region Create required service accounts, add them to local administrators 
    Install-WindowsFeature RSAT-AD-PowerShell
    $adcn=(Get-ADDomain).DistinguishedName
    $dname=(Get-ADDomain).Name
    New-AdUser SCOM-AccessAccount -SamAccountName scom.aa -AccountPassword (ConvertTo-SecureString -AsPlainText $svcpass -Force) -PasswordNeverExpires $true -Enabled $true -Path "OU=$ouname,$adcn"
    New-AdUser SCOM-DataWareHouse-Reader -SamAccountName scom.dwr -AccountPassword (ConvertTo-SecureString -AsPlainText $svcpass -Force) -PasswordNeverExpires $true -Enabled $true -Path "OU=$ouname,$adcn"
    New-AdUser SCOM-DataWareHouse-Write -SamAccountName scom.dww -AccountPassword (ConvertTo-SecureString -AsPlainText $svcpass -Force) -PasswordNeverExpires $true -Enabled $true -Path "OU=$ouname,$adcn"
    New-AdUser SCOM-Server-Action -SamAccountName scom.sa -AccountPassword (ConvertTo-SecureString -AsPlainText $svcpass -Force) -PasswordNeverExpires $true -Enabled $true -Path "OU=$ouname,$adcn"
    New-AdGroup -Name SCOM-Admins -GroupScope Global -GroupCategory Security -Path "OU=$ouname,$adcn"
    Add-AdGroupMember SCOM-Admins scom.aa,scom.dwr,scom.dww,scom.sa
    Add-LocalGroupMember -Member $dname\SCOM-Admins -Group Administrators
    #SQL Server service accounts (SQLSSRS is a service reporting services account)
    New-AdUser SQLSVC -SamAccountName sqlsvc -AccountPassword (ConvertTo-SecureString -AsPlainText $svcpass -Force) -PasswordNeverExpires $true -Enabled $true -Path "OU=$ouname,$adcn"
    New-AdUser SQLSSRS -SamAccountName sqlssrs -AccountPassword (ConvertTo-SecureString -AsPlainText $svcpass -Force) -PasswordNeverExpires $true -Enabled $true -Path "OU=$ouname,$adcn"
    Write-Host "The service Accounts and SCOM-Admins group have been added to OU=$ouname,$adcn" -ForegroundColor DarkCyan
#endregion
#region Configure firewall on SQL Server and add SCOM-Admins to the local admins###
    $secpasswd = ConvertTo-SecureString $sqlpass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("$dname\$sqluser", $secpasswd)
    $psrem = New-PSSession -ComputerName $sqlsrv -Credential $cred
    Invoke-Command -Session $psrem -ScriptBlock{
        Install-WindowsFeature RSAT-AD-Powershell
        Set-NetFirewallRule -Name WMI-WINMGMT-In-TCP -Enabled True
        New-NetFirewallRule -Name "SQL DB" -DisplayName "SQL Database" -Profile Domain -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
        New-NetFirewallRule -Name "SQL Server Admin Connection" -DisplayName "SQL Admin Connection" -Profile Domain -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
        New-NetFirewallRule -Name "SQL Browser" -DisplayName "SQL Browser" -Profile Domain -Direction Inbound -LocalPort 1434 -Protocol UDP -Action Allow
        New-NetFirewallRule -Name "SQL SRRS (HTTP)" -DisplayName "SQL SRRS (HTTP)" -Profile Domain -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
        New-NetFirewallRule -Name "SQL SRRS (SSL)" -DisplayName "SQL SRRS (SSL)" -Profile Domain -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
        New-NetFirewallRule -Name "SQL Instance Custom Port" -DisplayName "SQL Instance Custom Port" -Profile Domain -Direction Inbound -LocalPort $sqlserverport -Protocol TCP -Action Allow
        New-NetFirewallRule -Name "SQL Server 445" -DisplayName "SQL Server 445" -Profile Domain -Direction Inbound -LocalPort 445 -Protocol TCP -Action Allow
        New-NetFirewallRule -Name "SQL Server 135" -DisplayName "SQL Server 135" -Profile Domain -Direction Inbound -LocalPort 135 -Protocol TCP -Action Allow
        Add-LocalGroupMember -Member $arg[0]\SCOM-Admins -Group Administrators} -ArgumentList $dname
    Write-Host "The SQL Server $sqlsrv has been configured" -ForegroundColor DarkCyan
#endregion
#region Install Web Console prerequisites
    Install-WindowsFeature NET-WCF-HTTP-Activation45,Web-Static-Content,Web-Default-Doc,Web-Dir-Browsing,Web-Http-Errors, `
    Web-Http-Logging,Web-Request-Monitor,Web-Filtering,Web-Stat-Compression,Web-Mgmt-Console,Web-Metabase,Web-Asp-Net,Web-Windows-Auth
    Write-Host "The Web Console prerequisites have been installed" -ForegroundColor DarkCyan
#endregion
#region Install SCOM 2016 (AuthorizationMode-Mixed,custom SQL Server ports,named instance - SCOM)
    $arglist= @("/install /components:OMServer,OMConsole,OMWebConsole /ManagementGroupName:$mgmtgroup /SqlServerInstance:$sqlsrv\$sqlinstancename /SqlInstancePort:$sqlserverport", 
    "/DatabaseName:OperationsManager /DWSqlServerInstance:$sqlsrv\$sqlinstancename /DWDatabaseName:OperationsManagerDW /ActionAccountUser:$dname\scom.sa",
    "/ActionAccountPassword:$svcpass /DASAccountUser:$dname\scom.aa /DASAccountPassword:$svcpass /DataReaderUser:$dname\scom.dwr", 
    "/DataReaderPassword:$svcpass /DataWriterUser:$dname\scom.dww /DataWriterPassword:$svcpass /WebSiteName:""Default Web Site""", 
    '/WebConsoleAuthorizationMode:Mixed /EnableErrorReporting:Always /SendCEIPReports:1 /UseMicrosoftUpdate:1 /AcceptEndUserLicenseAgreement:1 /silent')
    Start-Process -FilePath $env:systemdrive\SCOM2016\setup.exe -ArgumentList $arglist -Wait
    Write-Host "The SCOM has been installed. Don't forget to license SCOM" -ForegroundColor DarkCyan
#endregion

 <# 
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |w|w|w|.|r|l|e|v|c|h|e|n|k|o|.|c|o|m|
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                                                                                                    
 
 To properly license SCOM, install the product key using the following cmdlet: 
 Set-SCOMLicense -ProductId XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
 #>