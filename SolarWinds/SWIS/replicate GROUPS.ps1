Import-Module SwisPowerShell

$SourceServer = "HOSTANME"
$DestinationServer = "HOSTANME"

# Get Credentials to Log on to servers
$sourcecred= Get-Credential -Message "Enter Credentials for Source Server"
$destcred= Get-Credential -Message "Enter Credentials for Destination Server"

# create the connection to both source and destination SolarWinds servers
$swissource = Connect-Swis -Hostname $SourceServer -Credential  $sourcecred
$swisdest = Connect-Swis -Hostname $DestinationServer -Credential  $destcred
#$swissource = Connect-Swis -Hostname $SourceServer -Trusted
#$swisdest = Connect-Swis -Hostname $DestinationServer -Trusted

$AllGroups = Get-SwisData -SwisConnection $swissource -Query "SELECT ContainerID, Name, Description, Owner, Frequency, StatusCalculator, RollupType, IsDeleted, PollingEnabled, LastChanged, UnManageFrom, UnManageUntil, DetailsUrl FROM Orion.Container"
$Groups = Get-SwisData -SwisConnection $swissource -Query "SELECT ContainerID, Name, Description, Owner, Frequency, StatusCalculator, RollupType, IsDeleted, PollingEnabled, LastChanged, UnManageFrom, UnManageUntil, DetailsUrl FROM Orion.Container WHERE ContainerID IN (SELECT ContainerID FROM Orion.ContainerMemberDefinition WHERE Entity = 'Orion.Groups')"
$GroupDefinitions = Get-SwisData -SwisConnection $swissource -Query "Select DefinitionID, ContainerID, Name, Entity, FromClause, Expression, Definition FROM Orion.ContainerMemberDefinition WHERE ContainerID IN (SELECT ContainerID FROM Orion.Container WHERE ContainerID IN (SELECT ContainerID FROM Orion.ContainerMemberDefinition WHERE Entity = 'Orion.Groups'))"

$URL = Get-SwisData -SwisConnection $swisdest -Query 'SELECT SettingValue FROM Orion.WebSettings WHERE SettingName=''SwisUriSystemIdentifier'''
foreach ($Group in $Groups) {
    $members = @()
    $GroupDefinitionsThisGroup = $GroupDefinitions | Where {$_.ContainerID -eq $($Group).ContainerID}
    $GroupName = $Group | Select -ExpandProperty Name
    Write-Host "Creating group $GroupName" -ForegroundColor Green
    if (@($GroupDefinitionsThisGroup).Count -ge 1) {
        foreach ($GroupDefinitionThisGroup in $GroupDefinitionsThisGroup) {
            if ($($GroupDefinitionThisGroup).Definition -like "filter:*") {
                $DefinitionName = $GroupDefinitionThisGroup | Select -ExpandProperty Name
                $Definition = $GroupDefinitionThisGroup | Select -ExpandProperty Definition
                $Members += @{ Name = $DefinitionName; Definition = $Definition }
                Write-Host "     Adding $Definition to $GroupName" -ForegroundColor Yellow
            } 
            elseif (($($GroupDefinitionThisGroup).Definition -like "swis:*") -and ($($GroupDefinitionThisGroup).Entity -eq "Orion.Nodes")) {
                $Expression = $GroupDefinitionThisGroup | select -ExpandProperty Expression
                if ($Expression -like "Nodes.Uri=*") {
                    $NodeID = $Expression.Split("=")[2]
                    $NodeID = $NodeID.Replace("`'","")
                } else {
                    $NodeID = $Expression.Split("=")[1]
                }
                $NodeInfoQuery = 'Select Caption, IPAddress from Orion.Nodes where NodeID = ''' + $NodeID + ''''
                $NodeInfo = Get-SwisData -SwisConnection $swissource -Query $NodeInfoQuery -ErrorAction Continue
                if ($NodeInfo) {
                    $NodeCaption = $NodeInfo | Select -ExpandProperty Caption
                    $IP = $NodeInfo | Select -ExpandProperty IPAddress 
                    $DestinationNodeQuery = 'Select NodeID, Caption from Orion.Nodes where IPAddress = ''' + $IP + ''''
                    $NodeInDestination = Get-SwisData -SwisConnection $swisdest -Query $DestinationNodeQuery -ErrorAction SilentlyContinue
                    if ($NodeInDestination) {
                        $NodeID = $NodeInDestination | Select -ExpandProperty NodeID
                        $Expression = 'Nodes.NodeID=' + $NodeID
                        $Definition = 'swis://' + $URL + '/Orion/Orion.Nodes/NodeID=' + $NodeID
                        $Members += @{ Name = "Orion.Nodes Nodes"; Definition = $Definition }
                        Write-Host "    Adding $NodeCaption to $GroupName" -ForegroundColor Green
                    } else {
                        Write-Host "    $IP does not exist on the destination server" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "     $NodeCaption does not have an IP address in the source server" -ForegroundColor Red
                }
            } elseif (($($GroupDefinitionThisGroup).Definition -like "swis:*") -and ($($GroupDefinitionThisGroup).Entity -eq "Orion.NPM.Interfaces")) {
                $InterfaceID = $($GroupDefinitionThisGroup).Expression.Split("=")[3]
                $InterfaceID = $InterfaceID.Replace("`'","")
                $SourceInterfaceIndexQuery = 'SELECT InterfaceIndex FROM Orion.NPM.Interfaces WHERE InterfaceID = ''' + $InterfaceID + ''''
                $SourceInterfaceIndex = Get-SwisData -SwisConnection $swissource -Query $SourceInterfaceIndexQuery -ErrorAction Continue
                #$SourceInterfaceMacQuery = "SELECT MAC FROM Orion.NPM.Interfaces WHERE InterfaceID=`'$InterfaceID`'"
                #$SourceInterfaceMac = Get-SwisData -SwisConnection $swissource -Query $SourceInterfaceMacQuery -ErrorAction Continue
                $SourceInterfaceNodeQuery = "SELECT i.Node.IP_Address FROM Orion.NPM.Interfaces i WHERE InterfaceID=`'$InterfaceID`'"
                $SourceInterfaceNode = Get-SwisData -SwisConnection $swissource -Query $SourceInterfaceNodeQuery -ErrorAction Continue
                if ($SourceInterface) {
                    $DestinationNodeQuery = 'Select NodeID from Orion.Nodes where IPAddress = ''' + $SourceInterfaceNode + ''''
                    $DestinationNodeID = Get-SwisData -SwisConnection $swisdest -Query $DestinationNodeQuery -ErrorAction SilentlyContinue
                    #$DestinationInterfaceQuery = "SELECT FullName, InterfaceID, NodeID FROM Orion.NPM.Interfaces WHERE MAC=`'$SourceInterfaceMac`' AND InterfaceIndex=`'$SourceInterfaceIndex`' AND NodeID=`'$DestinationNodeID`'"
                    $DestinationInterfaceQuery = "SELECT FullName, InterfaceID, NodeID FROM Orion.NPM.Interfaces WHERE InterfaceIndex=`'$SourceInterfaceIndex`' AND NodeID=`'$DestinationNodeID`'"
                    $DestinationInterface = Get-SwisData -SwisConnection $swisdest -Query $DestinationInterfaceQuery -ErrorAction SilentlyContinue
                    $NewInterfaceID = $DestinationInterface | Select -ExpandProperty InterfaceID
                    $NewInterfaceName = $DestinationInterface | Select -ExpandProperty FullName
                    $NewNodeID = $DestinationInterface | Select -ExpandProperty NodeID
                    if ($NewInterfaceID) {
                            $Definition = 'swis://' + $URL + '/Orion/Orion.Nodes/NodeID=' + $NewNodeID + '/Interfaces/InterfaceID=' + $NewInterfaceID
                            $InterfaceName = 'Orion.Nodes.NodeID=' + $NewNodeID + ' Interfaces.InterfaceID=' + $NewInterfaceID
                            $Members += @{ Name = $InterfaceName; Definition = $Definition }
                            Write-Host "    Adding Interface $NewInterfaceName to $GroupName" -ForegroundColor Green
                    } else {
                        Write-Host "     Interface with MAC $SourceInterfaceMac does not exist in the new system" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "     Cannot find the $InterfaceID interface on the old system" -ForegroundColor Red
                }
            }
        }
    }
    $groupId = (Invoke-SwisVerb $swisdest "Orion.Container" "CreateContainer" @(
        # group name
        $($Group).Name,

        # owner, must be 'Core'
        "Core",

        # refresh frequency
        $($Group).Frequency,

        # Status rollup mode:
        # 0 = Mixed status shows warning
        # 1 = Show worst status
        # 2 = Show best status
        $($Group).StatusCalculator,

        # group description
        $($Group).Description,

        # polling enabled/disabled = true/false (in lowercase)
        "true",""
        # group members
        ([xml]@(
            "<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
            [string]($members |% {
                "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
                }
            ),
            "</ArrayOfMemberDefinitionInfo>"
        )).DocumentElement
        )).InnerText        
    if ($GroupID -and $Members) {
        Invoke-SwisVerb $swisdest "Orion.Container" "AddDefinitions" @(
            # group ID
            $groupId,

            # group member to add
            ([xml]@(
                "<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
                [string]($members |% {
                    "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
                    }
                ),
                "</ArrayOfMemberDefinitionInfo>"
            )).DocumentElement
            ) | Out-Null  
    }
}

$SubGroups = $GroupDefinitions | where Entity -eq "Orion.Groups"


if ($SubGroups.Count -ge 1) {
    foreach ($SubGroup in $SubGroups) {
        $members = @()
        $OldDefinition = $SubGroup | Select -ExpandProperty Definition
        $OldSubGroupID = $OldDefinition.Split("=")[1]
        $SourceParentGroup = $Groups | where ContainerID -eq $($SubGroup.ContainerID) | Select -ExpandProperty Name
        $SourceSubGroup = $AllGroups | where ContainerID -eq $OldSubGroupID | Select -ExpandProperty Name
        if ($SubGroup.DefinitionID -lt 18463) {continue}
        #if ($SourceSubGroup -eq "USTLH300(TALLAHASSEE)" -or $SourceSubGroup -eq "[CAQUE900] - Quebec (1000 route de l'Église)" -or $SourceSubGroup -eq "[CAYVO100] - Val-d'or (Avenue Est)" -or $SourceSubGroup -eq "[GBLHR100] - Heathrow (D'Albiac House)" -or $SourceSubGroup -eq "[CABAR300] - Barrie (Commerce Park Drive)" -or $SourceSubGroup -eq "[CASJF200] - St Johns (11 Austin St)" -or $SourceSubGroup -eq "[CAWND200] - Windsor (Provincial Road)") {continue}
        $GroupID = Get-SwisData -SwisConnection $swisdest -Query "Select ContainerID FROM Orion.Container WHERE Name=`'$SourceParentGroup`'" -ErrorAction SilentlyContinue
        $TargetSubGroup = Get-SwisData -SwisConnection $swisdest -Query "Select ContainerID FROM Orion.Container WHERE Name=`'$SourceSubGroup`'" -ErrorAction SilentlyContinue
        $Definition = 'swis://' + $URL + '/Orion/Orion.Groups/ContainerID=' + $TargetSubGroup
        $SubGroupName = 'Orion.Groups.ContainerID=' + $TargetSubGroup
        $Members += @{ Name = $SubGroupName; Definition = $Definition }

        if ($GroupID -and $Members) {
            Write-Host "Adding $SourceSubGroup to $SourceParentGroup (DefinitionID = $($SubGroup.DefinitionID)" -ForegroundColor Green
            Invoke-SwisVerb $swisdest "Orion.Container" "AddDefinitions" @(
                # group ID
                $groupId,

                # group member to add
                ([xml]@(
                    "<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
                    [string]($members |% {
                        "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
                        }
                    ),
                    "</ArrayOfMemberDefinitionInfo>"
                )).DocumentElement
                ) | Out-Null  
        } else {
            Write-Host "Something went wrong trying to add the $SourceSubGroup to the $SourceParentGroup group" -ForegroundColor DarkYellow
        }
    }
}

