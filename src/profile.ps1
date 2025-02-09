# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.
# if ($env:MSI_SECRET) {
#     Disable-AzContextAutosave -Scope Process | Out-Null
#     Connect-AzAccount -Identity
# }

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.
function Get-MsiAccessToken {
    <#
        .SYNOPSIS
            Get MSI Access Token for the provided Resource URL.
        .EXAMPLE
            Get-MsiAccessToken -ResourceUrl 'https://management.azure.com'
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $ResourceUrl
    )

    try {
        # Get MSI access token
        Write-Information "Getting MSI Access Token for Resource [$ResourceUrl]..."
        $TokenHeaders = @{ 'X-IDENTITY-HEADER' = "$env:MSI_SECRET" }
        $TokenUrl     = "$($env:MSI_ENDPOINT)?resource=$ResourceUrl&api-version=2019-08-01"
        $Token        = (Invoke-RestMethod -Method Get -Uri $TokenUrl -Headers $TokenHeaders).access_token
    } catch {
        Write-Error "Error generating MSI Access Token: $($_.Exception.Message)"
    }

    return $Token
}

function Get-AzTableHeaders {
    <#
        .SYNOPSIS
            Construct Azure Table Storage request headers object.
        .EXAMPLE
            # Use Entra ID authentication
            Get-AzTableHeaders -RowKey 'myrowkey'
        .EXAMPLE
            # Use master key authentication
            Get-AzTableHeaders -RowKey 'myrowkey' -UseSharedKeyAuth
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        # Storage Account containing the Table
        [Parameter()]
        [ValidateLength(3, 24)]
        [string] $StorageAccount = $env:STORAGE_ACCOUNT_NAME,

        # Azure Table name
        [Parameter()]
        [ValidateLength(3, 63)]
        [string] $TableName = $env:STORAGE_TABLE_NAME,

        # Partition Key
        [Parameter()]
        [string] $PartitionKey = 'default',

        # Row Key
        [Parameter()]
        [string] $RowKey,

        # If the request should use master key authentication rather than Entra ID authentication
        [Parameter()]
        [switch] $UseSharedKeyAuth
    )

    # Set Azure Table Storage request headers
    $DateTime = [DateTime]::UtcNow.ToString('R')
    $AzTableHeaders = @{
        'Accept'        = 'application/json;odata=nometadata'
        'x-ms-version'  = '2020-08-04'
        'x-ms-date'     = $DateTime
    }

    if ($UseSharedKeyAuth) {
        # Compute Storage Access Signature
        Write-Verbose 'Get Azure Table Storage SharedKeyLite Signature'
        if ([string]::IsNullOrWhiteSpace($env:STORAGE_ACCESS_KEY)) {
            Write-Error 'STORAGE_ACCESS_KEY environment variable is not set.'
            return 1
        }
        $SigningString  = "$DateTime`n/$StorageAccount/$TableName(PartitionKey='$PartitionKey',RowKey='$RowKey')"
        $HmacSha        = [System.Security.Cryptography.HMACSHA256]@{Key = [Convert]::FromBase64String($env:STORAGE_ACCESS_KEY)}
        $Signature      = [Convert]::ToBase64String($HmacSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($SigningString)))
        $AzTableHeaders += @{'Authorization' = "SharedKeyLite $StorageAccount`:$Signature"}
    } else {
        # Get Azure Storage Access Token
        Write-Verbose 'Get Azure Storage Access Token'
        $AzStorageToken = if ($env:MSI_SECRET) {
            Get-MsiAccessToken -ResourceUrl 'https://storage.azure.com/'
        } else {
            (Get-AzAccessToken -ResourceUrl 'https://storage.azure.com/' -WarningAction SilentlyContinue).Token
        }
        $AzTableHeaders += @{'Authorization' = "Bearer $($AzStorageToken)"}
    }

    Write-Debug 'Azure Table Storage Request Headers:'
    Write-Debug ($AzTableHeaders | ConvertTo-Json)

    return $AzTableHeaders
}

function Get-AzTableRecord {
    <#
        .SYNOPSIS
            Get Azure Table Storage record.
        .EXAMPLE
            Get-AzTableRecord -RowKey 'myrowkey' -Headers $(Get-AzTableHeaders)
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param (
        # Storage Account containing the Table
        [Parameter()]
        [ValidateLength(3, 24)]
        [string] $StorageAccount = $env:STORAGE_ACCOUNT_NAME,

        # Azure Table name
        [Parameter()]
        [ValidateLength(3, 63)]
        [string] $TableName = $env:STORAGE_TABLE_NAME,

        # Partition Key
        [Parameter()]
        [string] $PartitionKey = 'default',

        # Row Key
        [Parameter(Mandatory)]
        [string] $RowKey,

        # Headers for the request
        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    # Get Azure Table Storage request properties
    $AzTableUri = "https://$StorageAccount.table.core.windows.net/$TableName(PartitionKey='$PartitionKey',RowKey='$RowKey')"

    # Get the record from the Azure Table
    Write-Verbose "Get Azure Table record [$AzTableUri]"
    try {
        $AzTableRecord = Invoke-RestMethod -Method Get -Uri $AzTableUri -Headers $Headers
    } catch {
        if ($_.Exception.StatusCode -eq 'NotFound') {
            Write-Verbose "Azure Table record not found [$AzTableUri]"
            return $null
        } else {
            Write-Error "Error getting Azure Table record: $_"
        }
    }

    return $AzTableRecord
}

function Set-AzTableRecord {
    <#
        .SYNOPSIS
            Set Azure Table Storage record.
        .EXAMPLE
            $NewRecord = [pscustomobject]@{
                CreatedAt    = $DateTime
                OriginalUrl  = $OriginalUrl
                PartitionKey = 'default'
                RowKey       = $ShortUrlId
                UpdatedAt    = $DateTime
            }
            Set-AzTableRecord -Record $Record -Headers $(Get-AzTableHeaders)
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param (
        # Storage Account containing the Table
        [Parameter()]
        [ValidateLength(3, 24)]
        [string] $StorageAccount = $env:STORAGE_ACCOUNT_NAME,

        # Azure Table name
        [Parameter()]
        [ValidateLength(3, 63)]
        [string] $TableName = $env:STORAGE_TABLE_NAME,

        # Record to insert into the Table
        [Parameter(Mandatory)]
        [PSCustomObject] $Record,

        # Headers for the request
        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    # Set Azure Tale Storage request properties
    $PartitionKey = $Record.PartitionKey
    $RowKey       = $Record.RowKey
    $AzTableUri   = "https://$StorageAccount.table.core.windows.net/$TableName(PartitionKey='$PartitionKey',RowKey='$RowKey')"
    $AzTableBody  = $Record | ConvertTo-Json -Depth 10

    # Set the record in the Azure Table
    Write-Verbose "Set Azure Table record [$AzTableUri]"
    try {
        Invoke-RestMethod -Method Put -Uri $AzTableUri -Body $AzTableBody -Headers $Headers -ContentType 'application/json'
    } catch {
        Write-Error "Error setting Azure Table record: $_"
    }
}