# Create a URL
Invoke-RestMethod -Method Post 'http://localhost:7071/hi?url=https://google.com'

# Test the URL
Invoke-RestMethod -Method Get 'http://localhost:7071/hi' | Out-Null

# Update the URL
# Expected Response: 409 Conflict
Invoke-RestMethod -Method Post 'http://localhost:7071/hi?url=https://microsoft.com'

# Update the URL (force)
Invoke-RestMethod -Method Post 'http://localhost:7071/hi?url=https://microsoft.com&force=true'

# Test the new URL
Invoke-RestMethod -Method Get 'http://localhost:7071/hi' | Out-Null

# Update the URL (force, track clicks)
Invoke-RestMethod -Method Post 'http://localhost:7071/hi?url=https://bing.com&force=true&trackClicks=true'

# Test the new URL (track a click)
Invoke-RestMethod -Method Get 'http://localhost:7071/hi' | Out-Null

# Update the URL (disable track clicks)
# Expected Response: 409 Conflict
Invoke-RestMethod -Method Post 'http://localhost:7071/hi?trackClicks=false'

# Update the URL (force, disable track clicks)
Invoke-RestMethod -Method Post 'http://localhost:7071/hi?force=true&trackClicks=false'

# Test the new URL (do not track click)
Invoke-RestMethod -Method Get 'http://localhost:7071/hi' | Out-Null

# Delete the URL
Invoke-RestMethod -Method Delete 'http://localhost:7071/hi'