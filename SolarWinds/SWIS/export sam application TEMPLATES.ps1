#region Top of Script

<#
.SYNOPSIS
  Exports all application templates for backup.
.DESCRIPTION
  Exports all application templates for backup. Deletes old backup files without removing database entries.
  Includes an example of the syntax for imports.
.INPUTS
  None
.OUTPUTS
  Log file stored in same directory as script runs from, if script isn't run from a file then saves to user desktop.
  TemplateExports directory is created in the same path and filled with the exported data.

#>

#endregion Top of Script
#####-----------------------------------------------------------------------------------------#####
#region Parameters

# No mandatory parameters are defined as inputs will be gathered via prompts.

#endregion Parameters
#####-----------------------------------------------------------------------------------------#####
#region Functions 

#region Set-SwisConnection
Function Set-SwisConnection {
    Param(
        [Parameter(Mandatory = $true)] [string]$SolarWindsServer,
        [Parameter(Mandatory = $true)] [System.Management.Automation.PSCredential]$Credential
    )
    # Connect to SWIS
    $swis = Connect-Swis -Credential $Credential -Hostname $SolarWindsServer
    RETURN $swis
}
#endregion Set-SwisConnection

#endregion Functions 
#####-----------------------------------------------------------------------------------------#####
#region Logging

clear-host
$logTime = Get-Date -Format "yyyyMMdd_HHmm"
$script = ($MyInvocation.MyCommand)
if($script.Path){ $dir = (Split-Path $script.path) + "\logs" }
else { $dir = ([Environment]::GetFolderPath("Desktop")) + "\logs" }
if((test-path $dir) -eq $false) { mkdir -path $dir }
$Logfile = "$dir\$($script.name)_$logTime.log"
$removed = (get-ChildItem -Path "$dir").where{ $_.name -like "*.log" -and $_.LastWriteTime -lt (Get-Date).AddDays(-31) } 
$removed | Remove-Item
if( $removed ) {
    "Removed the following files:"
    $removed.name
}

Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader

# Start the timer
$stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "The stopwatch has started" -ForegroundColor Yellow

#endregion Logging
#####-----------------------------------------------------------------------------------------#####
#region User Input

$hostname = Read-Host -Prompt "Enter the Hostname or IP Address of your SolarWinds server"
$credential = Get-Credential -Message "Please enter your SolarWinds credentials"

#endregion User Input
#####-----------------------------------------------------------------------------------------#####
#region Connections

$swis = Set-SwisConnection -SolarWindsServer $hostname -Credential $credential

#endregion Connections
#####-----------------------------------------------------------------------------------------#####  
#region Execution

"Finding templates to export"
$templates = get-swisdata $swis @"
select at.name as template, at.ApplicationTemplateID, a.name, count(*) as instances
from orion.apm.ApplicationTemplate at
left join orion.apm.Application a on a.ApplicationTemplateID=at.ApplicationTemplateID
group by at.name, a.name, at.ApplicationTemplateID
"@

$TempPath = "$dir\TemplateExports\"
if((test-path $TempPath) -eq $false) {$null = mkdir -path $TempPath}

foreach( $template in $templates ) {
    $templateXML = invoke-swisverb $swis "orion.apm.applicationtemplate" "ExportTemplate" $template.applicationtemplateid
    $namecleanup = "$($template.template)"
    $namecleanup = $namecleanup.Replace("\", " ").Replace("/", " ").replace("<"," ").replace(">"," ").replace(":"," ").replace("|"," ").replace("?", " ").replace("*"," ").replace("[","").replace("]","")

    " Exporting view $namecleanup.xml to $TempPath"
    
    $templateXML | Export-Clixml ($TempPath + "$namecleanup.xml")
}

# Note: Removal of database entries has been removed as per user request. This section now focuses on file management.

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

"`nCompleted"

$stopWatch.Stop()

Write-Host "Script duration: $( $stopWatch.Elapsed.Minutes ) min, $( $stopWatch.Elapsed.Seconds ) sec" -ForegroundColor Yellow
