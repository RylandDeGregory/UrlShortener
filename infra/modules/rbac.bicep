@sys.minLength(1)
@sys.maxLength(260)
@sys.description('Application Insights name.')
param appInsightsName string

@sys.minLength(36)
@sys.maxLength(36)
@sys.description('Microsoft Entra Security Principal Object ID.')
param principalId string

@sys.minLength(3)
@sys.maxLength(24)
@sys.description('Storage Account name.')
param storageAccountName string


resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// RBAC Role Definitions
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

@sys.description('Built-in Monitoring Metrics Publisher role. See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/monitor#monitoring-metrics-publisher')
resource monitoringMetricsPublisherRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '3913510d-42f4-4e42-8a64-420c390055eb'
}

// RBAC Role Assignments
@sys.description('Allows Principal to write to Storage Account Blobs')
resource storageBlobOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, storageAccount.id, storageBlobOwnerRole.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobOwnerRole.id
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

@sys.description('Allows Principal to write to Storage Account Tables')
resource storageTableContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, storageAccount.id, storageTableContributorRole.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageTableContributorRole.id
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

@sys.description('Allows Principal to write telemetry to Application Insights')
resource monitoringMetricsPublisherAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, appInsights.id, monitoringMetricsPublisherRole.id)
  scope: appInsights
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRole.id
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
