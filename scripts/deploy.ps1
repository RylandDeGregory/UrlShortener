$output = azd env get-values

foreach ($line in $output) {
    if (-not $line) {
        break
    }
    $name = $line.Split('=')[0]
    $value = $line.Split('=')[1].Trim('"')
    Set-Item -Path "env:\$name" -Value $value
}

Write-Host 'Environment variables set.'

$tools = @('az', 'func')

foreach ($tool in $tools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "Error: $tool command line tool is not available, check pre-requisites in README.md"
        exit 1
    }
}

Set-Location ./src
func azure functionapp publish $env:FUNCTION_APP_NAME --powershell

Write-Host 'Deployment completed.'
Set-Location ../