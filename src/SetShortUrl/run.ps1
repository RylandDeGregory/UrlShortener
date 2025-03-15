using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Parse short url id from the request route
$ShortUrlId = $Request.Params.ShortUrlId

# Extract original url from body or query parameter
$OriginalUrl = if ($Request.Body.url) { $Request.Body.url } else { $Request.Query.url }
$ForceUpdate = if ($Request.Body.force) { $Request.Body.force } else { $Request.Query.force }
$TrackClicks = if ($Request.Body.trackClicks) { $Request.Body.trackClicks } else { $Request.Query.trackClicks }

#region ValidateRequest
if ([String]::IsNullOrWhiteSpace($ShortUrlId)) {
    # Return 400 if a short url id is not provided
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'ShortUrlId is required'
    })
    exit
} elseif ([String]::IsNullOrWhiteSpace($OriginalUrl) -and [String]::IsNullOrWhiteSpace($TrackClicks)) {
    # Return 400 if the original url is not provided
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'Url is required'
    })
    exit
} elseif (-not [String]::IsNullOrWhiteSpace($ForceUpdate) -and $ForceUpdate -ne 'true') {
    # Return 400 if the force is set to an invalid value
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'Force must be "true" if set'
    })
    exit
} elseif (-not [String]::IsNullOrWhiteSpace($TrackClicks) -and $TrackClicks -notin 'true', 'false') {
    # Return 400 if the trackClicks is set to an invalid value
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'TrackClicks must be "true" or "false" if set'
    })
    exit
}

# Validate the short URL ID
if (-not ($ShortUrlId -match '^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$') -or $ShortUrlId.Length -gt 50) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'ShortUrlId must contain only alphanumeric characters and hyphens, cannot start or end with a hyphen, and cannot exceed 50 characters.'
    })
    exit
}

# Validate the input URL
if (-not [String]::IsNullOrWhiteSpace($OriginalUrl)) {
    try {
        $uri = [System.Uri]::new($OriginalUrl)
        if (-not ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https')) {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'URL must use HTTP or HTTPS scheme'
            })
            exit
        }
    } catch {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'Url must be a valid URI'
        })
        exit
    }
}
#endregion ValidateRequest

#region GetRecord
# Get Azure Table Storage request headers
try {
    Write-Verbose 'Get Azure Table Storage request headers'
    $Headers = Get-AzTableHeaders -RowKey $ShortUrlId -Verbose
} catch {
    $ErrorMessage = "Error getting Azure Table Storage headers: $_"
    Write-Error $ErrorMessage
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = $ErrorMessage
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
        Body       = $ErrorMessage
    })
    exit
}
#endregion GetRecord

#region SetRecord
if ($ShortUrlRecord) {
    # Update the existing record if the force parameter is set
    if ($ForceUpdate -eq 'true') {
        if ($ShortUrlRecord.Url -eq $OriginalUrl -and [string]$ShortUrlRecord.TrackClicks -eq $TrackClicks) {
            # Return 200 if the new url is the same as the existing url
            Write-Information "Url [$OriginalUrl] is the existing value for [$ShortUrlId]"
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
            })
            exit
        }
        if (-not [String]::IsNullOrWhiteSpace($OriginalUrl) -and $ShortUrlRecord.Url -ne $OriginalUrl) {
            Write-Information "Url changed from [$($ShortUrlRecord.Url)] to [$OriginalUrl]"
            $ShortUrlRecord.Url = $OriginalUrl
        }

        if (-not [String]::IsNullOrWhiteSpace($TrackClicks)) {
            Write-Information "TrackClicks changed from [$($ShortUrlRecord.TrackClicks)] to [$TrackClicks]"

            # Ensure TrackClicks property exists
            if (-not (Get-Member -InputObject $ShortUrlRecord -Name 'TrackClicks')) {
                Add-Member -InputObject $ShortUrlRecord -MemberType NoteProperty -Name 'TrackClicks' -Value ($TrackClicks -eq 'true')
            } else {
                $ShortUrlRecord.TrackClicks = ($TrackClicks -eq 'true')
            }

            # Handle Clicks property
            if ($TrackClicks -eq 'true' -and -not (Get-Member -InputObject $ShortUrlRecord -Name 'Clicks')) {
                Add-Member -InputObject $ShortUrlRecord -MemberType NoteProperty -Name 'Clicks' -Value 0
            }

            Write-Information "$(if ($TrackClicks -eq 'true') { 'Enabled' } else { 'Disabled' }) click tracking for [$ShortUrlId]"
        }

        $TableRecord = $ShortUrlRecord
        $TableRecord.UpdatedAt = Get-Date -AsUTC -Format 'o'
        Write-Information "Update record with ID [$ShortUrlId] in Azure Table Storage"
    } else {
        # Return 409 if the short url id already exists
        Write-Warning "ShortUrlId [$ShortUrlId] is already registered."
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Conflict
        })
        exit
    }
} else {
    # Define the record to be inserted into the Table
    $DateTime = Get-Date -AsUTC -Format 'o'
    $TableRecord = [PSCustomObject]@{
        CreatedAt    = $DateTime
        Url          = $OriginalUrl
        PartitionKey = 'default'
        RowKey       = $ShortUrlId
        UpdatedAt    = $DateTime
    }
    if ($TrackClicks -eq 'true') {
        Add-Member -InputObject $TableRecord -MemberType NoteProperty -Name 'Clicks' -Value 0
        Add-Member -InputObject $TableRecord -MemberType NoteProperty -Name 'TrackClicks' -Value $true
        Write-Information "Enabled click tracking for [$ShortUrlId]"
    }
    Write-Information "Insert record with ID [$ShortUrlId] into Azure Table Storage"
}

# Insert the record into the Table
try {
    Set-AzTableRecord -Record $TableRecord -Headers $Headers | Out-Null
} catch {
    $ErrorMessage = "Error setting record into Azure Table Storage: $_"
    Write-Error $ErrorMessage
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = $ErrorMessage
    })
    exit
}
#endregion SetRecord

# Return 200 OK if the record was inserted successfully
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
