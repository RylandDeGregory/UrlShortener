@sys.description('The Azure Region to deploy the resources into.')
param location string

@sys.minLength(1)
@sys.maxLength(260)
@sys.description('Application Insights name.')
param appInsightsName string

@sys.minLength(1)
@sys.maxLength(60)
@sys.description('App Service Plan name.')
param appServicePlanName string

@sys.minLength(2)
@sys.maxLength(60)
@sys.description('Function App name.')
param functionAppName string

@sys.minLength(4)
@sys.maxLength(63)
@sys.description('Log Analytics Workspace name.')
param logAnalyticsWorkspaceName string

@sys.description('If Azure Monitor Diagnostic Settings should be enabled for the resources.')
param logsEnabled bool

@sys.minLength(3)
@sys.maxLength(63)
@sys.description('Storage Account Blob Container name.')
param storageAccountBlobContainerName string

@sys.minLength(3)
@sys.maxLength(24)
@sys.description('Storage Account name.')
param storageAccountName string

@sys.minLength(3)
@sys.maxLength(63)
@sys.description('Storage Account Table name.')
param storageAccountTableName string

@sys.description('The Azure Tags to apply to the resources.')
param tags object

@sys.minLength(2)
@sys.maxLength(64)
@sys.description('Virtual Network name.')
param virtualNetworkName string

@sys.minLength(1)
@sys.maxLength(80)
@sys.description('Function App Virtual Network Integration Subnet name.')
param virtualNetworkSubnetName string

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName

  resource funcSubnet 'subnets' existing = {
    name: virtualNetworkSubnetName
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  properties: {
    reserved: true
  }
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  tags: tags
}

resource aspDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: appServicePlan
  properties: {
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    functionAppConfig: {
      deployment: {
        storage: {
          authentication: {
            type: 'SystemAssignedIdentity'
          }
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${storageAccountBlobContainerName}'
        }
      }
      runtime: {
        name: 'powershell'
        version: '7.4'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 100
      }
    }
    httpsOnly: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
          value: 'Authorization=AAD'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_TABLE_NAME'
          value: storageAccountTableName
        }
      ]
    }
    virtualNetworkSubnetId: virtualNetwork::funcSubnet.id
  }
  tags: union(tags, {
    'azd-service-name': 'url-shortener'
  })

  resource basicPublishingCredentialsPoliciesFtp 'basicPublishingCredentialsPolicies' = {
    name: 'ftp'
    properties: {
      allow: false
    }
  }

  resource basicPublishingCredentialsPoliciesScm 'basicPublishingCredentialsPolicies' = {
    name: 'scm'
    properties: {
      allow: false
    }
  }
}

resource funcDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: functionApp
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

output name string = functionApp.name
output principalId string = functionApp.identity.principalId
output uri string = 'https://${functionApp.properties.defaultHostName}'
