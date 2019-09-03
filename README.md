# PowerShell script to automate SCOM installation

- SCOM Server –  VM with up to 8Gb RAM, 4vCPU, Windows Server 2016
- SCOM VMs has an Internet Connection (to get Report Viewer/Runtime)
- SQL Server – VM with up to 4Gb RAM. Windows Server 2016
- Database Services, Full Text and Reporting Services – Native were installed on the SQL Server VM.
- These machines are also joined to the same domain
- SCOM media copied to the %systemdrive%\SCOM2016
- I checked the script using my domain administrator account
  
  Blog post: https://rlevchenko.com/2018/01/16/automate-scom-2016-installation-with-powershell/
