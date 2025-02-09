targetScope = 'resourceGroup'

@sys.minLength(1)
@sys.maxLength(260)
@sys.description('Application Insights name. Default: appi-urlshort-$<uniqueSuffix>')
param appInsightsName string = 'appi-urlshort-${uniqueSuffix}'

@sys.minLength(1)
@sys.maxLength(60)
@sys.description('App Service Plan name. Default: asp-urlshort-$<uniqueSuffix>')
param appServicePlanName string = 'asp-urlshort-${uniqueSuffix}'

@minLength(1)
@maxLength(64)
@description('AZD environment name. Used to generate the value of the uniqueSuffix parameter.')
param environmentName string

@sys.minLength(2)
@sys.maxLength(60)
@sys.description('Function App name. Default: func-urlshort-$<uniqueSuffix>')
param functionAppName string = 'func-urlshort-${uniqueSuffix}'

@sys.minLength(1)
@sys.description('The Azure Region to deploy the resources into.')
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@sys.minLength(4)
@sys.maxLength(63)
@sys.description('Log Analytics Workspace name. Default: log-urlshort-$<uniqueSuffix>')
param logAnalyticsWorkspaceName string = 'log-urlshort-${uniqueSuffix}'

@sys.description('If Azure Monitor Diagnostic Settings should be enabled for the resources. Default: false')
param logsEnabled bool = false

@sys.minLength(3)
@sys.maxLength(63)
@sys.description('Storage Account Blob Container name (used to store application package). Default: func-app-package-storage')
param storageAccountBlobContainerName string = 'func-app-package-storage'

@sys.minLength(3)
@sys.maxLength(24)
@sys.description('Storage Account name. Default: sturlshort$<uniqueSuffix>')
param storageAccountName string = 'sturlshort${replace(uniqueSuffix, '-', '')}'

@sys.minLength(3)
@sys.maxLength(63)
@sys.description('Storage Account Table name (used to store application data). Default: RegisteredUrls')
param storageAccountTableName string = 'RegisteredUrls'

@sys.minLength(1)
@sys.maxLength(13)
@sys.description('A unique string to add as a suffix to all resources. Default: toLower(uniqueString(resourceGroup().id, environmentName, location))')
param uniqueSuffix string = toLower(uniqueString(resourceGroup().id, environmentName, location))

@sys.minLength(9)
@sys.maxLength(18)
@sys.description('Virtual Network IPv4 CIDR prefix. Default: 10.100.0.0/24')
param virtualNetworkAddressPrefix string = '10.100.0.0/24'

@sys.minLength(2)
@sys.maxLength(64)
@sys.description('Virtual Network name. Default: vnet-urlshort-$<uniqueSuffix>')
param virtualNetworkName string = 'vnet-urlshort-${uniqueSuffix}'

@sys.minLength(9)
@sys.maxLength(18)
@sys.description('Virtual Network Function App Integration Subnet IPv4 CIDR prefix. Default: 10.100.0.0/26')
param virtualNetworkSubnetAddressPrefix string = '10.100.0.0/26'

@sys.minLength(1)
@sys.maxLength(80)
@sys.description('Function App Virtual Network Integration Subnet name. Default: snet-functionAppVirtualNetworkIntegration')
param virtualNetworkSubnetName string = 'snet-functionAppVirtualNetworkIntegration'

// Set AZD Environment name
var tags = { 'azd-env-name': environmentName }

module functionApp 'modules/functionApp.bicep' = {
  name: 'FunctionApp'
  params: {
    appServicePlanName: appServicePlanName
    functionAppName: functionAppName
    location: location
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    logsEnabled: logsEnabled
    storageAccountBlobContainerName: storageAccount.outputs.containerName
    storageAccountName: storageAccount.outputs.name
    storageAccountTableName: storageAccount.outputs.tableName
    tags: tags
    virtualNetworkName: virtualNetwork.outputs.name
    virtualNetworkSubnetName: virtualNetwork.outputs.functionAppSubnetName
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'Monitoring'
  params: {
    appInsightsName: appInsightsName
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logsEnabled: logsEnabled
    tags: tags
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'RBAC'
  params: {
    appInsightsName: monitoring.outputs.appInsightsName
    principalId: functionApp.outputs.principalId
    storageAccountName: storageAccount.outputs.name
  }
}

resource resourceGroupLock 'Microsoft.Authorization/locks@2020-05-01' = {
  scope: resourceGroup()
  name: 'DoNotDelete'
  properties: {
    level: 'CanNotDelete'
    notes: 'This lock prevents the accidental deletion of resources.'
  }
  dependsOn: [
    rbac
  ]
}

module storageAccount 'modules/storage.bicep' = {
  name: 'Storage'
  params: {
    location: location
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    logsEnabled: logsEnabled
    storageAccountBlobContainerName: storageAccountBlobContainerName
    storageAccountName: storageAccountName
    storageAccountTableName: storageAccountTableName
    tags: tags
    virtualNetworkName: virtualNetwork.outputs.name
    virtualNetworkSubnetName: virtualNetwork.outputs.functionAppSubnetName
  }
}

module virtualNetwork 'modules/networking.bicep' = {
  name: 'Networking'
  params: {
    location: location
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    logsEnabled: logsEnabled
    tags: tags
    virtualNetworkAddressPrefix: virtualNetworkAddressPrefix
    virtualNetworkName: virtualNetworkName
    virtualNetworkSubnetAddressPrefix: virtualNetworkSubnetAddressPrefix
    virtualNetworkSubnetName: virtualNetworkSubnetName
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output FUNCTION_APP_NAME string = functionApp.outputs.name

// $Params = @{
//     Location          = 'eastus2'
//     Name              = 'UrlShortener-main'
//     ResourceGroupName = 'UrlShort'
//     TemplateFile      = './infrastructure/main.bicep'
//     Verbose           = $true
// }
// New-AzResourceGroupDeployment @Params
