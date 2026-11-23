# Starts the web application on Windows without Apache:   powershell -ExecutionPolicy Bypass -File sources\dev\run-web.ps1 -Database chadji22
# Needs PHP >= 8.1 with the sqlsrv and fileinfo extensions. The password is asked for here and lives only in this
# process: it is not written to a file and it is not in the command history.
param(
    [Parameter(Mandatory = $true)][string]$Database,
    [string]$User = $Database,
    [string]$Server = 'mssql.cs.ucy.ac.cy',
    [int]$Port = 8080
)
$php = Get-Command php -ErrorAction SilentlyContinue
if (-not $php) { throw 'php was not found. Open a new terminal after installing PHP.' }

$secure = Read-Host "Password of $User" -AsSecureString
$env:DB_PASS = (New-Object System.Net.NetworkCredential('', $secure)).Password
$env:DB_HOST = $Server; $env:DB_NAME = $Database; $env:DB_USER = $User; $env:APP_DEBUG = '1'
try {
    Write-Host "http://localhost:$Port   (Ctrl+C to stop)"
    # startup warnings printed into the page would break the headers (for example after a too large upload)
    & $php.Source -d display_errors=0 -d display_startup_errors=0 -S "localhost:$Port" -t (Join-Path $PSScriptRoot '..\public')
} finally {
    Remove-Item Env:DB_PASS -ErrorAction SilentlyContinue
}
