targetScope='resourceGroup'

param prefix string
var spoke1name = '${prefix}spoke1'
var fwname = '${prefix}fw'
var spoke2name = '${prefix}spoke2'

resource spoke1 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: spoke1name
}

resource fw 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: fwname
}

resource spoke2 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: spoke2name
}

module fwtospoke1 'azbicep/bicep/vpeer.bicep' = {
  name: 'fwtospoke1module'
  params: {
    vnethubname: fw.name
    vnetspokename: spoke1.name
    spokeUseRemoteGateways: false
  }
}

module fwtospoke2 'azbicep/bicep/vpeer.bicep' = {
  name: 'fwtospoke2module'
  params: {
    vnethubname: fw.name
    vnetspokename: spoke2.name
    spokeUseRemoteGateways: false
  }
}
