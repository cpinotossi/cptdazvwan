targetScope='resourceGroup'

param prefix string
var hub1name = '${prefix}hub1'
var hub2name = '${prefix}hub2'
var spoke1name = '${prefix}spoke1'
var spoke1bastionname = '${prefix}bastion1'
var spoke2name = '${prefix}spoke2'


resource hub1 'Microsoft.Network/virtualHubs@2021-05-01' existing = {
  name: hub1name
}

resource hub2 'Microsoft.Network/virtualHubs@2021-05-01' existing = {
  name: hub2name
}

resource spoke1 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: spoke1name
}

resource spoke1bastion 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: spoke1bastionname
}

resource spoke2 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: spoke2name
}


resource hub1defaultrt 'Microsoft.Network/virtualHubs/hubRouteTables@2021-02-01' existing = {
  name: 'defaultRouteTable'
  parent: hub1
}

resource hub2defaultrt 'Microsoft.Network/virtualHubs/hubRouteTables@2021-02-01' existing = {
  name: 'defaultRouteTable'
  parent: hub2
}

resource hub1tospoke1 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2021-05-01' = {
  name: 'hub1tospoke1'
  parent: hub1
  properties: {
    routingConfiguration:{
      associatedRouteTable:{
        id: hub1defaultrt.id
      }
      propagatedRouteTables:{
        labels:[
          'default'
        ]
        ids:[
          {
            id: hub1defaultrt.id
          }
        ]
      }
      vnetRoutes:{
        staticRoutes:[]
      }
    }
    allowHubToRemoteVnetTransit: true
    allowRemoteVnetToUseHubVnetGateways: true
    enableInternetSecurity: true
    remoteVirtualNetwork: {
      id: spoke1.id
    }
  }
}

resource hub1tospoke1bastion 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2021-05-01' = {
  name: 'hub1tospoke1bastion'
  parent: hub1
  properties: {
    routingConfiguration:{
      associatedRouteTable:{
        id: hub1defaultrt.id
      }
      propagatedRouteTables:{
        labels:[
          'default'
        ]
        ids:[
          {
            id: hub1defaultrt.id
          }
        ]
      }
      vnetRoutes:{
        staticRoutes:[]
      }
    }
    allowHubToRemoteVnetTransit: true
    allowRemoteVnetToUseHubVnetGateways: true
    enableInternetSecurity: true
    remoteVirtualNetwork: {
      id: spoke1bastion.id
    }
  }
}

resource hub2tospoke2 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2021-05-01' = {
  name: 'hub2tospoke2'
  parent: hub2
  properties: {
    routingConfiguration:{
      associatedRouteTable:{
        id: hub2defaultrt.id
      }
      propagatedRouteTables:{
        labels:[
          'default'
        ]
        ids:[
          {
            id: hub2defaultrt.id
          }
        ]
      }
      vnetRoutes:{
        staticRoutes:[]
      }
    }
    allowHubToRemoteVnetTransit: true
    allowRemoteVnetToUseHubVnetGateways: true
    enableInternetSecurity: true
    remoteVirtualNetwork: {
      id: spoke2.id
    }
  }
}
