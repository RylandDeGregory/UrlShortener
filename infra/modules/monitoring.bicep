@sys.description('The Azure Region to deploy the resources into.')
param location string

@sys.minLength(1)
@sys.maxLength(260)
@sys.description('Application Insights name.')
param appInsightsName string

@sys.minLength(4)
@sys.maxLength(63)
@sys.description('Log Analytics Workspace name.')
param logAnalyticsWorkspaceName string

@sys.description('If Azure Monitor Diagnostic Settings should be enabled for the resources.')
param logsEnabled bool

@sys.description('The Azure Tags to apply to the resources.')
param tags object

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: true
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
  tags: tags
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
  tags: tags
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

output appInsightsName string = appInsights.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
