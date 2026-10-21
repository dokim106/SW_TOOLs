####### Startup #######
#please use a powershell integrated console to run script
#Watch for user to put "-configure" after the script in case config entry is needed
[cmdletbinding()]
param(
    [switch]$configure  
)

####### Global Variables ######
$configFileName = "\config.json"
$scriptDir = Split-Path -parent $PSCommandPath
$configFullPath = $scriptDir + $configFileName
$testMode = $false
$logPath = $PSScriptRoot

###### Functions ######
#Function to set the config file, if needed
function Set-ConfigurationFile ($configFileName) {
    #remove any existing config file if needed
    try {
        Remove-item $configFullPath
    }
    catch {
        #no file to remove, just continue
    }
    #promt user for the client name
    $clientName = read-host -prompt "Client Name"
    #prompt user for hostname of SolarWinds server
    $SolarWindsHost = read-host -prompt "SolarWinds Server IP/Hostname"
    #prompt user for a username
    $userName = read-host -prompt "SolarWinds Username"
    #prompt user for a password
    $pwdInput = read-host -prompt "SolarWinds Password" -AsSecureString
    #convert from a PS Secure String object into encrypted string for storage
    $pwdEncStr = ConvertFrom-SecureString $pwdInput
    # Build a config object to store as JSON config file
    $configObj = [PSCustomObject]@{
        SolarWinds = @{
            clientName = $clientName
            SolarWindsHost = $SolarWindsHost
            SolarWindsUser = $userName
            SolarWindsPw   = $pwdEncStr
        }
    }
    # Write the config file
    ConvertTo-Json -InputObject $configObj -depth 100 | out-file $configFullPath
}

#Main function for all SolarWinds queries
function Get-Results($query){
    $results = Get-SwisData $swis -Query $query
    try{
        $results = Get-SwisData $swis -Query $query -ErrorAction Stop
    }
    catch{
        $message = "There was an error executing '"+$query+"': $($PSItem.ToString())"
        Write-L1Log -message $message -severity "[WARN]"
        return $null
    }
    return $results
}

function Write-L1Log (){
    param(
        [Parameter()]
        [string]$message,
        [Parameter()]
        [string]$severity
    )
    if ($testMode -eq $true) {
        Write-Host $message
    } else {
        #debug
        $timeStamp = Get-Date
        $messageText = "$($timeStamp)`t[$($severity)] $($Message)"
        # get the current date NUMBER in STRING format for unique filename
        # add/remove time formatting to create new file names on that unit
        # this example is hourly -Format "yyyyMMddHH"
        [string]$dateNBR = (Get-Date -Format "yyyy-MM-dd")
        # build the full path file name
        $logFileName = "\$($dateNBR).log"
        $logFullPath = $logPath + $logFileName
        #check if the Directory exists 
        #create if missing or add-content will fail
        if (Test-Path -Path $logPath){
            #the path exists
            #write/append to the file
            #the file will be created if it doesn't exist
            Add-Content -Path $logFullPath -Value $messageText
        }else{
            #we need to go back up a level to create the new dir
            $newFolder = $logPath.replace("\log", "")
            new-item -Path $newFolder -Name "log" -ItemType "directory"
            #Enter a first entry when the log dir is made
            $firstTimeStamp = (Get-Date -Format "yyyy-MM-dd HH:mm")
            $firstMessageText = "the Log directory was created."
            Add-Content -Path $logFullPath -Value "$($firstTimeStamp)`t$($firstMessageText)"
            #write/append to the file with original message passed to the function
            Add-Content -Path $logFullPath -Value $messageText
        }
        # clean up check point
        # delete any log files > 30 days old
        #$oldLogs = $logPath | Get-ChildItem | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30) -and $_.}
        if($oldLogs.Count -gt 1){
            # \Log it  > Use this block format to submit log entries
            $logMessage += "`tDeleting old log files: "
            $logMessage += $oldLogs
            Add-Content -Path $logFullPath -Value $logMessage
            # /Log it
            $oldLogs | remove-item
        }
    }
}

####### Verify Modules and Files #######
#Make sure SWIS module is installed and load it.
if (!(Get-InstalledModule | Where-Object { $_.Name -eq "SwisPowerShell" })) {
    try { Import-Module SwisPowerShell }
    catch {
        $message = "Failed to import SwisPowerShell Module."
        Write-L1Log -message $message -severity "FATAL"
        exit
    }
}

#Make sure PSWriteOffice is installed
if (!(Get-InstalledModule | Where-Object { $_.Name -eq "PSWriteOffice" })) {
    try { Import-Module PSWriteOffice }
    catch {
        $message = "Failed to import PSWriteOffice Module."
        Write-L1Log -message $message -severity "FATAL"
        exit
    }
}

#If user sets the config flag or if the config file is missing, trigger the config file builder
if (($configure) -or (!(Test-Path $configFullPath))) {
    Set-ConfigurationFile $configFileName
}

#We should now have a config file no matter what. Retrieve its data.
try{
    $configJSON = Get-Content $configFullPath
}
catch{
    $message = "Could not access the config.json file."
    Write-L1Log -message $message -severity "FATAL"
    exit
}

####### Connect to SolarWinds #######
$config = $configJSON | ConvertFrom-Json
$clientName = $config.SolarWinds.clientName
$SolarWindsHost = $config.SolarWinds.SolarWindsHost
$SolarWindsUser = $config.SolarWinds.SolarWindsUser
$SolarWindsPwdFromConfig = $config.SolarWinds.SolarWindsPw

#Convert password to Secure String so we can build a creds object with it
$pwdSecStr = ConvertTo-SecureString $SolarWindsPwdFromConfig

# Build the credential object from the config file
[pscredential]$creds = New-Object System.Management.Automation.PSCredential ($SolarWindsUser, $pwdSecStr)

# Connect to Swis
$swis = Connect-Swis -Credential $creds -Hostname $SolarWindsHost  # create a SWIS connection object

####### Verify Installed Modules #######
#Make modules hashtable
$modules = [ordered]@{}

#Add each module and whether they're installed into the modules hashtable
#1 module installed, 0 module not installed
#Default Modules
[void]$modules.Add("High-Level Design", 1)
[void]$modules.Add("SolarWinds Platform Servers", 1)
[void]$modules.Add("SolarWinds Platform Polling", 1)
[void]$modules.Add("SolarWinds Platform Core", 1)

#NPM
try{
    $isNPM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='NPM'")
}
catch{
    $message = "Could not check for the existence of NPM"
    Write-L1Log -message $message -severity "WARN"
    $isNPM = 0
}
[void]$modules.Add("NPM", $isNPM)

#SAM
try{
    $isSAM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='APM'")
}
catch{
    $message = "Could not check for the existence of SAM"
    Write-L1Log -message $message -severity "WARN"
    $isSAM = 0
}
[void]$modules.Add("SAM", $isSAM)

#NCM
try{
    $isNCM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='NCM'")
}
catch{
    $message = "Could not check for the existence of NCM"
    Write-L1Log -message $message -severity "WARN"
    $isNCM = 0
}
[void]$modules.Add("NCM", $isNCM)

#IPAM
try{
    $isIPAM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='IPAM'")
}
catch{
    $message = "Could not check for the existence of IPAM"
    Write-L1Log -message $message -severity "WARN"
    $isIPAM = 0
}
[void]$modules.Add("IPAM", $isIPAM)

#UDT
try{
    $isUDT = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='UDT'")
}
catch{
    $message = "Could not check for the existence of UDT"
    Write-L1Log -message $message -severity "WARN"
    $isUDT = 0
}
[void]$modules.Add("UDT", $isUDT)

#VNQM
try{
    $isVNQM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='VoIP'")
}
catch{
    $message = "Could not check for the existence of VNQM"
    Write-L1Log -message $message -severity "WARN"
    $isVNQM = 0
}
[void]$modules.Add("VNQM", $isVNQM)

#WPM
try{
    $isWPM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='SEUM'")
}
catch{
    $message = "Could not check for the existence of WPM"
    Write-L1Log -message $message -severity "WARN"
    $isWPM = 0
}
[void]$modules.Add("WPM", $isWPM)

#NTA
try{
    $isNTA = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='NTA'")
}
catch{
    $message = "Could not check for the existence of NTA"
    Write-L1Log -message $message -severity "WARN"
    $isNTA = 0
}
[void]$modules.Add("NTA", $isNTA)

#VIM
try{
    $isVMAN = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='VIM'")
}
catch{
    $message = "Could not check for the existence of VMAN"
    Write-L1Log -message $message -severity "WARN"
    $isVMAN = 0
}
[void]$modules.Add("VMAN", $isVMAN)

#LA
try{
    $isLA = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='OLM'")
}
catch{
    $message = "Could not check for the existence of LA"
    Write-L1Log -message $message -severity "WARN"
    $isLA = 0
}
[void]$modules.Add("LA", $isLA)

#SCM
try{
    $isSCM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='SCM'")
}
catch{
    $message = "Could not check for the existence of SCM"
    Write-L1Log -message $message -severity "WARN"
    $isSCM = 0
}
[void]$modules.Add("SCM", $isSCM)

#SRM
try{
    $isSRM = Get-Results("SELECT count(*) as installed FROM Orion.InstalledModule WHERE Name='SRM'")
}
catch{
    $message = "Could not check for the existence of SRM"
    Write-L1Log -message $message -severity "WARN"
    $isSRM = 0
}
[void]$modules.Add("SRM", $isSRM)

#Add Admin table last
[void]$modules.Add("SolarWinds Administration", 1)
[void]$modules.Add("Scalability", 1)

####### Manage Microsoft Word #######
#Determine the document name
$date = Get-Date -Format "MM-dd-yyyy"
$sanitizedHost = $SolarWindsHost.Replace(".", "-")
$documentName = "$($clientName)_$($sanitizedHost)_$($date).txt"

#Make a new word document at desired path
try{
    $WordDocument = New-OfficeWord -FilePath $PSScriptRoot\$documentName -ErrorAction Stop
}
catch{
    $message = "Could not create a new word document in your directory with the follpwing error: $($PSItem.ToString())"
    Write-L1Log -message $message -severity "FATAL"
    exit
}

#Add Title
try{
    New-OfficeWordText -Document $WordDocument -Text 'SolarWinds Platform As Built' -Color Blue -Alignment center -Style Heading1 -ErrorAction Stop
}
catch{
    $message = "Could not title the word document with the following error: $($PSItem.ToString())"
    Write-L1Log -message $message -severity "WARN"
}

####### Process Health Check #######

#Look for the SWQL_Scripts folder
$rootFolderPath = $PSScriptRoot+"/SWQL_Scripts"

foreach ($module in $modules.GetEnumerator()){
    #Check to see if the module is installed
    if ($module.Value -eq 1){
        # Assign the folder path
        $moduleFolderPath = $rootFolderPath+"/$($module.Name)"

        # Get all text files in the current folder
        try{
            $textFiles = Get-ChildItem -Path $moduleFolderPath -Filter *.txt -ErrorAction Stop
        }
        catch{
            $message = "Could not find $($module.Name) in SWQL_Scripts"
            Write-L1Log -message $message -severity "WARN"
            Continue
        }

        #Run relevant queries
        if($textFiles){
            #Title the module section
            try{
                New-OfficeWordText -Document $WordDocument -Text $module.Name -Color Black -Bold $true -Style Heading2 -ErrorAction Stop
            }
            catch{
                $message = "Could not title the section for $moduleName with the following error: $($PSItem.ToString())"
                Write-L1Log -message $message -severity "WARN"
            }

            #Get the file name and content
            foreach ($file in $textFiles) {
                # Get the file name
                $fileName = [io.path]::GetFileNameWithoutExtension($file.FullName)

                # Read the content of the file
                $fileContent = Get-Content -Path $file.FullName -Raw

                #Use the query to get info from SolarWinds
                $result = Get-Results($fileContent)

                #If result is not empty
                if ($result){
                    #Create the table with a title
                    try{
                        New-OfficeWordText -Document $WordDocument -Text $fileName -Bold $true -Style Heading6 -ErrorAction Stop
                    }
                    catch{
                        $message = "Could not create title'$fileName' with the following error: $($PSItem.ToString())"
                        Write-L1Log -message $message -severity "WARN"
                    }

                    try{
                        New-OfficeWordTable -Document $WordDocument -DataTable $result -Style GridTable5Dark -ErrorAction Stop 
                    }
                    catch{
                        $message = "Could not create '$fileName' table with the following error: $($PSItem.Tostring())"
                        Write-L1Log -message $message -severity "WARN" 
                    }
                }
                #Otherwise, record the error message in red text
                else{
                    $errmessage = "Could not create table '"+$fileName+"'. Check error log for more details."
                    try{
                        New-OfficeWordText -Document $WordDocument -Text $errmessage -Color Red -Style Heading6 -ErrorAction Stop
                    }
                    catch{
                        $message = "Could not create '$fileName' error message with the following error: $($PSItem.Tostring())"
                        Write-L1Log -message $message -severity "WARN"
                    }
                }
            }   
        }

        #Make some space in between sections
        New-OfficeWordText -Document $WordDocument
    }
}

#Save the word document
try{
    Save-OfficeWord $WordDocument
}
catch{
    $message = "Could save $documentName with the following error: $($PSItem.Tostring())"
    Write-L1Log -message $message -severity "WARN"
}

#Open the file
try{
    Invoke-Item -LiteralPath "$PSScriptRoot\$documentName"
}
catch{
    $message = "Could not open $documentName with the following error: $($PSItem.Tostring())"
    Write-L1Log -message $message -severity "WARN"
}