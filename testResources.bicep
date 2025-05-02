@description('The region where the resources will be deployed')
param region string

@description('The IP tag type')
param ipTag string = 'FirstPartyUsage'

@description('The IP tag value')
param ipTagValue string = '/DelegatedNetworkControllerTest'


var containerGroup1 = {
  publicIPName: 'container1PublicIP'
  publicIPDNSName: 'container1${uniqueString(resourceGroup().id)}'
}

var containerGroup2 = {
  publicIPName: 'container2PublicIP'
  publicIPDNSName: 'container2${uniqueString(resourceGroup().id)}'
}

resource containerGroup1PublicIP 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: containerGroup1.publicIPName
  location: region
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: containerGroup1.publicIPDNSName
    }
    ipTags: [
      {
        ipTagType: ipTag
        tag: ipTagValue
      }
    ]
  }
}


resource containerGroup2PublicIP 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: containerGroup2.publicIPName
  location: region
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: containerGroup2.publicIPDNSName
    }
    ipTags: [
      {
        ipTagType: ipTag
        tag: ipTagValue
      }
    ]
  }
}

output fqdn1 string = containerGroup1PublicIP.properties.dnsSettings.fqdn
output fqdn2 string = containerGroup2PublicIP.properties.dnsSettings.fqdn
