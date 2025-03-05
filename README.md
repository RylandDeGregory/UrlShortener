# Azure Functions URL Shortener

A simple URL shortener built using Azure Functions, Azure Table Storage, and PowerShell.

## Setup

This project utilizes the [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/overview) to provision and manage Azure infrastructure.

### Install prerequisites

1. Install PowerShell 7: [Instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
2. Install the Azure Developer CLI (`azd`): [Instructions](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd).
3. Install the Azure Functions Core Tools (`func`): [Instructions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local).

## Run locally

Navigate to the `src` app folder and create a file in that folder named `local.settings.json` that contains this JSON data:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME_VERSION": "7.4",
    "FUNCTIONS_WORKER_RUNTIME": "powershell",
    "IS_LOCAL": true,
    "STORAGE_ACCOUNT_NAME": "devstoreaccount1",
    "STORAGE_ACCESS_KEY": "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==",
    "STORAGE_TABLE_NAME": "RegisteredUrls"
  }
}
```

You can use [Azurite](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azurite?tabs=visual-studio-code%2Ctable-storage) to emulate Azure Storage locally with the [well-known values](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azurite#well-known-storage-account-and-key) for `STORAGE_ACCOUNT_NAME` and `STORAGE_ACCESS_KEY` defined above, or use Azure Storage locally by overriding those settings and updating `IS_LOCAL` to `false`.

> If you wish to connect to Azurite using the [Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer), you must first start both the Blob and Table Services from VS Code.

1. (optional) Run Azurite Table Service.
2. Run the Azure Functions Core tools: `cd src && func host start`.
3. Interact with endpoints locally using Postman, Curl, PowerShell, etc.

## Deploy to Azure

Run this command to provision the function app, with any required Azure resources, and deploy your code:

```shell
azd up
```

You're prompted to supply these required deployment parameters:

| Parameter | Description |
| ---- | ---- |
| _Environment name_ | An environment that's used to maintain a unique deployment context for your app.|
| _Azure subscription_ | Subscription in which your resources are created.|
| _Azure location_ | Azure region in which to create the resource group that contains the new Azure resources. Only regions that currently support the Flex Consumption plan are shown.|

After publish completes successfully, `azd` provides you with the URL endpoints of your new functions, but without the function key values required to access the endpoints. To learn how to obtain these same endpoints along with the required function keys, see [Invoke functions on Azure](https://learn.microsoft.com/azure/azure-functions/create-first-function-azure-developer-cli?pivots=programming-language-powershell#invoke-the-function-on-azure).

## Redeploy your code

You can run the `azd up` command as many times as you need to both provision your Azure resources and deploy code updates to your Function App.

> [!NOTE]
> Deployed code files are always overwritten by the latest deployment package.

## Clean up resources

When you're done working with your function app and related resources, you can use this command to delete the function app and its related resources from Azure and avoid incurring any further costs:

```shell
azd down
```

### Configure CI/CD with GitHub Actions

You can [configure CI/CD for your azd project](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/configure-devops-pipeline?tabs=GitHub) using GitHub Actions, so you don't have to run `azd up` every time you want to push changes to Azure.

```shell
azd pipeline config
```
