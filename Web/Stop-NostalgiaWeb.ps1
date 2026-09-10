$ErrorActionPreference = 'Stop'

# Stop only Apache processes started from this Nostalgia folder. Other local Apache
# installations remain untouched.
$apachePath = Join-Path $PSScriptRoot 'Apache\bin\httpd.exe'
$stopped = 0

Get-CimInstance Win32_Process -Filter "Name = 'httpd.exe'" |
    Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $apachePath } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force
        $stopped++
    }

if ($stopped -gt 0) {
    Write-Host "Nostalgia web server stopped ($stopped Apache process(es))."
} else {
    Write-Host 'The Nostalgia web server was not running.'
}
