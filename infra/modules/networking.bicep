@sys.description('The Azure Region to deploy the resources into.')
param location string

@sys.minLength(4)
@sys.maxLength(63)
@sys.description('Log Analytics Workspace name.')
param logAnalyticsWorkspaceName string

@sys.description('If Azure Monitor Diagnostic Settings should be enabled for the resources.')
param logsEnabled bool

@sys.description('The Azure Tags to apply to the resources.')
param tags object

@sys.minLength(9)
@sys.maxLength(18)
@sys.description('Virtual Network address prefix.')
param virtualNetworkAddressPrefix string

@sys.minLength(2)
@sys.maxLength(64)
@sys.description('Virtual Network name.')
param virtualNetworkName string

@sys.minLength(9)
@sys.maxLength(18)
@sys.description('Function App Virtual Network Integration Subnet address prefix.')
param virtualNetworkSubnetAddressPrefix string

@sys.minLength(1)
@sys.maxLength(80)
@sys.description('Function App Virtual Network Integration Subnet name.')
param virtualNetworkSubnetName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
  }

  resource funcSubnet 'subnets' = {
    name: virtualNetworkSubnetName
    properties: {
      addressPrefix: virtualNetworkSubnetAddressPrefix
      delegations: [
        {
          name: 'functionAppDelegation'
          properties: {
            serviceName: 'Microsoft.App/environments'
          }
        }
      ]
      serviceEndpoints: [
        {
          service: 'Microsoft.Storage'
          locations: [
            location
          ]
        }
      ]
    }
  }
  tags: tags
}

resource virtualNetworkDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: virtualNetwork
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspace.id
  }
}

output functionAppSubnetName string = virtualNetwork::funcSubnet.name
output name string = virtualNetwork.name
