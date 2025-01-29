@sys.description('The Azure Region to deploy the resources into. Default: resourceGroup().location')
param location string = resourceGroup().location

@sys.description('A unique string to add as a suffix to all resources. Default: substring(uniqueString(resourceGroup().id), 0, 5)')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 5)

@sys.description('Application Insights name. Default: appi-urlshorten-$<uniqueSuffix>')
param appInsightsName string = 'appi-urlshorten-${uniqueSuffix}'

@sys.description('App Service Plan name. Default: asp-urlshorten-$<uniqueSuffix>')
param appServicePlanName string = 'asp-urlshorten-${uniqueSuffix}'

@sys.description('Function App name. Default: func-urlshorten-$<uniqueSuffix>')
param functionAppName string = 'func-urlshorten-${uniqueSuffix}'

@sys.description('Log Analytics Workspace name. Default: log-urlshorten-$<uniqueSuffix>')
param logAnalyticsWorkspaceName string = 'log-urlshorten-${uniqueSuffix}'

@sys.description('If Azure Monitor Diagnostic Settings should be enabled for the resources. Default: false')
param logsEnabled bool = false

@sys.description('Storage Account name. Default: sturlshorten$<uniqueSuffix>')
param storageAccountName string = 'sturlshorten${replace(uniqueSuffix, '-', '')}'

@sys.description('Storage Account Blob Container name. Default: app-package-$<functionAppName>-$<uniqueSuffix>')
param storageAccountBlobContainerName string = 'app-package-${functionAppName}'

@sys.description('Storage Account Table name. Default: RegisteredUrls')
param storageAccountTableName string = 'RegisteredUrls'

@sys.description('Virtual Network name. Default: vnet-urlshorten-$<uniqueSuffix>')
param virtualNetworkName string = 'vnet-urlshorten-${uniqueSuffix}'

@sys.description('Virtual Network address prefix. Default: 10.100.0.0/24')
param virtualNetworkAddressPrefix string = '10.100.0.0/24'

@sys.description('Virtual Network Function App Integration Subnet address prefix. Default: 10.100.0.0/26')
param virtualNetworkSubnetAddressPrefix string = '10.100.0.0/26'


// RBAC Role definitions
@sys.description('Built-in Storage Blob Data Owner role. See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-owner')
resource storageBlobOwnerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}

@sys.description('Built-in Storage Table Data Contributor role. See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-table-data-contributor')
resource storageTableContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '19e7f393-937e-4f77-808e-94535e297925'
}

// RBAC Role assignments
@sys.description('Allows Function App Managed Identity to write to Storage Account Blobs')
resource funcMIBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, storageAccount.id, storageBlobOwnerRole.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobOwnerRole.id
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@sys.description('Allows Function App Managed Identity to write to Storage Account Tables')
resource funcMITableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, storageAccount.id, storageTableContributorRole.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageTableContributorRole.id
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
  // Link Application Insights instance to Function App
  tags: {
    'hidden-link:${resourceId('Microsoft.Web/sites', functionAppName)}': 'Resource'
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
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
      ]
    }
    virtualNetworkSubnetId: virtualNetwork.properties.subnets[0].id
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

// Resource Group Lock
resource rgLock 'Microsoft.Authorization/locks@2020-05-01' = {
  scope: resourceGroup()
  name: 'DoNotDelete'
  properties: {
    level: 'CanNotDelete'
    notes: 'This lock prevents the accidental deletion of resources'
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource logAnalyticsWorkspaceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: logAnalyticsWorkspace
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'allMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    allowedCopyScope: 'AAD'
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
      virtualNetworkRules: [
        {
          id: virtualNetwork::funcSubnet.id
          action: 'Allow'
        }
      ]
    }
    publicNetworkAccess: 'Enabled'
  }
  sku: {
    name: 'Standard_LRS'
  }

  // Child resources
  resource blobService 'blobServices' existing = {
    name: 'default'

    resource container 'containers' = {
      name: storageAccountBlobContainerName
    }
  }

  resource tableService 'tableServices' existing = {
    name: 'default'

    resource table 'tables' = {
      name: storageAccountTableName
    }
  }
}

resource blobServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: storageAccount::blobService
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspace.id
  }
}

resource tableServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: storageAccount::tableService
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Virtual Network
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
    name: 'snet-functionAppVirtualNetworkIntegration'
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
}
