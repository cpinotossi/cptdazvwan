targetScope='resourceGroup'

//var parameters = json(loadTextContent('parameters.json'))
param location1 string
param location2 string
var username = 'chpinoto'
var password = 'demo!pass123'
param prefix string
param myobjectid string
param myip string

module vwanhub1module 'azbicep/bicep/vwan.bicep' = {
  name: 'vwanhub1deploy'
  params: {
    ciderhub: '10.0.0.0/16'
    locationvhub: location1
    locationvwan: location1
    postfix: 'hub1'
    prefix: prefix
  }
}

module vwanhub2module 'azbicep/bicep/vwan.bicep' = {
  name: 'vwanhub2deploy'
  params: {
    ciderhub: '10.3.0.0/16'
    locationvwan: location1
    locationvhub: location2
    postfix: 'hub2'
    prefix: prefix
  }
  dependsOn:[ 
    vwanhub1module // This is needed because we are refering the vwan which is created at module vwanhub1module
  ]
}

module spoke1vnetmodule 'azbicep/bicep/vnet.bicep' = {
  name: 'spoke1vnetdeploy'
  params: {
    prefix: prefix
    postfix: 'spoke1'
    location: location1
    cidervnet: '10.1.0.0/16'
    cidersubnet: '10.1.0.0/24'
    // ciderbastion: '10.1.1.0/24'
  }
}

module spoke1bastionmodule 'azbicep/bicep/vnet.bicep' = {
  name: 'spoke1bastiondeploy'
  params: {
    prefix: prefix
    postfix: 'bastion1'
    location: location2
    cidervnet: '10.2.0.0/16'
    cidersubnet: '10.2.0.0/24'
    ciderbastion: '10.2.1.0/24'
  }
}

module spoke2vnetmodule 'azbicep/bicep/vnet.bicep' = {
  name: 'spoke2vnetdeploy'
  params: {
    prefix: prefix
    postfix: 'spoke2'
    location: location2
    cidervnet: '10.4.0.0/16'
    cidersubnet: '10.4.0.0/24'
    // ciderbastion: '10.4.1.0/24'
  }
}

module fwvnetmodule 'azbicep/bicep/vnet.bicep' = {
  name: 'fwvnetdeploy'
  params: {
    prefix: prefix
    postfix: 'fw'
    location: location2
    cidervnet: '10.5.0.0/16'
    cidersubnet: '10.5.0.0/24'
    ciderfirewall: '10.5.1.0/24'
    ciderbastion: '10.5.2.0/24'
  }
}

module spoke1vmmodule 'azbicep/bicep/vm.bicep' = {
  name: 'spoke1vmdeploy'
  params: {
    prefix: prefix
    postfix: 'spoke1'
    vnetname: spoke1vnetmodule.outputs.vnetname
    location: location1
    username: username
    password: password
    myObjectId: myobjectid
    privateip: '10.1.0.4'
    imageRef: 'linux'
  }
  dependsOn:[
    spoke1vnetmodule
  ]
}

module spoke2vmmodule 'azbicep/bicep/vm.bicep' = {
  name: 'spoke2vmdeploy'
  params: {
    prefix: prefix
    postfix: 'spoke2'
    vnetname: spoke2vnetmodule.outputs.vnetname
    location: location2
    username: username
    password: password
    myObjectId: myobjectid
    privateip: '10.4.0.4'
    imageRef: 'linux'
  }
  dependsOn:[
    spoke2vnetmodule
  ]
}

module fwvmmodule 'azbicep/bicep/vm.bicep' = {
  name: 'fwvmdeploy'
  params: {
    prefix: prefix
    postfix: 'fw'
    vnetname: fwvnetmodule.outputs.vnetname
    location: location2
    username: username
    password: password
    myObjectId: myobjectid
    privateip: '10.5.0.4'
    imageRef: 'linux'
  }
  dependsOn:[
    fwvnetmodule
  ]
}
