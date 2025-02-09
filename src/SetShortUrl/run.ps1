using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $ShortUrlRecord, $TriggerMetadata)

# Parse short url id from the request route
$ShortUrlId = $Request.Params.ShortUrlId

# Extract original url from body or query parameter
$OriginalUrl = if ($Request.Body.url) { $Request.Body.url } else { $Request.Query.url }

if ([string]::IsNullOrWhiteSpace($ShortUrlId) -or [string]::IsNullOrWhiteSpace($OriginalUrl)) {
    # Return 400 if a short url id or original url is not provided
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'ShortUrlId is required'
    })
    exit
} elseif ([string]::IsNullOrWhiteSpace($OriginalUrl)) {
    # Return 400 if the original url is not provided
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'OriginalUrl is required'
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

# Create the record to be inserted into the Table
$DateTime = [DateTime]::UtcNow.ToString('o')
$NewRecord = [pscustomobject]@{
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

# Return 200 OK if the record was created successfully
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
