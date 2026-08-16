$ErrorActionPreference = 'Stop'

# Stop only Apache processes started from this repack.  Other local Apache
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
    Write-Host "Nostalgia-Webserver beendet ($stopped Apache-Prozess(e))."
} else {
    Write-Host 'Nostalgia-Webserver war nicht aktiv.'
}
