using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $ShortUrlRecord, $TriggerMetadata)

# Parse short url id from the request route
$ShortUrlId = $Request.Params.ShortUrlId

# Return response based on request parameters
if ([string]::IsNullOrWhiteSpace($ShortUrlId)) {
    # Return 404 if a short url id is not provided
    Write-Warning 'ShortUrlId was not provided'
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
