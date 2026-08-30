param(
    [string]$LauncherPath = (Join-Path $PSScriptRoot '..\..\Nostalgia\NostalgiaServer.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NostalgiaTestNativeMethods
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr window);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "GetClassLongPtr")]
    public static extern IntPtr GetClassLongPtr(IntPtr window, int index);
}
'@

$launcherFullPath = [IO.Path]::GetFullPath($LauncherPath)
$openWebsiteButtonName = 'Webseite ' + [char]0x00F6 + 'ffnen'
$openAddOnsButtonName = 'AddOns ' + [char]0x00F6 + 'ffnen'
$closeButtonName = 'Schlie' + [char]0x00DF + 'en'
$nostalgiaDirectory = Split-Path -Parent $launcherFullPath
$wowExecutable = [IO.Path]::GetFullPath((Join-Path $nostalgiaDirectory 'client\WoW.exe'))
$addOnsDirectory = [IO.Path]::GetFullPath((Join-Path $nostalgiaDirectory 'client\Interface\AddOns'))
$ownedExecutables = @{
    mariadbd = [IO.Path]::GetFullPath((Join-Path $nostalgiaDirectory 'MariaDB\bin\mariadbd.exe'))
    realmd    = [IO.Path]::GetFullPath((Join-Path $nostalgiaDirectory 'Server\realmd.exe'))
    mangosd   = [IO.Path]::GetFullPath((Join-Path $nostalgiaDirectory 'Server\mangosd.exe'))
    httpd     = [IO.Path]::GetFullPath((Join-Path $nostalgiaDirectory 'Web\Apache\bin\httpd.exe'))
}

function Write-TestResult([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $state = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Output ("[{0}] {1}{2}" -f $state, $Name, $(if ($Detail) { ": $Detail" } else { '' }))
    if (-not $Passed) { throw "Test failed: $Name. $Detail" }
}

function Get-OwnedProcess([string]$Name) {
    @(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object {
        try { [IO.Path]::GetFullPath($_.Path) -eq $ownedExecutables[$Name] } catch { $false }
    })
}

function Wait-Until([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$Description) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 300
    } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "Timeout while waiting for $Description"
}

function Test-Port([int]$Port) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        return $task.Wait(350) -and $client.Connected
    } catch { return $false } finally { $client.Dispose() }
}

function Get-MainAutomationElement([Diagnostics.Process]$Process) {
    Wait-Until { $Process.Refresh(); $Process.MainWindowHandle -ne 0 } 20 'launcher window'
    [Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
}

function Get-Button([Windows.Automation.AutomationElement]$Window, [string]$Name) {
    $condition = [Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty,
            [Windows.Automation.ControlType]::Button),
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::NameProperty,
            $Name))
    $Window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
}

function Invoke-Button([Windows.Automation.AutomationElement]$Window, [string]$Name) {
    $button = Get-Button $Window $Name
    if ($null -eq $button) { throw "Button '$Name' not found" }
    Wait-Until { $button.Current.IsEnabled } 300 "enabled button '$Name'"
    $handle = [IntPtr]$button.Current.NativeWindowHandle
    if ($handle -eq [IntPtr]::Zero -or
        -not [NostalgiaTestNativeMethods]::PostMessage($handle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)) {
        throw "Could not post BM_CLICK to button '$Name'"
    }
}

function Get-OwnedWowProcess {
    @(Get-Process -Name 'wow' -ErrorAction SilentlyContinue | Where-Object {
        try { [IO.Path]::GetFullPath($_.Path) -eq $wowExecutable } catch { $false }
    })
}

function Wait-ForServerRunning {
    Wait-Until { (Get-OwnedProcess 'mariadbd').Count -eq 1 } 45 'MariaDB process'
    Wait-Until { (Get-OwnedProcess 'realmd').Count -eq 1 } 60 'realmd process'
    Wait-Until { (Get-OwnedProcess 'mangosd').Count -eq 1 } 90 'mangosd process'
    Wait-Until { (Get-OwnedProcess 'httpd').Count -ge 1 } 45 'Apache process'
    Wait-Until { (Test-Port 3307) -and (Test-Port 3724) -and (Test-Port 8085) -and (Test-Port 8080) } 300 'all server ports'
}

function Wait-ForServerStopped {
    Wait-Until {
        (Get-OwnedProcess 'mariadbd').Count -eq 0 -and
        (Get-OwnedProcess 'realmd').Count -eq 0 -and
        (Get-OwnedProcess 'mangosd').Count -eq 0 -and
        (Get-OwnedProcess 'httpd').Count -eq 0
    } 180 'all managed processes to stop'
}

foreach ($name in $ownedExecutables.Keys) {
    if ((Get-OwnedProcess $name).Count -ne 0) {
        throw "Refusing to test: an owned $name process is already running."
    }
}
if ((Get-OwnedWowProcess).Count -ne 0) {
    throw 'Refusing to test: the Nostalgia WoW client is already running.'
}

$launcher = $null
try {
    $launcher = Start-Process -FilePath $launcherFullPath -PassThru
    $window = Get-MainAutomationElement $launcher
    $windowIcon = [NostalgiaTestNativeMethods]::SendMessage($launcher.MainWindowHandle, 0x007F, [IntPtr]2, [IntPtr]::Zero)
    if ($windowIcon -eq [IntPtr]::Zero) {
        $windowIcon = [NostalgiaTestNativeMethods]::GetClassLongPtr($launcher.MainWindowHandle, -34)
    }
    Write-TestResult 'Launcher- und Taskleisten-Icon gesetzt' ($windowIcon -ne [IntPtr]::Zero)

    $wowButton = Get-Button $window 'WoW starten'
    Write-TestResult 'WoW starten bei gestopptem Server deaktiviert' ($null -ne $wowButton -and -not $wowButton.Current.IsEnabled)

    Invoke-Button $window 'Tools / Voraussetzungen'
    $toolsWindow = $null
    Wait-Until {
        $processCondition = [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ProcessIdProperty,
            $launcher.Id)
        $nameCondition = [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::NameProperty,
            'Tools / Voraussetzungen')
        $toolsWindow = [Windows.Automation.AutomationElement]::RootElement.FindFirst(
            [Windows.Automation.TreeScope]::Children,
            [Windows.Automation.AndCondition]::new($processCondition, $nameCondition))
        $null -ne $toolsWindow
    } 10 'tools/prerequisites dialog'
    $installedButton = Get-Button $toolsWindow 'Bereits installiert'
    $vcInstallers = @(Get-ChildItem -LiteralPath (Join-Path $nostalgiaDirectory 'tools') -Filter 'VC_redist.*.exe' -File)
    Write-TestResult 'Vorhandene VC++-Installer sinnvoll erkannt' (
        $vcInstallers.Count -eq 2 -and
        $null -ne $installedButton -and
        -not $installedButton.Current.IsEnabled)
    Invoke-Button $toolsWindow $closeButtonName

    $explorerHandlesBefore = @(Get-Process explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -ExpandProperty MainWindowHandle)
    Invoke-Button $window $openAddOnsButtonName
    $addOnsExplorer = $null
    Wait-Until {
        $addOnsExplorer = @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -notin $explorerHandlesBefore -and
            $_.MainWindowTitle -like "*$addOnsDirectory*"
        }) | Select-Object -First 1
        $null -ne $addOnsExplorer
    } 15 'AddOns Explorer window'
    Write-TestResult 'AddOns öffnen verwendet den richtigen relativen Ordner' ($null -ne $addOnsExplorer)
    [NostalgiaTestNativeMethods]::PostMessage([IntPtr]$addOnsExplorer.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null

    $browserNames = @('msedge', 'chrome', 'firefox', 'brave', 'opera', 'iexplore')
    $browserProcessesBeforeStart = @(Get-Process -Name $browserNames -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -ExpandProperty Id)

    Invoke-Button $window 'Server starten'
    Wait-ForServerRunning
    Write-TestResult 'Normaler Start' $true
    $wowButton = Get-Button $window 'WoW starten'
    Wait-Until { $wowButton.Current.IsEnabled } 10 'enabled WoW button'
    Write-TestResult 'WoW starten nach Serverstart aktiviert' $wowButton.Current.IsEnabled
    $childrenHaveNoWindows = @('mariadbd', 'realmd', 'mangosd', 'httpd') | ForEach-Object {
        @(Get-OwnedProcess $_) | ForEach-Object {
            $_.Refresh()
            $_.MainWindowHandle -eq 0
        }
    }
    Write-TestResult 'Keine sichtbaren Kindprozess-Fenster' (-not ($childrenHaveNoWindows -contains $false))
    $browserProcessesAfterStart = @(Get-Process -Name $browserNames -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -ExpandProperty Id)
    $newBrowserProcesses = @($browserProcessesAfterStart | Where-Object { $_ -notin $browserProcessesBeforeStart })
    Write-TestResult 'Browser öffnet beim Serverstart nicht automatisch' ($newBrowserProcesses.Count -eq 0) ($newBrowserProcesses -join ', ')
    $startCondition = [Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty,
            [Windows.Automation.ControlType]::Button),
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::NameProperty,
            'Server starten'))
    $startButton = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $startCondition)
    Write-TestResult 'Komponenten-Doppelstart per UI gesperrt' (-not $startButton.Current.IsEnabled)
    $webButtonCondition = [Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty,
            [Windows.Automation.ControlType]::Button),
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::NameProperty,
            $openWebsiteButtonName))
    $webButton = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $webButtonCondition)
    $webResponse = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/' -UseBasicParsing -TimeoutSec 10
    Write-TestResult 'Webseite öffnen vorhanden und Webziel antwortet' ($null -ne $webButton -and $webResponse.StatusCode -eq 200)

    Invoke-Button $window 'WoW starten'
    Wait-Until { (Get-OwnedWowProcess).Count -ge 1 } 30 'Nostalgia WoW process'
    Write-TestResult 'WoW starten öffnet client\WoW.exe' ((Get-OwnedWowProcess).Count -ge 1)

    $second = Start-Process -FilePath $launcherFullPath -PassThru
    Write-TestResult 'Launcher-Doppelstart verhindert' ($second.WaitForExit(10000) -and -not $launcher.HasExited)

    Invoke-Button $window 'Server beenden'
    Wait-ForServerStopped
    Write-TestResult 'Normaler kontrollierter Stop' $true
    Write-TestResult 'Server-Stop beendet WoW nicht' ((Get-OwnedWowProcess).Count -ge 1)
    Get-OwnedWowProcess | Stop-Process -Force
    Wait-Until { (Get-OwnedWowProcess).Count -eq 0 } 15 'test WoW cleanup'

    Invoke-Button $window 'Server starten'
    Wait-ForServerRunning
    Write-TestResult 'Erneuter Start nach Stop' $true

    $world = @(Get-OwnedProcess 'mangosd')[0]
    Stop-Process -Id $world.Id -Force
    Wait-Until { (Get-OwnedProcess 'mangosd').Count -eq 0 } 20 'simulated mangosd crash'
    $unexpectedCondition = [Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty,
            [Windows.Automation.ControlType]::Text),
        [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::NameProperty,
            'Unerwartet beendet'))
    Wait-Until {
        $null -ne $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $unexpectedCondition)
    } 10 'unexpected world status'
    Write-TestResult 'Unerwarteter mangosd-Absturz erkannt' (-not $launcher.HasExited)
    Invoke-Button $window 'Server beenden'
    Wait-ForServerStopped

    Invoke-Button $window 'Server starten'
    Wait-ForServerRunning
    $launcher.Refresh()
    [void]$launcher.CloseMainWindow()
    Write-TestResult 'X wartet auf kontrollierten Shutdown' ($launcher.WaitForExit(180000))
    Wait-ForServerStopped
    $launcher = $null

    $missingDirectory = Join-Path $PSScriptRoot ('missing-layout-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $missingDirectory | Out-Null
    $missingLauncher = Join-Path $missingDirectory 'NostalgiaServer.exe'
    Copy-Item -LiteralPath $launcherFullPath -Destination $missingLauncher
    $missingProcess = Start-Process -FilePath $missingLauncher -PassThru
    $missingWindow = Get-MainAutomationElement $missingProcess
    Invoke-Button $missingWindow 'Server starten'
    $documentCondition = [Windows.Automation.PropertyCondition]::new(
        [Windows.Automation.AutomationElement]::ControlTypeProperty,
        [Windows.Automation.ControlType]::Document)
    $document = $missingWindow.FindFirst([Windows.Automation.TreeScope]::Descendants, $documentCondition)
    $documentValue = $document.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
    $reportedText = ''
    Wait-Until {
        $documentValue.Current.Value -match 'Datei nicht gefunden'
    } 10 'missing-file error text'
    $reportedText = $documentValue.Current.Value
    Write-TestResult 'Fehlende EXE verständlich gemeldet' ($reportedText -match 'MariaDB\\bin\\mariadbd.exe') $reportedText

    $dialog = $null
    try {
        Wait-Until {
        $processCondition = [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ProcessIdProperty,
            $missingProcess.Id)
        $windows = [Windows.Automation.AutomationElement]::RootElement.FindAll(
            [Windows.Automation.TreeScope]::Children,
            $processCondition)
        $dialog = @($windows | Where-Object { $_.Current.ClassName -eq '#32770' }) | Select-Object -First 1
        $null -ne $dialog
        } 3 'missing-file error dialog'
    } catch {
        # The log is the authoritative assertion. Some headless Windows
        # sessions do not expose native message boxes through UI Automation.
    }
    if ($null -eq $dialog) {
        $processCondition = [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ProcessIdProperty,
            $missingProcess.Id)
        $windows = [Windows.Automation.AutomationElement]::RootElement.FindAll(
            [Windows.Automation.TreeScope]::Children,
            $processCondition)
        $dialog = @($windows | Where-Object { $_.Current.ClassName -eq '#32770' }) | Select-Object -First 1
    }
    if ($null -ne $dialog) { Invoke-Button $dialog 'OK' }
    $missingProcess.CloseMainWindow() | Out-Null
    if (-not $missingProcess.WaitForExit(10000)) {
        Stop-Process -Id $missingProcess.Id -Force
        $missingProcess.WaitForExit(5000) | Out-Null
    }
    Remove-Item -LiteralPath $missingLauncher
    Remove-Item -LiteralPath $missingDirectory
} finally {
    if ($null -ne $launcher -and -not $launcher.HasExited) {
        [void]$launcher.CloseMainWindow()
        [void]$launcher.WaitForExit(180000)
    }
}
