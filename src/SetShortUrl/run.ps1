using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Parse short url id from the request route
$ShortUrlId = $Request.Params.ShortUrlId

# Extract original url from body or query parameter
$OriginalUrl = if ($Request.Body.url) { $Request.Body.url } else { $Request.Query.url }
$ForceUpdate = if ($Request.Body.force) { $Request.Body.force } else { $Request.Query.force }
$TrackClicks = if ($Request.Body.trackClicks) { $Request.Body.trackClicks } else { $Request.Query.trackClicks }

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

# Get Azure Table Storage request headers
try {
    Write-Verbose 'Get Azure Table Storage request headers'
    $Headers = Get-AzTableHeaders -RowKey $ShortUrlId -Verbose
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

        if ([string]$ShortUrlRecord.TrackClicks -ne $TrackClicks) {
            Write-Information "TrackClicks changed from [$($ShortUrlRecord.TrackClicks)] to [$TrackClicks]"
            if ($TrackClicks -eq 'true') {
                if (-not $ShortUrlRecord.Clicks) {
                    Add-Member -InputObject $ShortUrlRecord -MemberType NoteProperty -Name 'Clicks' -Value 0
                }
                if (-not $ShortUrlRecord.TrackClicks) {
                    Add-Member -InputObject $ShortUrlRecord -MemberType NoteProperty -Name 'TrackClicks' -Value $true
                } else {
                    $ShortUrlRecord.TrackClicks = $true
                }
                Write-Information "Enabled click tracking for [$ShortUrlId]"
            } else {
                $ShortUrlRecord.TrackClicks = $false
                Write-Information "Disabled click tracking for [$ShortUrlId]"
            }
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
        Body      = $ErrorMessage
    })
    exit
}

# Return 200 OK if the record was inserted successfully
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
