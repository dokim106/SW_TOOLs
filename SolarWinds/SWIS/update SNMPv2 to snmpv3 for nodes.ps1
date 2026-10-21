$ErrorActionPreference = 'Stop'

if (!(Get-InstalledModule | where {$_.Name -EQ "SwisPowerShell"}))
    { Import-Module SwisPowerShell}

$swis = Connect-Swis -Hostname "<SolarWinds server>" -Credential (Get-Credential)

$query="
SELECT top 1000
n.caption as [Node]
,n.ip_address as [ip_address]
,n.uri as [uri]
from orion.nodes n
where n.vendor='net-snmp'
and n.Status =1
and n.SNMPVersion='2'
--and n.ip_address like '10.xx.xx.xx'
"

$nodes = Get-SwisData -SwisConnection $swis -Query $query

$properties = @{
    SNMPVersion      = '3' ;
    SNMPV3Context    = '';
    SNMPV3Username   = 'sw-mon';
    SNMPV3PrivMethod = 'AES128'; # None, DES56, AES128, AES192, AES256
    SNMPV3PrivKey    = 'xxxxx'
    SNMPV3PrivKeyIsPwd = $TRUE;
    SNMPV3AuthMethod = 'SHA1' #None, MD5, SHA1
    SNMPV3AuthKey    = 'xxxxx'
    SNMPV3AuthKeyIsPwd = $TRUE;

}

$count=0
foreach ($node in $nodes) {
  Write-Output "SNMPv3: Node: $($node.node)   $($node.IP_address)"
  Set-SwisObject $swis $($node.uri) $properties
  $count++
  sleep -Milliseconds 400
   }
write-host "Total NODES  " $count
