# Azure vWAN Demos

## vWAN with vhub-spoke-spoke 

TODO: .
- Did convert hub1 into secure hub via portal. Do it via CLI.

### Overview
Setup vWAN with two vHub´s in different azure regions:

~~~mermaid
classDiagram
  class fw {
    -CIDR : 10.5.0.0/16
    -Location: westeurope
  }
  class vWANHub1 {
    -CIDR : 10.0.0.0/16
    -Location: westeurope
    -Secure: FALSE
  }
    class Spoke1{
    -CIDR : 10.1.0.0/16
    -Location: westeurope
  }
    class SpokeBastion1{
    -CIDR : 10.2.0.0/16
    -Location: westeurope
  }
    class vWANHub2 {
    -CIDR : 10.3.0.0/16
    -Location: eastus
    -Secure: FALSE
  }
  class Spoke2{
    -CIDR : 10.4.0.0/16
    -Location: eastus
  }
  vWANHub1 -- vWANHub2 : vwan-peering
  vWANHub1 -- Spoke1 : vwan-peering
  vWANHub2 -- Spoke2: vwan-peering
  SpokeBastion1 -- vWANHub1 : vwan-peering
  fw -- Spoke1: vnet-peering
  fw -- Spoke2: vnet-peering
~~~

### Create needed env variables

~~~ bash
sudo chmod 600 azbicep/ssh/chpinoto.key # to avoid ssh issues
prefix=cptdazvwan
location1=westeurope
location2=eastus
subid=$(az account show --query id -o tsv)
myip=$(curl ifconfig.io) # Just in case we like to whitelist our own ip.
myobjectid=$(az ad user list --query '[?displayName==`ga`].id' -o tsv) # just in case we like to assing
~~~ 

### Create azure resources and connections

~~~ bash
az group delete -n $prefix --yes
az group create -n $prefix -l $location1
az deployment group create -n $prefix -g $prefix --mode incremental --template-file deploy.bicep -p prefix=$prefix myobjectid=$myobjectid location1=$location1 location2=$location2 myip=$myip
# Establish vwan connections in a seperate step
az deployment group create -n $prefix -g $prefix --mode incremental --template-file vwanconnections.bicep -p prefix=$prefix
# Establish direct vnet connections between vwan spokes with the fw vnet.
az deployment group create -n $prefix -g $prefix --mode incremental --template-file vnetconnections.bicep -p prefix=$prefix
~~~

### Show effective routes from vm nic in spoke1:

~~~bash
spoke1nicid=$(az network nic show -n ${prefix}spoke1 -g $prefix --query id -o tsv)
az network nic show-effective-route-table --ids $spoke1nicid -o table | grep -wv None
~~~

Output nic of spoke1 vm:
~~~text
Source                 State    Address Prefix    Next Hop Type          Next Hop IP
---------------------  -------  ----------------  ---------------------  -------------
Default                Active   10.1.0.0/16       VnetLocal
Default                Active   10.0.0.0/16       VNetPeering
VirtualNetworkGateway  Active   10.2.0.0/16       VirtualNetworkGateway  20.76.216.14
VirtualNetworkGateway  Active   10.4.0.0/16       VirtualNetworkGateway  20.76.216.14
Default                Active   0.0.0.0/0         Internet
Default                Active   10.5.0.0/16       VNetGlobalPeering
~~~

NOTES: 
- Peering with spoke2 vnet (10.4.0.0/16) and bastion vnet (10.2.0.0/16) via vwan hub is achieved via VirtualNetworkGateway.
- IP range of hub2 (10.3.0.0/16) does not show up.
- Peering with fw vnet (10.5.0.0/16) does show a seprate route.


### Show effective routes from vm nic in fw vnet:

~~~bash
fwnicid=$(az network nic show -n ${prefix}fw -g $prefix --query id -o tsv)
az network nic show-effective-route-table --ids $fwnicid -o table | grep -wv None
~~~

Output nic of spoke1 vm:
~~~text
Source    State    Address Prefix    Next Hop Type      Next Hop IP
--------  -------  ----------------  -----------------  -------------
Default   Active   10.5.0.0/16       VnetLocal
Default   Active   10.4.0.0/16       VNetPeering
Default   Active   0.0.0.0/0         Internet
Default   Active   10.1.0.0/16       VNetGlobalPeering
~~~

NOTES: 
- Peering with spoke2 vnet (10.4.0.0/16) via vnet peering.
- Peering with spoke1 (10.1.0.0/16) via global vnet peering.

### Effective routes from vWAN

Get the route table configured for the Virtual Hub1:

~~~ bash
hub1rtid=$(az network vhub route-table list -g $prefix --vhub-name ${prefix}hub1 --query "[?labels[0]=='default'].id" -o tsv)
subid=$(az account show --query id -o tsv)
az network vhub get-effective-routes --resource-type RouteTable -g $prefix -n ${prefix}hub1 --resource-id $hub1rtid --query 'value[].{Prefix:addressPrefixes[0],ASPath:asPath,NextHopType:nextHopType,NextHop:nextHops[0],Origin:routeOrigin}' | awk '{ gsub(/\/subscriptions\/'$subid'\/resourceGroups\/'$prefix'\/providers\/Microsoft.Network\//,""); gsub("virtualHubs","vhub");gsub("hubVirtualNetworkConnections","vhubcon"); print }'
~~~

Output hub1 route table:

~~~json
[
  {
    "ASPath": null,
    "NextHop": "vhub/cptdazvwanhub1/vhubcon/hub1tospoke1",
    "NextHopType": "Virtual Network Connection",
    "Origin": "vhub/cptdazvwanhub1/vhubcon/hub1tospoke1",
    "Prefix": "10.1.0.0/16"
  },
  {
    "ASPath": null,
    "NextHop": "vhub/cptdazvwanhub1/vhubcon/hub1tospoke1bastion",
    "NextHopType": "Virtual Network Connection",
    "Origin": "vhub/cptdazvwanhub1/vhubcon/hub1tospoke1bastion",
    "Prefix": "10.2.0.0/16"
  },
  {
    "ASPath": "65520-65520",
    "NextHop": "vhub/cptdazvwanhub2",
    "NextHopType": "Remote Hub",
    "Origin": "vhub/cptdazvwanhub2",
    "Prefix": "10.4.0.0/16"
  }
]
~~~

NOTE: 
Routing to fw vnet (10.5.0.0/16) is not mentioned by vwan.



-------------------------------------------------------------------------

### Create a new static route inside 

~~~ bash
az network vhub route-table route list -n defaultRouteTable -g $prefix --vhub-name ${prefix}hub1 
hub1conid=$(az network vhub connection show -n hub1tospoke1 -g $prefix --vhub-name ${prefix}hub1 --query id -o tsv)
-n hub1tospoke1
az network vhub route-table route add --destination-type CIDR --destinations 10.1.0.4/32 -n defaultRouteTable --next-hop-type ResourceId --next-hop $hub1conid --route-name bypass-fw -g $prefix --vhub-name ${prefix}hub1
az network vhub connection show -n hub1tospoke1 -g $prefix --vhub-name ${prefix}hub1 --query routingConfiguration.vnetRoutes | awk '{ gsub(/\/subscriptions\/'$subid'\/resourceGroups\/'$prefix'\/providers\/Microsoft.Network\//,""); gsub("virtualHubs","vhub");gsub("hubVirtualNetworkConnections","vhubcon"); print }'
az network vhub route-table route remove --index 3 -n defaultRouteTable -g $prefix --vhub-name ${prefix}hub1
~~~

### Show static route details
This will also include the next hop information.

~~~ bash
az network vhub connection list -g $prefix --vhub-name ${prefix}hub1
az network vhub connection show -n hub1tospoke1 -g $prefix --vhub-name ${prefix}hub1 --query routingConfiguration.vnetRoutes | awk '{ gsub(/\/subscriptions\/'$subid'\/resourceGroups\/'$prefix'\/providers\/Microsoft.Network\//,""); gsub("virtualHubs","vhub");gsub("hubVirtualNetworkConnections","vhubcon"); print }'
~~~




Get the effective routes configured for the Virtual Hub1 vnet connection:

~~~ bash
hub1conid=$(az network vhub connection list -g $prefix --vhub-name ${prefix}hub1 --query [0].id -o tsv)
az network vhub get-effective-routes --resource-type HubVirtualNetworkConnection -g $prefix -n ${prefix}hub1 --resource-id $hub1conid --query 'value[].{Prefix:addressPrefixes[0],ASPath:asPath,NextHopType:nextHopType,NextHop:nextHops[0],Origin:routeOrigin}' | awk '{ gsub(/\/subscriptions\/'$subid'\/resourceGroups\/'$prefix'\/providers\/Microsoft.Network\//,""); gsub("virtualHubs","vhub");gsub("hubVirtualNetworkConnections","vhubcon"); print }'

# Get the effective routes configured for the Virtual Hub2 vnet connection
hub2conid=$(az network vhub connection list -g $prefix --vhub-name ${prefix}hub2 --query [0].id -o tsv)
az network vhub get-effective-routes --resource-type HubVirtualNetworkConnection -g $prefix -n ${prefix}hub2 --resource-id $hub2conid --query 'value[].{Prefix:addressPrefixes[0],ASPath:asPath,NextHopType:nextHopType,NextHop:nextHops[0],Origin:routeOrigin}' | awk '{ gsub(/\/subscriptions\/'$subid'\/resourceGroups\/'$prefix'\/providers\/Microsoft.Network\//,""); gsub("virtualHubs","vhub");gsub("hubVirtualNetworkConnections","vhubcon"); print }'
~~~

Output vwan hub1 vnet connection details:

~~~json
[
  {
    "ASPath": "65520-65520",
    "NextHop": "vhub/cptdazvwanhub2",
    "NextHopType": "Remote Hub",
    "Origin": "vhub/cptdazvwanhub2",
    "Prefix": "10.2.0.0/16"
  }
]
~~~

### Get VNet Peering details

~~~ bash
spoke1vnetpname=$(az network vnet peering list -g $prefix --vnet-name ${prefix}spoke1 --query [].name -o tsv)
az network vnet peering list -g $prefix --vnet-name ${prefix}spoke1 --query "[].{name:name,allowForwardedTraffic:allowForwardedTraffic,allowVirtualNetworkAccess:allowVirtualNetworkAccess}" -o table  
~~~

Output vnet peering details of spoke1:

~~~text
Name                                                         AllowForwardedTraffic    AllowVirtualNetworkAccess
-----------------------------------------------------------  -----------------------  ---------------------------
RemoteVnetToHubPeering_bf7ac4f2-05d6-414c-ab2f-a06903d9b600  False                    True
cptdazvwanspoke1cptdazvwanfw                                 True                     True
~~~

NOTES:
- Peering done via vWAN does always define AllowForwardedTraffic = False.

### Test connection with ping ans ssh

Ping from spoke1 vm:

~~~ bash
ssh-keygen -R [127.0.0.1]:50022
spoke1vmid=$(az vm show -g $prefix -n ${prefix}spoke1 --query id -o tsv)
# establish an ssh tunnel
az network bastion tunnel -n ${prefix}bastion1 -g $prefix --target-resource-id $spoke1vmid --resource-port 22 --port 50022
# open a new terminal STR SHIFT Ö at vscode
ssh -p 50022 -i azbicep/ssh/chpinoto.key chpinoto@127.0.0.1
yes
demo!pass123
ping 10.4.0.4 # ping vm at spoke2 via vwan peering
ping 10.5.0.4 # ping vm at fw via global vnet peering
logout
exit #close shell
# close tunnel with Ctrl + C
~~~

Ping from fw vm:

~~~ bash
fwvmid=$(az vm show -g $prefix -n ${prefix}fw --query id -o tsv)
az network bastion ssh -n ${prefix}fw -g $prefix --target-resource-id $fwvmid --auth-type ssh-key --username chpinoto --ssh-key azbicep/ssh/chpinoto.key
demo!pass123
ping -c 3 10.1.0.4 # ping vm at spoke1
ping -c 3 10.5.0.4 # ping vm at spoke2
logout
sudo chmod 655 azbicep/ssh/chpinoto.key
~~~


### Connection Manager [NOT WORKING]

> NOTE: We expect that you already have an existing "Network Watch" Azure resource and a corresponding "Log Analytics Workspace" setup.

Create Azure connection-monitor ICMP test from:
- Vnet "spoke1" to vnet "spoke2"
- Vnet "spoke1" to vnet "fw"
- Vnet "spoke2" to vnet "spoke1"
- Vnet "spoke2" to vnet "fw"
- Vnet "fw" to vnet "spoke1"
- Vnet "fw" to vnet "spoke2"

Because this would become a very long az cli command we did put everything inside a bash script called azconmon.sh which can be feeded with the needed parameters.

Retrieve the Log Analytis Workspace id.

~~~ bash
az monitor log-analytics workspace create -g $prefix  -n $prefix -l $location1
lawguid=$(az monitor log-analytics workspace list -g $prefix --query [].customerId -o tsv)
lawid=$(az monitor log-analytics workspace show -g $prefix -n $prefix --query id -o tsv)
~~~

Create connection monitor test.

> NOTE: After all the changes which have been introduce you maybe will face issue by setting up the connnection monitor test. If this is the case just restart the VMs and it should work. At least it did work for me.

~~~ bash
spoke1vmid=$(az vm show -g $prefix -n ${prefix}spoke1 --query id -o tsv)
spoke1vmname=$(az vm show -g $prefix -n ${prefix}spoke1 --query name -o tsv)
spoke2vmid=$(az vm show -g $prefix -n ${prefix}spoke2 --query id -o tsv)
spoke2vmname=$(az vm show -g $prefix -n ${prefix}spoke2 --query name -o tsv)
fwvmid=$(az vm show -g $prefix -n ${prefix}fw --query id -o tsv)
./azbicep/bicep/azconmon.sh $prefix $location1 s1tos2 $spoke1vmid $spoke1vmname $spoke2vmid $spoke2vmname
./azbicep/bicep/azconmon.sh  $prefix $location1 s1tofw $spoke1vmid ${prefix}spoke1 $fwvmid ${prefix}fw
./azbicep/bicep/azconmon.sh  $prefix $location1 s2tos1 $spoke2vmid ${prefix}spoke2 $spoke1vmid ${prefix}spoke1
./azbicep/bicep/azconmon.sh  $prefix $location1 sstofw $spoke2vmid ${prefix}spoke2 $fwvmid ${prefix}fw
./azbicep/bicep/azconmon.sh  $prefix $location1 fwtos1 $fwvmid ${prefix}fw $spoke2vmid ${prefix}spoke2
./azbicep/bicep/azconmon.sh  $prefix $location1 fwtos2 $fwvmid ${prefix}fw $spoke1vmid ${prefix}spoke1
~~~

Verify if test have been deployed.

~~~ bash
az network watcher connection-monitor list -l $location1 -o table
~~~

Define new variables to query the connection-monitor results.

~~~ bash
# lawid=$(az monitor log-analytics workspace list -g DefaultResourceGroup-SCUS --query [].customerId -o tsv)
lawid=$(az monitor log-analytics workspace list -g defaultresourcegroup-eus --query [].customerId -o tsv)
query="NWConnectionMonitorTestResult | where TimeGenerated > ago(5m) | sort by TestResult | project TestGroupName, TestResult | summarize count() by TestResult,TestGroupName"
~~~

Let´s have a look at our connection manager test results.

~~~ text
az monitor log-analytics query -w $lawid --analytics-query "$query" -o table

TableName      TestGroupName    TestResult    Count_
-------------  ---------------  ------------  --------
PrimaryResult  s1tos2tgrp       Fail          1
PrimaryResult  h1tos2tgrp       Pass          1
PrimaryResult  h1tos1tgrp       Pass          2
PrimaryResult  h1tos3tgrp       Pass          1
~~~

### Clean up

~~~ bash
az group delete -n $prefix -y --no-wait
~~~

# Misc

## Azure vWAN

NOTES:
- Assuming you have a route enabled on your vNet to send traffic to the Azure Firewall then you won't be able to RDP directly to the Public IP of your VM. The problem here is something called asymmetric routing. Your inbound request goes to the public IP of the VM, the RDP client expects the response to come from the same IP, however because your outbound traffic is being routed to the firewall, the response comes from the firewall IP. The client does not allow this, as it is a security issue, so your connection fails.
(source https://docs.microsoft.com/en-us/answers/questions/527091/how-to-rdp-azure-vm-behind-azure-firewall.html)

- Inter-region traffic cannot be inspected by Azure Firewall or NVA. Additionally, configuring both private and internet routing policies is currently not supported in most Azure regions. Doing so will put Gateways (ExpressRoute, Site-to-site VPN and Point-to-sive VPN) in a failed state and break connectivity from on-premises branches to Azure. Please ensure you only have one type of routing policy on each Virtual WAN hub. For more information, please contact previewinterhub@microsoft.com.
(source https://docs.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies)

- Filtering inter-hub traffic in secure virtual hub deployments	Secured Virtual Hub to Secured Virtual Hub communication filtering isn't yet supported. However, hub to hub communication still works if private traffic filtering via Azure Firewall isn't enabled.
(source https://docs.microsoft.com/en-us/azure/firewall-manager/overview#known-issues)


~~~bash
#List Route tables of a certain vhub.
az network vhub route-table list -g $prefix --vhub-name ${prefix}hub1 | awk '{ gsub(/\/subscriptions\/'$subid'\/resourceGroups\/'$prefix'\/providers\/Microsoft.Network\//,""); gsub("virtualHubs","vhub");gsub("hubVirtualNetworkConnections","vhubcon"); print }'
# Show route table details
az network vhub route-table show -n defaultRouteTable -g $prefix --vhub-name ${prefix}hub1 --query routes
~~~


## Network Watch Connection Monitor tips and tricks

~~~ bash
az network watcher list -o table
az network watcher connection-monitor show -l $location -n h1tos1 --query outputs[0].workspaceSettings.workspaceResourceId -o tsv
# Delete all test connection
az network watcher connection-monitor list -l $location -o table --query [].name  | tee >(echo)
az network watcher connection-monitor delete -l $location -n h1tos1
az network watcher connection-monitor delete -l $location -n test1
az network watcher connection-monitor delete -l $location -n test2
az network watcher connection-monitor delete -l $location -n s1tos2
az network watcher connection-monitor delete -l $location -n s3toh1
az network watcher connection-monitor delete -l $location -n h1tos1test


az network watcher test-ip-flow \
  --direction outbound \
  --local ${hub1ip}:* \
  --protocol Icmp \
  --remote ${spoke2ip}:8080 \
  --vm $hub1vmid \
  --nic $hub1nicid \
  -g $prefix \
  --out table

az network watcher list --query '[?location==`eastus`].location' '[?location==${location}]' -l $location
lawidquery=[?location==\`$location\`].customerId
lawlocation=$(az network watcher list --query $lawidquery -o tsv)
lawid=$(az network watcher connection-monitor show -l $location -n h1tos1 --query outputs[0].workspaceSettings.workspaceResourceId -o tsv)
az monitor log-analytics workspace list --query $lawidquery -o table
~~~

## Links
- [Using Azure Firewall as a Network Virtual Appliance (NVA)](https://techcommunity.microsoft.com/t5/fasttrack-for-azure/using-azure-firewall-as-a-network-virtual-appliance-nva/ba-p/1972934)
- [Good read about why we need transitive routing Part 1](https://ine.com/blog/azure-practical-peer-to-peer-transitive-routing)
- [Good read about why we need transitive routing Part 2](https://ine.com/blog/azure-practical-peer-to-peer-transitive-routing-part-2)
- [Azure VNets overview](https://github.com/microsoft/Common-Design-Principles-for-a-Hub-and-Spoke-VNET-Archiecture/blob/master/README.md)
- [Exc video by stuart](https://www.youtube.com/watch?v=m-GmkMFZ5WA)
- [vWAN Hub Routing pref by jose](https://blog.cloudtrooper.net/2022/07/14/azure-virtual-wan-hub-routing-preference/)
- [Lesson learned on vwan](https://www.cloudnation.nl/inspiratie/blogs/practical-lessons-learned-from-working-with-azure-virtual-wan)


## SSH

Clear SSH key

~~~bash
# Remove know host
ssh-keygen -R [127.0.0.1]:50022
~~~

Generate SSH KEY.

~~~ text
ssh-keygen -m PEM -t rsa -b 4096 -C "azure chpinoto vm user `date +%Y-%m-%d`" -f ~/.ssh/azure/chpinoto
mv ~/.ssh/azure/chpinoto ~/.ssh/azure/chpinoto.key
cat ~/.ssh/azure/chpinoto.pub
ssh -i chpinoto.key chpinoto@10.2.0.4
~~~

## Stop the firewall

~~~ bash
$azfw1 = Get-AzFirewall -Name cptdvnetfw1 -ResourceGroupName cptdvnet
$azfw1.Deallocate()
Set-AzFirewall -AzureFirewall $azfw1

$azfw2 = Get-AzFirewall -Name cptdvnetfw2 -ResourceGroupName cptdvnet
$azfw1.Deallocate()
Set-AzFirewall -AzureFirewall $azfw2
~~~

## Start and stop the azure firewall

~~~ pwsh
Get-AzContext
$prefix = "cptdvwan"
$azfw = Get-AzFirewall -Name $prefix -ResourceGroupName $prefix
$vnet = Get-AzVirtualNetwork -ResourceGroupName $prefix -Name ${prefix}hub1
$publicip = Get-AzPublicIpAddress -Name ${prefix}fw -ResourceGroupName $prefix
$azfw.Allocate($vnet,@($publicip))
Set-AzFirewall -AzureFirewall $azfw
~~~~

### github
~~~ bash
sudo chmod 655 azbicep/ssh/chpinoto.key
gh repo create $prefix --private
git init
git remote add origin https://github.com/cpinotossi/$prefix.git
git submodule add https://github.com/cpinotossi/azbicep
git submodule init
git submodule update
git submodule update --init
git status
git add .gitignore
git add *
git commit -m"Partly working"
git push origin main
git push --set-upstream origin main
git push --recurse-submodules=on-demand
git rm README.md # unstage
git --help
git config advice.addIgnoredFile false
~~~


