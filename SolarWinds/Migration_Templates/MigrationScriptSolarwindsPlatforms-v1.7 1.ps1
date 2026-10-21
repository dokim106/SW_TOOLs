#   Migration Script Solarwinds Platforms
#   Author:     Author Name
#   Email:      author@example.com
#   Version:    1.0
#   History:    2023-09 HM - Creation of Script
#               2023-10 HM - Extension and Bugfixing
#######################################


# Functions #
function WriteLogEntry($Severity, $Message) 
{

}

function ip2guid($ip)
{
    $ipx = @()
    foreach ($ipa in $ip.split("."))
    {
    $ipx += "{0:X2}" -f [int]$ipa #Hex
    }
    
    $ipy = $ipx[3] + $ipx[2] + $ipx[1] + $ipx[0] + "-0000-0000-0000-000000000000"
    $ipy = $ipy.replace(' ', '')  
    return($ipy) 
}

function IsEmpty($str) 
{ 
    $null -eq $str -or $str -eq '' -or $str.GetType() -eq [DBNull] 
}

function DoesCPExist($Table, $Field)
{
    $CPExists = ''
    $CPExists = Get-SwisData $target "SELECT Field 
                                        FROM Orion.CustomProperty 
                                        WHERE Field = @FieldValue 
                                        AND Table=@Table" @{ FieldValue=$Field
                                                             Table=$Table}
    if($CPExists){
        return $true
    }
    else{
        return $false
    }                                                             
    
                                                            
}

function SelectTargetEngineID ($PollingMethod, $SwisConn)
{
    $Query = "SELECT TOP 1 COUNT(nodeID) as Number ,ObjectSubType, EngineID 
                FROM Orion.Nodes 
                WHERE ObjectSubType = '$PollingMethod'
                GROUP BY ObjectSubType, EngineID 
                ORDER by Number ASC"
    $Engine = Get-SwisData -SwisConnection $SwisConn -Query $Query
    
    if(!(IsEmpty $Engine.EngineID)){
        return $Engine.EngineID
    }
    else{
        $Engine = Get-SwisData -SwisConnection $SwisConn -Query "SELECT TOP 1 EngineID from orion.engines"
        return $Engine
    }
    
}

function DoesParentContainerExistInTarget($ParentContainer)
{
    $ParentContainerURI = $false
    $ParentContainerURI = Get-SwisData $source "SELECT Uri FROM Orion.groups where Name=@NewName" @{NewName=$Parentcontainer}

    return $ParentContainerURI
}

function DoesSourceHaveParent ($ContainerID)
{
        #Check if Group has Parent Group -> different SWIS Verb for creating the group
        $Searchstring='Groups.ContainerID='+$ContainerID.ToString()
        $HasParent = $false
        $HasParent = Get-SwisData $source "SELECT ContainerID FROM Orion.ContainerMemberDefinition where Expression =@Searchstring" @{Searchstring=$Searchstring}
        return $HasParent
}

function DoesTargetNodeExist($SourceIP){
    $targetNodeUri = Get-SwisData $target "SELECT Uri FROM Orion.Nodes WHERE IPAddress=@SourceIP" @{SourceIP = $SourceIP}
    if($targetNodeUri){
        return $true
    }
    else{
        return $false
    }
}

function CreateContainerWithPartent($ContainerName, $ContainerDescription, $ContainerProperties, $Pollingenabled, $ContainerMembers, $ContainerPartentID, $ContainerRefresh, $ContainerStatusCalulator){
        $groupId = (Invoke-SwisVerb $target "Orion.Container" "CreateContainerwithParent" @(
        #ParentID
        $ContainerPartentID
        # group name
        $ContainerName,
        # owner, must be 'Core'
        'CORE',
        # refresh frequency
        $ContainerRefresh,
        # Status rollup mode:
        # 0 = Mixed status shows warning
        # 1 = Show worst status
        # 2 = Show best status
        $ContainerStatusCalulator,
        # group description
        $ContainerDescription,
        # polling enabled/disabled = true/false (in lowercase)
        $Pollingenabled,
        # group members
        ([xml]@(
           "<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
           [string]($ContainerMembers |% {
             "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
             }
           ),
           "</ArrayOfMemberDefinitionInfo>"
            )).DocumentElement
        )).InnerText
       
        return $groupId
}

function CreateContainer($ContainerName, $ContainerDescription, $ContainerProperties, $Pollingenabled, $ContainerMembers, $ContainerRefresh, $ContainerStatusCalulator){
        $groupId = (Invoke-SwisVerb $target "Orion.Container" "CreateContainer" @(
        # group name
        $ContainerName,
        # owner, must be 'Core'
        'CORE',
        # refresh frequency
        $ContainerRefresh,
        # Status rollup mode:
        # 0 = Mixed status shows warning
        # 1 = Show worst status
        # 2 = Show best status
        $ContainerStatusCalulator,
        # group description
        $ContainerDescription,
        # polling enabled/disabled = true/false (in lowercase)
        $Pollingenabled,
        # group members
        ([xml]@(
           "<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
           [string]($ContainerMembers |% {
             "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
             }
           ),
           "</ArrayOfMemberDefinitionInfo>"
            )).DocumentElement
        )).InnerText
       
        return $groupId
}

function RewriteContainerMembersTable($MemberTable){
    $NewMemberTable = @()  
    if($null -eq $MemberTable){
        $NewMemberTable = @(
            ##  No Members in the Sorting Group
            @{ Name = "Dummy Devices"; Definition = "filter:/Orion.Nodes[Vendor='Dummy']" }    
            )
    }
    foreach($Member in $MemberTable){
        $DefinitionType = $Member.Definition
        $NewMemberObject = New-Object psobject
        if($DefinitionType -like "filter*"){
            $NewMemberObject | add-member Noteproperty Name          $Member.Name
            $NewMemberObject | add-member Noteproperty Definition    $Member.Definition
            $NewmemberTable += $NewMemberObject             
        }

        else{
        switch($Member.entity){
         "Orion.Nodes" {
           $SourceNodeProperties = Get-SwisObject -SwisConnection $source -Uri $Member.definition
           $DestinationNodeProperties = Get-SwisData -SwisConnection $target -Query "SELECT URI, NodeID from Orion.Nodes where Caption = @SourceNodeCaption" @{SourceNodeCaption = $SourceNodeProperties.Caption}
           $DestinationNode = Get-SwisObject -SwisConnection $target -Uri $DestinationNodeProperties.Uri
           #if we can't find the destination node,skip it#
           if($null -eq $DestinationNode){
            continue
           }
           $NewNodeString = "Orion.Nodes.NodeID="+$DestinationNode.NodeID

           $NewMemberObject | add-member Noteproperty Name           $NewNodeString
           $NewMemberObject | add-member Noteproperty Definition     $DestinationNode.URI
           $NewmemberTable += $NewMemberObject
        }
         "Orion.Groups"{}
         "Orion.NPM.Interfaces" {
          $SourceInterfaceProperties = Get-SwisObject -SwisConnection $source -Uri $Member.definition
          #if we can't find the target interface, continue#
          if($null -eq $SourceInterfaceProperties){
            continue
          }
          $DestinationInterfaceProperties = Get-SwisData -SwisConnection $target -Query "SELECT if.URI, if.InterfaceID, if.node.NodeID from Orion.NPM.Interfaces as if where if.FullName = @SourceInterfaceFullName" @{SourceInterfaceFullName = $SourceInterfaceProperties.FullName}
          $NewMemberName = "Orion.Nodes.NodeID="+$DestinationInterfaceProperties.NodeID+" AND Interfaces.InterfaceID="+$DestinationInterfaceProperties.InterfaceID
          $NewMemberObject | add-member Noteproperty Name           $NewMemberName
          $NewMemberObject | add-member Noteproperty Definition     $DestinationInterfaceProperties.URI
          $NewmemberTable += $NewMemberObject            
        }
         "Orion.APM.Application" {}
         "Orion.Volumes"{}
        }
        }
    }
    # if all queries failed and we do not have any members in our table, create a dummy
    if($null -eq $NewMemberTable -or $NewMemberTable.Length -eq 0 ){
        $NewMemberTable = @(
            ##  No Members in the Sorting Group
            @{ Name = "Dummy Devices"; Definition = "filter:/Orion.Nodes[Vendor='Dummy']" }    
            )
    }
 return $NewMemberTable
}

function GetDestinationWMISettingID($NodeID){
    $WmiCredNameSource = Get-SwisData -SwisConnection $source -Query "SELECT NSet.NodeID, NSet.SettingName, NSet.SettingValue, NSet.NodeSettingID, Cred.Name
                                                                      FROM Orion.NodeSettings as NSet Left Join Orion.Credential as Cred ON NSet.SettingValue = Cred.ID
                                                                      WHERE Nset.SettingName = 'WMICredential' and NSet.NodeID = @NodeID"@{NodeID = $NodeID}

   $WmiCredDestID = Get-SwisData -SwisConnection $target -Query "SELECT ID
                                                                 FROM Orion.Credential 
                                                                 WHERE CredentialOwner = 'Orion' AND Name = @Credentialname" @{Credentialname = $WmiCredNameSource.Name}
    ## If we did not get a successful credential, pick the first in the list with a \ in the name
    if($null -eq $WmiCredDestID){
        $WmiCredDestID = Get-SwisData -SwisConnection $target -Query "SELECT TOP 1 ID, Name, Description, CredentialType, CredentialOwner
                                                                      FROM Orion.Credential
                                                                      WHERE CredentialOwner = 'Orion' and Name like '%\%'"
       return $WmiCredDestID                                                                      
    }
    else{
        return $WmiCredDestID
    }

}
# END Functions #

# PSModules #
if (!(Get-Module | where-object {$_.Name -eq "SWISPowerShell"})) {
    Import-Module "SWISPowerShell"
}
# END PSModules #


# Variables Holger #
$SourceHost = '<source server>'
$SourceUser = 'admin'
$SourcePass = 'supersecretpassword'
$SourceCred = New-Object -typename System.Management.Automation.PSCredential -argumentlist @($SourceUser,(ConvertTo-SecureString -String $SourcePass -AsPlainText -Force))

$destinationHost = '<destination server>'
$DestinationUser = 'admin'
$DestinationPass = 'supersecretpassword'
$DestinationCred = New-Object -typename System.Management.Automation.PSCredential -argumentlist @($DestinationUser,(ConvertTo-SecureString -String $DestinationPass -AsPlainText -Force))



# start Connection #
$global:source = Connect-Swis -Credential $SourceCred -Hostname $SourceHost
#Trusted Connection with Certificate - run script as admin to read the Certificate
#$source = Connect-Swis -Hostname $SourceHost -Trusted

$global:target = Connect-Swis -Credential $DestinationCred -Hostname $destinationHost
#Trusted Connection with Certificate - run script as admin to read the Certificate
#$target = Connect-Swis -Hostname $destinationHost -Trusted

# Copy Custom properties
## Get all Custom Properties and create CP Buckets Copy those to the destination ##
$AllCustomProperties = Get-SWISData $source "SELECT Table
                                                    ,Field
                                                    ,DataType
                                                    ,MaxLength
                                                    ,StorageMethod
                                                    ,Description
                                                    ,TargetEntity
                                                    ,Mandatory
                                                    ,Default
                                                    ,DisplayName
                                            FROM Orion.CustomProperty"

## create custom property baskets to use in queries etc.
$AlertsCustomProperties = '('
$ApplicationCustomProperties = '('
$GroupCustomProperties = '('
$InterfaceCustomProperties = '('
$IPAMCustomProperties = '('
$NodesCustomProperties = '('
$ReportsCustomProperties = '('
$VolumesCustomProperties = '('

## Fill Baskets and create the property if it does not exist in the destination
foreach($Customproperty in $AllCustomProperties)
{
    switch($Customproperty.Table)
    {
        AlertConfigurationsCustomProperties {$AlertsCustomProperties = $AlertsCustomProperties + $Customproperty.Field + ','
                                             if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                                                {
                                                    write-host 'CP Already exists'
                                                }
                                             else
                                             {
                                                $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "")
                                                Invoke-SwisVerb -Swis $target Orion.AlertConfigurationsCustomProperties CreateCustomProperty $CPProps
                                             } 
                                             continue  
                                            }
        APM_ApplicationCustomProperties {$ApplicationCustomProperties = $ApplicationCustomProperties + $Customproperty.Field + ','
                                        if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                                        {
                                            write-host 'CP Already exists'
                                        }
                                        else
                                        {
                                            $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "", "", $false, "", "", "")
                                            Invoke-SwisVerb -Swis $target Orion.APM.ApplicationCustomProperties CreateCustomProperty $CPProps
                                        } 
                                        continue
                                        }
        ContainerCustomProperties {$GroupCustomProperties = $GroupCustomProperties + $Customproperty.Field + ','
                                    if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                                        {
                                            write-host 'CP Already exists'
                                        }                                      
                                    
                                    else
                                    {
                                        $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "")
                                        Invoke-SwisVerb -Swis $target Orion.GroupCustomProperties CreateCustomProperty $CPProps
                                    } 
                                    continue
                                }
        Interfaces {$InterfaceCustomProperties = $InterfaceCustomProperties + $Customproperty.Field + ','
                    if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                    {
                        write-host 'CP Already exists'
                    }
                    else
                    {
                        $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "")
                        Invoke-SwisVerb -Swis $target Orion.NPM.InterfacesCustomProperties CreateCustomProperty $CPProps
                    } 
                    continue
                    }
        IPAM_GroupAttrData {$IPAMCustomProperties = $IPAMCustomProperties + $Customproperty.Field + ','
                            if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                            {
                                write-host 'CP Already exists'
                            }
                            else
                            {
                                $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "")
                                Invoke-SwisVerb -Swis $target Orion.NPM.InterfacesCustomProperties CreateCustomProperty $CPProps
                            }
                            continue 
                            }
        NodesCustomProperties {$NodesCustomProperties = $NodesCustomProperties + $Customproperty.Field + ','
                                if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                                {
                                    write-host 'CP Already exists'
                                }
                                else
                                {
                                    ## Setting a negative length to ZERO - Some Builtin Properties have the Length set to -1, don't know what SWI thought here##
                                    if($Customproperty.MaxLength -eq -1){
                                        $Customproperty.MaxLength = '0'
                                    }
                                    $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "")
                                    Invoke-SwisVerb -Swis $target Orion.NodesCustomProperties CreateCustomProperty $CPProps
                                } 
                                continue
                                }
        ReportDefinitions {$ReportsCustomProperties = $ReportsCustomProperties + $Customproperty.Field + ',' 
                            if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                            {
                                write-host 'CP Already exists'
                            }
                            else
                            {
                                $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "")
                                Invoke-SwisVerb -Swis $target Orion.ReportsCustomProperties CreateCustomProperty $CPProps
                            } 
                            continue
                            }
        Volumes {$VolumesCustomProperties = $VolumesCustomProperties + $Customproperty.Field + ','
                if(DoesCPExist -Table $Customproperty.Table -Field $Customproperty.Field)
                {
                    write-host 'CP Already exists'
                }
                else
                {
                    $CPProps = @($Customproperty.Field, $Customproperty.Description, $Customproperty.DataType, $Customproperty.MaxLength, "", "", "", "", "", "")
                    Invoke-SwisVerb -Swis $target Orion.VolumesCustomProperties CreateCustomProperty $CPProps
                } 
                continue
                }

    }
}

# Finish CustomPropertyBaskets - delete trailing "," and close brackets. 
$AlertsCustomProperties = $AlertsCustomProperties.Trimend(',') + ')'
$ApplicationCustomProperties = $ApplicationCustomProperties.Trimend(',') + ')'
$GroupCustomProperties = $GroupCustomProperties.Trimend(',') + ')'
$InterfaceCustomProperties = $InterfaceCustomProperties.Trimend(',') + ')'
$IPAMCustomProperties = $IPAMCustomProperties.Trimend(',') + ')'
$NodesCustomProperties = $NodesCustomProperties.Trimend(',')  + ')'
$ReportsCustomProperties = $ReportsCustomProperties.Trimend(',') +')'
$VolumesCustomProperties = $VolumesCustomProperties.Trimend(',') + ')'

if(DoesCPExist -Table 'NodesCustomProperties' -Field 'MigratedByAPI'){
    write-host 'CP Already exists'
}
else{
    Invoke-SwisVerb -Swis $target Orion.NodesCustomProperties CreateCustomProperty @("MigratedByAPI", "CopiedFromOldEnvironmentbyScript", "System.String", 100, "", "", "", "", "", "") 
}



# Copy non Agent and SNMP Nodes #
$nodePropsToCopy = @("AgentPort", "Allow64BitCounters", "BufferBgMissThisHour", "BufferBgMissToday", "BufferHgMissThisHour", "BufferHgMissToday", 
    "BufferLgMissThisHour", "BufferLgMissToday", "BufferMdMissThisHour", "BufferMdMissToday", "BufferNoMemThisHour", "BufferNoMemToday", 
    "BufferSmMissThisHour", "BufferSmMissToday", "Caption", "ChildStatus", "CMTS", "Community", "Contact", "DNS", "DynamicIP", "External", 
    "EntityType", "GroupStatus", "IOSImage", "IOSVersion", "IPAddress", "IPAddressGUID", "IPAddressType", "LastSystemUpTimePollUtc",  
    "Location", "MachineType", "NodeDescription", "ObjectSubType", "PollInterval", "RediscoveryInterval", "Severity", "SNMPVersion", 
    "StatCollection", "Status", "StatusDescription", "StatusLED", "SysName", "SysObjectID", "TotalMemory", "Vendor", "VendorIcon", 
    "RWCommunity") 

$interfacePropsToCopy = @("AdminStatus", "AdminStatusLED", "Caption", "Counter64", "CustomBandwidth", "FullName",  
    "IfName", "InBandwidth", "Inbps", "InDiscardsThisHour", "InDiscardsToday", "InErrorsThisHour", "InErrorsToday",  
    "InMcastPps", "InPercentUtil", "InPktSize", "InPps", "InterfaceAlias", "InterfaceIcon", "InterfaceIndex",  
    "InterfaceMTU", "InterfaceName", "InterfaceSpeed", "InterfaceSubType", "InterfaceType", "InterfaceTypeDescription",  
    "InterfaceTypeName", "InUcastPps", "MaxInBpsToday", "MaxOutBpsToday", "ObjectSubType", "OperStatus", "OutBandwidth",  
    "Outbps", "OutDiscardsThisHour", "OutDiscardsToday", "OutErrorsThisHour", "OutErrorsToday", "OutMcastPps",  
    "OutPercentUtil", "OutPktSize", "OutPps", "OutUcastPps", "PhysicalAddress", "PollInterval", "RediscoveryInterval",  
    "Severity", "StatCollection", "Status", "StatusLED", "UnManaged", "UnPluggable") 

$volumePropsToCopy = @("Icon", "Index", "Caption", "StatusIcon", "Type", "Size", "Responding", "FullName",  
    "VolumePercentUsed", "VolumeAllocationFailuresThisHour", "VolumeDescription", "VolumeSpaceUsed",  
    "VolumeAllocationFailuresToday", "VolumeSpaceAvailable", "VolumeTypeID")


# Get all SNMP and ICMP Nodes from Source
$sourceNodes = Get-SwisData $source "SELECT Uri, IPAddress, Caption, NodeID, ObjectSubType FROM Orion.Nodes where ObjectSubType NOT IN ('WMI', 'Agent') AND SNMPVersion IN ('2','1','0')" 
foreach ($sourceNode in $sourceNodes) { 
    Start-Sleep -Milliseconds 500
    # See if there is aleady a node on the target with the same IP address 
    $targetNodeUri = Get-SwisData $target "SELECT Uri FROM Orion.Nodes WHERE IPAddress=@ip" @{ip = $sourceNode.IPAddress}
     

    if ($null -ne $targetNodeUri) { 
        Write-Host "Skipping" $sourceNode.Caption "(" $sourceNode.IPAddress ") because it is already managed by " $hostname2 
        continue 
    } 


    # Fetch all properties of the source node 
    $sourceNodeProps = Get-SwisData $source "SELECT AgentPort, Allow64BitCounters, BufferBgMissThisHour, BufferBgMissToday, BufferHgMissThisHour, BufferHgMissToday, BufferLgMissThisHour, 
        BufferLgMissToday, BufferMdMissThisHour, BufferMdMissToday, BufferNoMemThisHour, BufferNoMemToday, BufferSmMissThisHour, BufferSmMissToday, 
        Caption, ChildStatus, CMTS, Community, Contact, DNS, DynamicIP, External, EntityType, GroupStatus, IOSImage, IOSVersion, IPAddress, IPAddressGUID, 
        IPAddressType, LastSystemUpTimePollUtc, Location, MachineType, NodeDescription, ObjectSubType, PollInterval, RediscoveryInterval, Severity, SNMPVersion, 
        StatCollection, Status, StatusDescription, StatusLED, SysName, SysObjectID, TotalMemory, Vendor, VendorIcon, RWCommunity         
         From Orion.Nodes Where NodeID = @nodeid" @{nodeid=$sourceNode.Nodeid}

    # Fetch all custom properties
    # Build the Select String from CP Bucket
    $NodeCustomPropsToCopy = $NodesCustomProperties.TrimStart('"(')
    $NodeCustomPropsToCopy = $NodeCustomPropsToCopy.TrimEnd(')"')
    $DummyNodeID = $sourceNode.Nodeid
    $Query = ''
    $query = "SELECT "+$NodeCustomPropsToCopy+" from Orion.NodesCustomProperties where NodeID = $DummyNodeID"
    $sourcenodeCPs = @{}
    $sourceNodeCPs = Get-SwisData -SwisConnection $source -Query $Query
 
     # Make an in-memory copy of the node 
     Write-Host "Copying" $sourceNode.Caption "(" $sourceNode.IPAddress ")" 
     $targetNodeProps = @{} 
     $nodePropsToCopy | Foreach-Object{ $targetNodeProps[$_] = $sourceNodeProps.$_ } 
     $targetNodeProps["EngineID"] = SelectTargetEngineID -PollingMethod $SourceNode.ObjectSubType -SwisConn $target
     
     # In-Memory copy of Customproperties
     $targetNodeCPs = @{}
     $sourceNodeCPs.psobject.Properties | Foreach-Object{ $targetNodeCPs[$_.Name] = $_.Value}     
 

     # Create the node on the target system 
     $newUri = New-SwisObject $target -EntityType "Orion.Nodes" -Properties $targetNodeProps 
     $newNode = Get-SwisObject $target $newUri 
 

     # Associate the custom property "MigratedByAPI" with this node and set its value to "true" 
     Set-SwisObject $target ($newUri+"/CustomProperties") @{ MigratedByAPI="true" } 

     #Set Copied Custom Properties
     Set-SwisObject $target ($newUri+"/CustomProperties") $targetNodeCPs
        


     # Copy the pollers for the new node 
     $pollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject='N:' + $sourceNode.NodeID } 
      
     foreach ($pollerType in $pollerTypes) { 
         $poller = @{ 
             PollerType = "$pollerType"; 
             NetObject = "N:" + $newNode.NodeID; 
             NetObjectType = "N"; 
             NetObjectID = $newNode.NodeID; 
         } 
         Write-Host "    Adding poller $pollerType" 
         New-SwisObject $target -EntityType "Orion.Pollers" -Properties $poller | Out-Null 
     } 
        
          
    # Get the interfaces on the source node
    $sourceInterfaces = ''
    $sourceInterfaces = Get-SwisData $source "SELECT Nodes.Interfaces.Uri, Nodes.Interfaces.InterfaceID FROM Orion.Nodes WHERE NodeID=@node" @{ node=$sourceNode.NodeID } 
    if($sourceinterfaces.Length -eq 0){
    # do nothing for Interfaces, because source does  not have interfaces  
    }
    else{
    foreach ($sourceInterface in $sourceInterfaces) { 
        if (IsEmpty $sourceInterface.URI) { 
            continue 
        } 

    $sourceIfProps = Get-SwisObject $source $sourceInterface.uri
    if($sourceIfProps.HasObsoleteData -eq 1 -or $sourceIfProps.length -eq 0){
        #do nothing
    }
    else{
        # Build the Select String from CP Bucket
    $InterfaceCustomPropsToCopy = $InterfaceCustomProperties.Trim('"()')
    #$InterfaceCustomPropsToCopy = $InterfaceCustomPropsToCopy.TrimEnd(')"')
    $InterfaceID = $sourceInterface.InterfaceID
    $InterfaceURI = $sourceInterface.Uri
    $Query = ''
    $Query = "SELECT "+$InterfaceCustomPropsToCopy+" FROM Orion.NPM.InterfacesCustomProperties where InterfaceID = $InterfaceID"
    $sourceIFCPs = @{}
    $sourceIFCPs = Get-SwisData -SwisConnection $source -Query $Query
    

        Write-Host "  Copying" $sourceNode.Caption "/" $sourceIfProps.Caption 
        $targetIfProps = @{} 
        $interfacePropsToCopy | %{ $targetIfProps[$_] = $sourceIfProps[$_] } 
        $targetIfProps["NodeID"] = $newNode.NodeID 
    
        # In-Memory copy of Interface Customproperties
    $targetIFCPs = @{}
    $sourceIFCPs.psobject.Properties | Foreach-Object{ $targetIFCPs[$_.Name] = $_.Value}     

        # Create the copy 
        $newIfUri = New-SwisObject $target -EntityType "Orion.NPM.Interfaces" -Properties $targetIfProps 
        $newIf = Get-SwisObject $target $newIfUri 

        # Set the Custom Properties                      
        Set-SwisObject $target ($newIfUri+"/CustomProperties") $targetIFCPs
        # Copy the pollers for the new interface 
        $ifPollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject = 'I:'+$sourceIfProps.InterfaceID } 

        foreach ($ifPollerType in $ifPollerTypes) { 
            $ifPoller = @{ 
                PollerType = "$ifPollerType"; 
                NetObject = "I:" + $newIf.InterfaceID; 
                NetObjectType = "I"; 
                NetObjectID = $newIf.InterfaceID; 
            } 
            Write-Host "      Adding poller $ifPollerType" 
            New-SwisObject $target -EntityType "Orion.Pollers" -Properties $ifPoller | Out-Null 
        } 
    }
    } 
    }
          
     # Get the volumes on the source node
     $sourceVolumes = ''      
     $sourceVolumes = Get-SwisData $source "SELECT Nodes.Volumes.Uri, Nodes.volumes.VolumeID FROM Orion.Nodes WHERE NodeID=@node" @{ node = $sourceNode.NodeID } 
        if($sourceVolumes.length -eq 0){
            # do nothing on volumes because source does not have volumes
        }
        else{
         foreach ($sourceVolume in $sourceVolumes) { 
             if (IsEmpty($sourceVolume.VolumeID)) { 
                 continue 
             } 
 

             $sourceVolProps = Get-SwisObject $source $sourceVolume.uri 
             Write-Host "  Copying" $sourceNode.Caption "/" $sourceVolProps.Caption 
             $targetVolProps = @{} 
             $volumePropsToCopy | %{ $targetVolProps[$_] = $sourceVolProps[$_] } 
             $targetVolProps["NodeID"] = $newNode.NodeID 
 

            # Build the Select String from CP Bucket
            if($VolumeCustomProperties){
                $VolumeCustomPropsToCopy = $VolumeCustomProperties.Trim('"()')
                $VolumeID = $sourceVolume.VolumeID            
                $Query = ''
                $Query = "SELECT "+$VolumeCustomPropsToCopy+" FROM Orion.VolumesCustomProperties where VolumeID = $VolumeID"
                $sourceVolumeCPs = @{}
                $sourceVolumeCPs = Get-SwisData -SwisConnection $source -Query $Query
                # In-Memory copy of Volume Customproperties                
                $targetVolumeCPs = @{}
                $sourceVolumeCPs.psobject.Properties | Foreach-Object{ $targetVolumeCPs[$_.Name] = $_.Value}    
            }
            
            # Create the copy 
            $newVolUri = New-SwisObject $target -EntityType "Orion.Volumes" -Properties $targetVolProps 
            $newVol = Get-SwisObject $target $newVolUri 
 
            # Set the Custom Properties if Volume has Properties
            if($null -ne $targetVolumeCPs){                                              
            Set-SwisObject $target ($newVolUri+"/CustomProperties") $targetVolumeCPs
            }
            # Copy the pollers for the new Volume 
            $volPollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject='V:' + $sourceVolProps.VolumeID } 
      
             foreach ($volPollerType in $volPollerTypes) { 
                 $volPoller = @{ 
                     PollerType = "$volPollerType"; 
                     NetObject = "V:"+$newVol.VolumeID; 
                     NetObjectType = "V"; 
                     NetObjectID = $newVol.VolumeID; 
                 } 
                 Write-Host "      Adding poller $volPollerType" 
                 New-SwisObject $target -EntityType "Orion.Pollers" -Properties $volPoller | Out-Null 
             } 
         } 
        }
     
     # If the Node was in NCM, add the new node to NCM 
     $IsNodeInNCM = $false
     $IsNodeInNCM = Get-SwisData -SwisConnection $source -Query "SELECT CoreNodeID from NCM.NODES where CoreNodeID = @NodeID" @{NodeID = $sourceNode.NodeID}    
    if($IsNodeInNCM){
        Invoke-SwisVerb $target Cirrus.Nodes AddNodeToNCM $newNode.NodeID 
    }  
      
 }
 
 ## SNMPv3 Nodes
$sourceNodesv3 = Get-SwisData $source "SELECT Uri, IPAddress, Caption, NodeID, ObjectSubType FROM Orion.Nodes where ObjectSubType NOT IN ('WMI', 'Agent')  AND SNMPVersion = '3'" 
foreach ($sourceNode in $sourceNodesv3) { 
    Start-Sleep -Milliseconds 500
    # See if there is aleady a node on the target with the same IP address 
    $targetNodeUri = Get-SwisData $target "SELECT Uri FROM Orion.Nodes WHERE IPAddress=@ip" @{ip = $sourceNode.IPAddress}     
    if ($null -ne $targetNodeUri) { 
        Write-Host "Skipping" $sourceNode.Caption "(" $sourceNode.IPAddress ") because it is already managed by " $hostname2 
        continue 
    } 
    # Fetch all properties of the source node 
    $sourceNodeProps = Get-SwisData $source "SELECT AgentPort, Allow64BitCounters, BufferBgMissThisHour, BufferBgMissToday, BufferHgMissThisHour, BufferHgMissToday, BufferLgMissThisHour, 
        BufferLgMissToday, BufferMdMissThisHour, BufferMdMissToday, BufferNoMemThisHour, BufferNoMemToday, BufferSmMissThisHour, BufferSmMissToday, 
        Caption, ChildStatus, CMTS, Community, Contact, DNS, DynamicIP, External, EntityType, GroupStatus, IOSImage, IOSVersion, IPAddress, IPAddressGUID, 
        IPAddressType, LastSystemUpTimePollUtc, Location, MachineType, NodeDescription, ObjectSubType, PollInterval, RediscoveryInterval, Severity, SNMPVersion, 
        StatCollection, Status, StatusDescription, StatusLED, SysName, SysObjectID, TotalMemory, Vendor, VendorIcon, RWCommunity         
         From Orion.Nodes Where NodeID = @nodeid" @{nodeid=$sourceNode.Nodeid}

    #Fetch SNMPV3Creds 
    $SNMPV3Creds = Get-SwisData -SwisConnection $source -Query "SELECT Username, Context, PrivacyMethod, PrivacyKey, PrivacyKeyIsPassword, AuthenticationMethod, AuthenticationKey, AuthenticationKeyIsPassword, RWUsername, RWContext, RWPrivacyMethod, RWPrivacyKey, RWPrivacyKeyIsPassword, RWAuthenticationMethod, RWAuthenticationKey, RWAuthenticationKeyIsPassword
                                                                FROM Orion.SNMPv3Credentials 
                                                                WHERE NodeID = @NodeID"@{NodeID=$sourceNode.NodeID } 
         
    # Fetch all custom properties
    # Build the Select String from CP Bucket
    $NodeCustomPropsToCopy = $NodesCustomProperties.TrimStart('"(')
    $NodeCustomPropsToCopy = $NodeCustomPropsToCopy.TrimEnd(')"')
    $DummyNodeID = $sourceNode.Nodeid
    $Query = ''
    $query = "SELECT "+$NodeCustomPropsToCopy+" from Orion.NodesCustomProperties where NodeID = $DummyNodeID"
    $sourceNodeCPs = Get-SwisData -SwisConnection $source -Query $Query
 

     # Make an in-memory copy of the node 
     Write-Host "Copying" $sourceNode.Caption "(" $sourceNode.IPAddress ")" 
     $targetNodeProps = @{} 
     $nodePropsToCopy | Foreach-Object{ $targetNodeProps[$_] = $sourceNodeProps.$_ }
     $SNMPV3Creds | Foreach-Object {} 
     $targetNodeProps["EngineID"] = SelectTargetEngineID -PollingMethod $SourceNode.ObjectSubType -SwisConn $target
     $targetNodeProps["SNMPV3Username"] = $SNMPV3Creds.Username
     $targetNodeProps["SNMPV3PrivMethod"] = $SNMPV3Creds.PrivacyMethod
     $targetNodeProps["SNMPV3PrivKey"] = $SNMPV3Creds.PrivacyKey
     $targetNodeProps["SNMPV3PrivKeyIsPwd"] = $SNMPV3Creds.PrivacyKeyIsPassword
     $targetNodeProps["SNMPV3AuthMethod"] = $SNMPV3Creds.AuthenticationMethod
     $targetNodeProps["SNMPV3AuthKey"] = $SNMPV3Creds.AuthenticationKey
     $targetNodeProps["SNMPV3AuthKeyIsPwd"] = $SNMPV3Creds.AuthenticationKeyIsPassword
      
     # In-Memory copy of Customproperties
     $targetNodeCPs = @{}
     $sourceNodeCPs.psobject.Properties | Foreach-Object{ $targetNodeCPs[$_.Name] = $_.Value}      
 

     # Create the node on the target system 
     $newUri = New-SwisObject $target -EntityType "Orion.Nodes" -Properties $targetNodeProps 
     $newNode = Get-SwisObject $target $newUri 
 
     # Associate the custom property "MigratedByAPI" with this node and set its value to "true" 
     Set-SwisObject $target ($newUri+"/CustomProperties") @{ MigratedByAPI='true' } 

     #Set Copied Custom Properties
     Set-SwisObject $target ($newUri+"/CustomProperties") $targetNodeCPs
        
     # Copy the pollers for the new node 
     $pollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject='N:' + $sourceNode.NodeID } 
     foreach ($pollerType in $pollerTypes) { 
         $poller = @{ 
             PollerType = "$pollerType"; 
             NetObject = "N:" + $newNode.NodeID; 
             NetObjectType = "N"; 
             NetObjectID = $newNode.NodeID; 
         } 
         Write-Host "    Adding poller $pollerType" 
         New-SwisObject $target -EntityType "Orion.Pollers" -Properties $poller | Out-Null 
     }  
     # Get the interfaces on the source node
    $sourceInterfaces = ''
    $sourceInterfaces = Get-SwisData $source "SELECT Nodes.Interfaces.Uri, Nodes.Interfaces.InterfaceID FROM Orion.Nodes WHERE NodeID=@node" @{ node=$sourceNode.NodeID } 
    if($sourceinterfaces.Length -eq 0){
    # do nothing for Interfaces, because source does  not have interfaces  
    }
    else{
    foreach ($sourceInterface in $sourceInterfaces) { 
        if (IsEmpty $sourceInterface.URI) { 
            continue 
        } 

    $sourceIfProps = Get-SwisObject $source $sourceInterface.uri
    if($sourceIfProps.HasObsoleteData -eq 1 -or $sourceIfProps.length -eq 0){
        #do nothing
    }
    else{
        # Build the Select String from CP Bucket
    $InterfaceCustomPropsToCopy = $InterfaceCustomProperties.Trim('"()')
    #$InterfaceCustomPropsToCopy = $InterfaceCustomPropsToCopy.TrimEnd(')"')
    $InterfaceID = $sourceInterface.InterfaceID
    $InterfaceURI = $sourceInterface.Uri
    $Query = ''
    $Query = "SELECT "+$InterfaceCustomPropsToCopy+" FROM Orion.NPM.InterfacesCustomProperties where InterfaceID = $InterfaceID"
    $sourceIFCPs = @{}
    $sourceIFCPs = Get-SwisData -SwisConnection $source -Query $Query
    

        Write-Host "  Copying" $sourceNode.Caption "/" $sourceIfProps.Caption 
        $targetIfProps = @{} 
        $interfacePropsToCopy | %{ $targetIfProps[$_] = $sourceIfProps[$_] } 
        $targetIfProps["NodeID"] = $newNode.NodeID 
    
        # In-Memory copy of Interface Customproperties
    $targetIFCPs = @{}
    $sourceIFCPs.psobject.Properties | Foreach-Object{ $targetIFCPs[$_.Name] = $_.Value}     

        # Create the copy 
        $newIfUri = New-SwisObject $target -EntityType "Orion.NPM.Interfaces" -Properties $targetIfProps 
        $newIf = Get-SwisObject $target $newIfUri 

        # Set the Custom Properties                      
        Set-SwisObject $target ($newIfUri+"/CustomProperties") $targetIFCPs
        # Copy the pollers for the new interface 
        $ifPollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject = 'I:'+$sourceIfProps.InterfaceID } 

        foreach ($ifPollerType in $ifPollerTypes) { 
            $ifPoller = @{ 
                PollerType = "$ifPollerType"; 
                NetObject = "I:" + $newIf.InterfaceID; 
                NetObjectType = "I"; 
                NetObjectID = $newIf.InterfaceID; 
            } 
            Write-Host "      Adding poller $ifPollerType" 
            New-SwisObject $target -EntityType "Orion.Pollers" -Properties $ifPoller | Out-Null 
        } 
    }
    } 
    }
          
     # Get the volumes on the source node
     $sourceVolumes = ''      
     $sourceVolumes = Get-SwisData $source "SELECT Nodes.Volumes.Uri, Nodes.volumes.VolumeID FROM Orion.Nodes WHERE NodeID=@node" @{ node = $sourceNode.NodeID } 
        if($sourceVolumes.length -eq 0){
            # do nothing on volumes because source does not have volumes
        }
        else{
         foreach ($sourceVolume in $sourceVolumes) { 
             if (IsEmpty($sourceVolume.VolumeID)) { 
                 continue 
             } 
 

             $sourceVolProps = Get-SwisObject $source $sourceVolume.uri 
             Write-Host "  Copying" $sourceNode.Caption "/" $sourceVolProps.Caption 
             $targetVolProps = @{} 
             $volumePropsToCopy | %{ $targetVolProps[$_] = $sourceVolProps[$_] } 
             $targetVolProps["NodeID"] = $newNode.NodeID 
 

            # Build the Select String from CP Bucket
            if($VolumeCustomProperties){
                $VolumeCustomPropsToCopy = $VolumeCustomProperties.Trim('"()')
                $VolumeID = $sourceVolume.VolumeID            
                $Query = ''
                $Query = "SELECT "+$VolumeCustomPropsToCopy+" FROM Orion.VolumesCustomProperties where VolumeID = $VolumeID"
                $sourceVolumeCPs = @{}
                $sourceVolumeCPs = Get-SwisData -SwisConnection $source -Query $Query
                # In-Memory copy of Volume Customproperties                
                $targetVolumeCPs = @{}
                $sourceVolumeCPs.psobject.Properties | Foreach-Object{ $targetVolumeCPs[$_.Name] = $_.Value}    
            }
            
            # Create the copy 
            $newVolUri = New-SwisObject $target -EntityType "Orion.Volumes" -Properties $targetVolProps 
            $newVol = Get-SwisObject $target $newVolUri 
 
            # Set the Custom Properties if Volume has Properties
            if($null -ne $targetVolumeCPs){                                              
            Set-SwisObject $target ($newVolUri+"/CustomProperties") $targetVolumeCPs
            }
            # Copy the pollers for the new Volume 
            $volPollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject='V:' + $sourceVolProps.VolumeID } 
      
             foreach ($volPollerType in $volPollerTypes) { 
                 $volPoller = @{ 
                     PollerType = "$volPollerType"; 
                     NetObject = "V:"+$newVol.VolumeID; 
                     NetObjectType = "V"; 
                     NetObjectID = $newVol.VolumeID; 
                 } 
                 Write-Host "      Adding poller $volPollerType" 
                 New-SwisObject $target -EntityType "Orion.Pollers" -Properties $volPoller | Out-Null 
             } 
         } 
        }
     # If the Node was in NCM, add the new node to NCM 
     $IsNodeInNCM = $false
     $IsNodeInNCM = Get-SwisData -SwisConnection $source -Query "SELECT CoreNodeID from NCM.NODES where CoreNodeID = @NodeID" @{NodeID = $sourceNode.NodeID}    
    if($IsNodeInNCM){
        Invoke-SwisVerb $target Cirrus.Nodes AddNodeToNCM $newNode.NodeID 
    }  
      
 }

## WMI Nodes - Credentials can't be copied as of current knowledge, so relying on the 
$sourceNodesWMI = Get-SwisData $source "SELECT Uri, IPAddress, Caption, NodeID, ObjectSubType FROM Orion.Nodes where ObjectSubType = 'WMI'" 
foreach ($sourceNode in $sourceNodesWMI) { 
    Start-Sleep -Milliseconds 500
    # See if there is aleady a node on the target with the same IP address 
    $targetNodeUri = Get-SwisData $target "SELECT Uri FROM Orion.Nodes WHERE IPAddress=@ip" @{ip=$sourceNode.IPAddress} 

    if ($null -ne $targetNodeUri) { 
        Write-Host "Skipping" $sourceNode.Caption "(" $sourceNode.IPAddress ") because it is already managed " 
        continue 
    } 


    # Fetch all properties of the source node 
    $sourceNodeProps = Get-SwisData $source "SELECT AgentPort, Allow64BitCounters, BufferBgMissThisHour, BufferBgMissToday, BufferHgMissThisHour, BufferHgMissToday, BufferLgMissThisHour, 
        BufferLgMissToday, BufferMdMissThisHour, BufferMdMissToday, BufferNoMemThisHour, BufferNoMemToday, BufferSmMissThisHour, BufferSmMissToday, 
        Caption, ChildStatus, CMTS, Community, Contact, DNS, DynamicIP, External, EntityType, GroupStatus, IOSImage, IOSVersion, IPAddress, IPAddressGUID, 
        IPAddressType, LastSystemUpTimePollUtc, Location, MachineType, NodeDescription, ObjectSubType, PollInterval, RediscoveryInterval, Severity, SNMPVersion, 
        StatCollection, Status, StatusDescription, StatusLED, SysName, SysObjectID, TotalMemory, Vendor, VendorIcon, RWCommunity         
         From Orion.Nodes Where NodeID = @nodeid" @{nodeid=$sourceNode.Nodeid}

    # Fetch all custom properties    
    # Build the Select String from CP Bucket
    $NodeCustomPropsToCopy = $NodesCustomProperties.TrimStart('"(')
    $NodeCustomPropsToCopy = $NodeCustomPropsToCopy.TrimEnd(')"')
    $DummyNodeID = $sourceNode.Nodeid
    $Query = ''
    $query = "SELECT "+$NodeCustomPropsToCopy+" from Orion.NodesCustomProperties where NodeID = $DummyNodeID"
    $sourceNodeCPs = Get-SwisData -SwisConnection $source -Query $Query
         # Make an in-memory copy of the node 
     #Write-Host "Copying" $sourceNode.Caption "(" $sourceNode.IPAddress ")" 
     $targetNodeProps = @{} 
     $nodePropsToCopy | %{ $targetNodeProps[$_] = $sourceNodeProps.$_ } 
     $targetNodeProps["EngineID"] = SelectTargetEngineID -PollingMethod $SourceNode.ObjectSubType -SwisConn $target
     if(!$targetNodeProps["DNS"]){
        $targetNodeProps["DNS"] = 'DNS'
     }
     
     # In-Memory copy of Customproperties
     $targetNodeCPs = @{}
     $sourceNodeCPs.psobject.Properties | Foreach-Object{ $targetNodeCPs[$_.Name] = $_.Value}    

     # Create the node on the target system 
     $newUri = New-SwisObject $target -EntityType "Orion.Nodes" -Properties $targetNodeProps 
     $newNode = Get-SwisObject $target $newUri 

          # Associate the custom property "MigratedByAPI" with this node and set its value to "true" 
          Set-SwisObject $target ($newUri+"/CustomProperties") @{ "MigratedByAPI"="true" }
          try{
          Set-SwisObject $target ($newUri+"/CustomProperties") $targetNodeCPs
          }
          catch{
          write-Host "Unable to set Custom Props for" $newNode.NodeName
          }

     #Adding Windows Credentials as NodeSettings 
     # Set WMI Credentials for the Node
     $WMICredentialID = GetDestinationWMISettingID -NodeID $sourceNode.NodeID
     $nodeSettings = @{ 
        NodeID = $newNode["NodeID"] 
        SettingName = "WMICredential" 
        SettingValue = $WMICredentialID
       } 
  
  #Creating node settings 
  New-SwisObject $target -EntityType "Orion.NodeSettings" -Properties $nodeSettings 

  # Copy the pollers for the new node 
  $pollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject='N:' + $sourceNode.NodeID } 
      
  foreach ($pollerType in $pollerTypes) { 
      $poller = @{ 
          PollerType = "$pollerType"; 
          NetObject = "N:" + $newNode.NodeID; 
          NetObjectType = "N"; 
          NetObjectID = $newNode.NodeID; 
      } 
      Write-Host "    Adding poller $pollerType" 
      New-SwisObject $target -EntityType "Orion.Pollers" -Properties $poller | Out-Null 
  } 
   # Get the interfaces on the source node
    $sourceInterfaces = ''
    $sourceInterfaces = Get-SwisData $source "SELECT Nodes.Interfaces.Uri, Nodes.Interfaces.InterfaceID FROM Orion.Nodes WHERE NodeID=@node" @{ node=$sourceNode.NodeID } 
    if($sourceinterfaces.Length -eq 0){
    # do nothing for Interfaces, because source does  not have interfaces  
    }
    else{
    foreach ($sourceInterface in $sourceInterfaces) { 
        if (IsEmpty $sourceInterface.URI) { 
            continue 
        } 

    $sourceIfProps = Get-SwisObject $source $sourceInterface.uri
    if($sourceIfProps.HasObsoleteData -eq 1 -or $sourceIfProps.length -eq 0){
        #do nothing
    }
    else{
        # Build the Select String from CP Bucket
    $InterfaceCustomPropsToCopy = $InterfaceCustomProperties.Trim('"()')
    #$InterfaceCustomPropsToCopy = $InterfaceCustomPropsToCopy.TrimEnd(')"')
    $InterfaceID = $sourceInterface.InterfaceID
    $InterfaceURI = $sourceInterface.Uri
    $Query = ''
    $Query = "SELECT "+$InterfaceCustomPropsToCopy+" FROM Orion.NPM.InterfacesCustomProperties where InterfaceID = $InterfaceID"
    $sourceIFCPs = @{}
    $sourceIFCPs = Get-SwisData -SwisConnection $source -Query $Query
    

        Write-Host "  Copying" $sourceNode.Caption "/" $sourceIfProps.Caption 
        $targetIfProps = @{} 
        $interfacePropsToCopy | %{ $targetIfProps[$_] = $sourceIfProps[$_] } 
        $targetIfProps["NodeID"] = $newNode.NodeID 
    
        # In-Memory copy of Interface Customproperties
    $targetIFCPs = @{}
    $sourceIFCPs.psobject.Properties | Foreach-Object{ $targetIFCPs[$_.Name] = $_.Value}     

        # Create the copy 
        $newIfUri = New-SwisObject $target -EntityType "Orion.NPM.Interfaces" -Properties $targetIfProps 
        $newIf = Get-SwisObject $target $newIfUri 

        # Set the Custom Properties                      
        Set-SwisObject $target ($newIfUri+"/CustomProperties") $targetIFCPs
        # Copy the pollers for the new interface 
        $ifPollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject = 'I:'+$sourceIfProps.InterfaceID } 

        foreach ($ifPollerType in $ifPollerTypes) { 
            $ifPoller = @{ 
                PollerType = "$ifPollerType"; 
                NetObject = "I:" + $newIf.InterfaceID; 
                NetObjectType = "I"; 
                NetObjectID = $newIf.InterfaceID; 
            } 
            Write-Host "      Adding poller $ifPollerType" 
            New-SwisObject $target -EntityType "Orion.Pollers" -Properties $ifPoller | Out-Null 
        } 
    }
    } 
    }
          
     # Get the volumes on the source node
     $sourceVolumes = ''      
     $sourceVolumes = Get-SwisData $source "SELECT Nodes.Volumes.Uri, Nodes.volumes.VolumeID FROM Orion.Nodes WHERE NodeID=@node" @{ node = $sourceNode.NodeID } 
        if($sourceVolumes.length -eq 0){
            # do nothing on volumes because source does not have volumes
        }
        else{
         foreach ($sourceVolume in $sourceVolumes) { 
             if (IsEmpty($sourceVolume.VolumeID)) { 
                 continue 
             } 
 

             $sourceVolProps = Get-SwisObject $source $sourceVolume.uri 
             Write-Host "  Copying" $sourceNode.Caption "/" $sourceVolProps.Caption 
             $targetVolProps = @{} 
             $volumePropsToCopy | %{ $targetVolProps[$_] = $sourceVolProps[$_] } 
             $targetVolProps["NodeID"] = $newNode.NodeID 
 

            # Build the Select String from CP Bucket
            if($VolumeCustomProperties){
                $VolumeCustomPropsToCopy = $VolumeCustomProperties.Trim('"()')
                $VolumeID = $sourceVolume.VolumeID            
                $Query = ''
                $Query = "SELECT "+$VolumeCustomPropsToCopy+" FROM Orion.VolumesCustomProperties where VolumeID = $VolumeID"
                $sourceVolumeCPs = @{}
                $sourceVolumeCPs = Get-SwisData -SwisConnection $source -Query $Query
                # In-Memory copy of Volume Customproperties                
                $targetVolumeCPs = @{}
                $sourceVolumeCPs.psobject.Properties | Foreach-Object{ $targetVolumeCPs[$_.Name] = $_.Value}    
            }
            
            # Create the copy 
            $newVolUri = New-SwisObject $target -EntityType "Orion.Volumes" -Properties $targetVolProps 
            $newVol = Get-SwisObject $target $newVolUri 
 
            # Set the Custom Properties if Volume has Properties
            if($null -ne $targetVolumeCPs){                                              
            Set-SwisObject $target ($newVolUri+"/CustomProperties") $targetVolumeCPs
            }
            # Copy the pollers for the new Volume 
            $volPollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{ netobject='V:' + $sourceVolProps.VolumeID } 
      
             foreach ($volPollerType in $volPollerTypes) { 
                 $volPoller = @{ 
                     PollerType = "$volPollerType"; 
                     NetObject = "V:"+$newVol.VolumeID; 
                     NetObjectType = "V"; 
                     NetObjectID = $newVol.VolumeID; 
                 } 
                 Write-Host "      Adding poller $volPollerType" 
                 New-SwisObject $target -EntityType "Orion.Pollers" -Properties $volPoller | Out-Null 
             } 
         } 
        }
     # If the Node was in NCM, add the new node to NCM 
     $IsNodeInNCM = $false
     $IsNodeInNCM = Get-SwisData -SwisConnection $source -Query "SELECT CoreNodeID from NCM.NODES where CoreNodeID = @NodeID" @{NodeID = $sourceNode.NodeID}    
    if($IsNodeInNCM){
        Invoke-SwisVerb $target Cirrus.Nodes AddNodeToNCM $newNode.NodeID 
    }  

}


## Create Groups ##
## Get All Groups ##
try{
    $AllGroups = Get-SwisData $source "SELECT Uri FROM Orion.groups" -ErrorAction Stop
}
catch{
    write-Host "getting Groups failed"
}
## End Get All Groups

<## Analyze all Groups ##
foreach($Group in $AllGroups){
    
    #Get Group Definitions
    $GroupProperties = Get-SwisObject $source $Group
    #Does the Group Already Exist
    $DoesGroupAlreadyExist =  Get-SwisData $target "SELECT ContainerID FROM Orion.Container where Name =@NewName" @{NewName=$GroupProperties.Name}
    if($DoesGroupAlreadyExist){
    continue
    }
    #Read the Member Definitions - We only need the Name and the Definition
    $MemberDefinitions = Get-SwisData $source "SELECT Name, Definition, Entity FROM Orion.ContainerMemberDefinition WHERE ContainerID=@ID" @{ID=$GroupProperties.ContainerID}
    $MemberDefinitionsHelper = RewriteContainerMembersTable -MemberTable $MemberDefinitions -source $source -target $target
    $MemberDefinitions = $MemberDefinitionsHelper

    #Check if Group has Parent Group -> different SWIS Verb for creating the group
    $Searchstring='Orion.Groups.ContainerID='+$GroupProperties.ContainerID.ToString()
    $Query= "SELECT ContainerID FROM Orion.ContainerMemberDefinition where Name like '%$Searchstring%'" 
    $HasParent = Get-SwisData -Swis $source -query $Query
    ## if parent group has other members, create it with members ##
    $NumberOfMembers = $MemberDefinitions.Count
    if($Hasparent){        
        $ParentSourceName = Get-SwisData $source "SELECT Name FROM Orion.Container where ContainerID =@Parent" @{Parent=$HasParent[0]}
        $DoesParentAlreadyExist = Get-SwisData $target "SELECT ContainerID FROM Orion.Container where Name =@ParentSourceName" @{ParentSourceName=$ParentSourceName}
         #Set Properties for the new Group that are Generic for Parent Groups and Groups with parents	    
        $GroupName = $($GroupProperties.Name)
	    $GroupOwner = $($GroupProperties.Owner)
	    $GroupFrequency = $($GroupProperties.Frequency)
	    $GroupStatusCalculator = $($GroupProperties.StatusCalculator)
	    $GroupDescription = $($GroupProperties.Description)
	    $GroupPollingEnabled = $($GroupProperties.PollingEnabled) 
        if ($DoesParentAlreadyExist -and $HasParent -and ($NumberOfMembers -ne 0)){
        $groupId = (Invoke-SwisVerb $target "Orion.Container" "CreateContainerwithParent" @(
        #ParentID
        $DoesParentAlreadyExist
        # group name
        $GroupName,
        # owner, must be 'Core'
        $GroupOwner,
        # refresh frequency
        $GroupFrequency,
        # Status rollup mode:
        # 0 = Mixed status shows warning
        # 1 = Show worst status
        # 2 = Show best status
        $GroupStatuscalculator,
        # group description
        $GroupDescription,
        # polling enabled/disabled = true/false (in lowercase)
        $GroupPollingenabled,
        # group members
        ([xml]@(
           "<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
           [string]($MemberDefinitions |% {
             "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
             }
           ),
           "</ArrayOfMemberDefinitionInfo>"
            )).DocumentElement
        )).InnerText
             ## group is created, continue with next group##
            continue
        
        }
    ## Subgroup is empty, so create empty group ##
        else {
            $groupId = (Invoke-SwisVerb $target "Orion.Container" "CreateContainerwithParent" @(
            #ParentID
            $DoesParentAlreadyExist
            # group name
            $GroupName,
            # owner, must be 'Core'
            $GroupOwner,
            # refresh frequency
            $GroupFrequency,
            # Status rollup mode:
            # 0 = Mixed status shows warning
            # 1 = Show worst status
            # 2 = Show best status
            $GroupStatuscalculator,
            # group description
            $GroupDescription,
            # polling enabled/disabled = true/false (in lowercase)
            $GroupPollingenabled,
            # group members
            ([xml]"<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion' />").DocumentElement
            )).InnerText
    
            ## group is created, continue with next group##
            continue
            }
            
    }

    ## if parent group has No members, create an empty Group ##
    if($NumberOfMembers -eq 0){
        #Set Properties for the new Group that are Generic for Parent Groups and Groups with parents	    
        $GroupName = $($GroupProperties.Name)
	    $GroupOwner = $($GroupProperties.Owner)
	    $GroupFrequency = $($GroupProperties.Frequency)
	    $GroupStatusCalculator = $($GroupProperties.StatusCalculator)
	    $GroupDescription = $($GroupProperties.Description)
	    $GroupPollingEnabled = $($GroupProperties.PollingEnabled)
        
        # Create the Group
        $groupId = (Invoke-SwisVerb $target "Orion.Container" "CreateContainer" @(
        # group name
        $GroupName,
        # owner, must be 'Core'
        $GroupOwner,
        # refresh frequency
        $GroupFrequency,
        # Status rollup mode:
        # 0 = Mixed status shows warning
        # 1 = Show worst status
        # 2 = Show best status
        $GroupStatuscalculator,
        # group description
        $GroupDescription,
        # polling enabled/disabled = true/false (in lowercase)
        $GroupPollingenabled,
        # group members
        ([xml]"<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion' />").DocumentElement
                                                                                    )
        
        ) 
        ## group is created, continue with next group##
        continue      
    }    
    ## Group has additional entries and a subgroup  create the group with just the non group entities##
    else{
        #Set Properties for the new Group that are Generic for Parent Groups and Groups with parents	    
        $GroupName = $($GroupProperties.Name)
        $GroupOwner = $($GroupProperties.Owner)
        $GroupFrequency = $($GroupProperties.Frequency)
        $GroupStatusCalculator = $($GroupProperties.StatusCalculator)
        $GroupDescription = $($GroupProperties.Description)
        $GroupPollingEnabled = $($GroupProperties.PollingEnabled)
        
        # Create the Group
        $groupId = (Invoke-SwisVerb $target "Orion.Container" "CreateContainer" @(
        # group name
        $GroupName,
        # owner, must be 'Core'
        $GroupOwner,
        # refresh frequency
        $GroupFrequency,
        # Status rollup mode:
        # 0 = Mixed status shows warning
        # 1 = Show worst status
        # 2 = Show best status
        $GroupStatuscalculator,
        # group description
        $GroupDescription,
        # polling enabled/disabled = true/false (in lowercase)
        $GroupPollingenabled,
        # group members
        ([xml]@(
           "<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
           [string]($MemberDefinitions |% {
             "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
             }
           ),
           "</ArrayOfMemberDefinitionInfo>"
            )).DocumentElement
        )).InnerText

        ## group is created, continue with next group##
        continue
    }

      
}
# END Script #>