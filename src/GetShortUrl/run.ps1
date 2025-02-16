using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Parse short url id from the request route
$ShortUrlId = $Request.Params.ShortUrlId

# Return response based on request parameters
if ([String]::IsNullOrWhiteSpace($ShortUrlId)) {
    # Return 404 if a short url id is not provided
    Write-Warning 'ShortUrlId was not provided'
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::NotFound
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

if (-not $ShortUrlRecord) {
    # Return 404 if the short url id does not exist
    Write-Warning "ShortUrlId [$ShortUrlId] is not registered."
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::NotFound
    })
    exit
} elseif ($ShortUrlRecord.RowKey -ne $ShortUrlId) {
    # Return 404 if the short url id in the request
    # does not match the Azure Tables RowKey returned by the input binding
    Write-Warning "ShortUrlId [$ShortUrlId] does not match the input binding record RowKey [$($ShortUrlRecord.RowKey)]"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::NotFound
    })
    exit
} else {
    # Redirect to the original URL
    Write-Information "Redirecting to [$($ShortUrlRecord.OriginalUrl)]"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Redirect
        Headers = @{ Location = $ShortUrlRecord.OriginalUrl }
    })
}
