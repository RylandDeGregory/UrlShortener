using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Parse short url id from the request route
$ShortUrlId = $Request.Params.ShortUrlId

# Extract original url from body or query parameter
$OriginalUrl = if ($Request.Body.url) { $Request.Body.url } else { $Request.Query.url }

if ([String]::IsNullOrWhiteSpace($ShortUrlId) -or [String]::IsNullOrWhiteSpace($OriginalUrl)) {
    # Return 400 if a short url id or original url is not provided
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'ShortUrlId is required'
    })
    exit
} elseif ([String]::IsNullOrWhiteSpace($OriginalUrl)) {
    # Return 400 if the original url is not provided
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'OriginalUrl is required'
    })
    exit
}

# Get Azure Table Storage request headers
try {
    Write-Verbose 'Get Azure Table Storage request headers'
    $Headers = Get-AzTableHeaders -RowKey $ShortUrlId
} catch {
    $ErrorMessage = "Error getting Azure Table Storage headers: $_"
    Write-Error $ErrorMessage
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body      = $ErrorMessage
    })
    exit
}

# Get the record from the Azure Table
try {
    $ShortUrlRecord = Get-AzTableRecord -RowKey $ShortUrlId -Headers $Headers
} catch {
    $ErrorMessage = "Error getting record [$ShortUrlId] from Azure Table Storage: $_"
    Write-Error $ErrorMessage
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body      = $ErrorMessage
    })
    exit
}

if ($ShortUrlRecord) {
    # Return 409 if the short url id already exists
    Write-Warning "ShortUrlId [$ShortUrlId] is already registered."
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Conflict
    })
    exit
}

# Define the record to be inserted into the Table
$DateTime = Get-Date -AsUTC -Format 'o'
$NewRecord = [PSCustomObject]@{
    CreatedAt    = $DateTime
    OriginalUrl  = $OriginalUrl
    PartitionKey = 'default'
    RowKey       = $ShortUrlId
    UpdatedAt    = $DateTime
}

# Insert the record into the Table
try {
    Write-Information "Insert record with ID [$ShortUrlId] into Azure Table Storage"
    Set-AzTableRecord -Record $NewRecord -Headers $Headers | Out-Null
} catch {
    $ErrorMessage = "Error inserting record into Azure Table Storage: $_"
    Write-Error $ErrorMessage
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body      = $ErrorMessage
    })
    exit
}

# Return 200 OK if the record was inserted successfully
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
