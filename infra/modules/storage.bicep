@sys.description('The Azure Region to deploy the resources into.')
param location string

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


resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName

  resource funcSubnet 'subnets' existing = {
    name: virtualNetworkSubnetName
  }
}

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
  tags: tags

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


output containerName string = storageAccount::blobService::container.name
output name string = storageAccount.name
output tableName string = storageAccount::tableService::table.name
