using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Net.Sockets;

namespace NostalgiaServer;

internal sealed class ServerManager : IDisposable
{
    private readonly LauncherLayout _layout;
    private readonly SemaphoreSlim _operationLock = new(1, 1);
    private readonly Dictionary<ServerComponent, ComponentState> _states = new()
    {
        [ServerComponent.Database] = ComponentState.Stopped,
        [ServerComponent.Realm] = ComponentState.Stopped,
        [ServerComponent.World] = ComponentState.Stopped,
        [ServerComponent.Web] = ComponentState.Stopped
    };

    private HiddenChildProcess? _database;
    private HiddenChildProcess? _realm;
    private HiddenChildProcess? _world;
    private HiddenChildProcess? _web;
    private volatile bool _intentionalShutdown;
    private bool _disposed;
    private CancellationTokenSource? _pipeCancellation;

    public ServerManager(LauncherLayout layout)
    {
        _layout = layout;
    }

    public event Action<StatusChangedEventArgs>? StatusChanged;
    public event Action<string>? LogReceived;

    public bool IsBusy { get; private set; }
    public bool HasManagedProcesses => IsAlive(_database) || IsAlive(_realm) || IsAlive(_world) || IsAlive(_web) || HasOwnedWebProcesses();
    public IReadOnlyDictionary<ServerComponent, ComponentState> States => _states;

    public async Task StartAsync()
    {
        await _operationLock.WaitAsync().ConfigureAwait(false);
        IsBusy = true;
        _intentionalShutdown = false;
        try
        {
            if (HasManagedProcesses)
                throw new LauncherException("Der Server wurde bereits gestartet.");

            _layout.Validate();
            EnsureNoExternalServerProcesses();
            Log("Launcher", "Starte die Nostalgia-Serverumgebung …");

            await StartDatabaseAsync().ConfigureAwait(false);
            await StartRealmAsync().ConfigureAwait(false);
            await StartWorldAsync().ConfigureAwait(false);
            await StartWebAsync().ConfigureAwait(false);
            Log("Launcher", "Alle Serverkomponenten laufen.");
            
            _pipeCancellation = new CancellationTokenSource();
            _ = StartConsolePipeServerAsync(_pipeCancellation.Token);
        }
        catch
        {
            Log("Launcher", "Der Start ist fehlgeschlagen. Bereits gestartete Komponenten werden beendet.");
            await StopCoreAsync().ConfigureAwait(false);
            throw;
        }
        finally
        {
            IsBusy = false;
            _operationLock.Release();
        }
    }

    public async Task StopAsync()
    {
        await _operationLock.WaitAsync().ConfigureAwait(false);
        IsBusy = true;
        try
        {
            await StopCoreAsync().ConfigureAwait(false);
        }
        finally
        {
            IsBusy = false;
            _operationLock.Release();
        }
    }

    public async Task StartWorldStandaloneAsync()
    {
        await _operationLock.WaitAsync().ConfigureAwait(false);
        IsBusy = true;
        try
        {
            if (_states[ServerComponent.Database] != ComponentState.Running || _states[ServerComponent.Realm] != ComponentState.Running)
                throw new LauncherException("Der Worldserver kann nicht gestartet werden, weil die Datenbank oder der Realm nicht laeuft.");

            Log("Launcher", "Manueller Start des Worldservers …");
            await StartWorldAsync().ConfigureAwait(false);
        }
        finally
        {
            IsBusy = false;
            _operationLock.Release();
        }
    }

    public async Task RestartWorldStandaloneAsync()
    {
        await _operationLock.WaitAsync().ConfigureAwait(false);
        IsBusy = true;
        try
        {
            if (_states[ServerComponent.Database] != ComponentState.Running || _states[ServerComponent.Realm] != ComponentState.Running)
                throw new LauncherException("Der Worldserver kann nicht neu gestartet werden, weil die Datenbank oder der Realm nicht laeuft.");

            Log("Launcher", "Manueller Neustart des Worldservers …");
            await StopWorldAsync().ConfigureAwait(false);
            
            // Kleine Pause um sicherzugehen, dass Ports wirklich freigegeben sind
            await Task.Delay(1000).ConfigureAwait(false);
            
            await StartWorldAsync().ConfigureAwait(false);
        }
        finally
        {
            IsBusy = false;
            _operationLock.Release();
        }
    }

    private async Task StartDatabaseAsync()
    {
        SetState(ServerComponent.Database, ComponentState.Starting);
        EnsurePortAvailable(3307, "MariaDB");
        Log("Database", "Starte MariaDB …");

        try
        {
            _database = HiddenChildProcess.Start(
                _layout.DatabaseExecutable,
                "--defaults-file=my.ini --console",
                _layout.DatabaseDirectory);
            AttachProcessEvents(ServerComponent.Database, _database, includeNormalOutput: false);
        }
        catch (Exception exception)
        {
            SetState(ServerComponent.Database, ComponentState.Error, exception.Message);
            throw FriendlyStartException("MariaDB", _layout.DatabaseExecutable, exception);
        }

        await WaitForDatabaseReadyAsync(_database, TimeSpan.FromSeconds(35)).ConfigureAwait(false);
        SetState(ServerComponent.Database, ComponentState.Running);
        Log("Database", "MariaDB ist bereit (Port 3307).");
    }

    private async Task StartRealmAsync()
    {
        SetState(ServerComponent.Realm, ComponentState.Starting);
        EnsurePortAvailable(3724, "Realmserver");
        Log("Realm", "Starte realmd.exe …");

        try
        {
            _realm = HiddenChildProcess.Start(_layout.RealmExecutable, string.Empty, _layout.ServerDirectory);
            AttachProcessEvents(ServerComponent.Realm, _realm, includeNormalOutput: true);
        }
        catch (Exception exception)
        {
            SetState(ServerComponent.Realm, ComponentState.Error, exception.Message);
            throw FriendlyStartException("Realmserver", _layout.RealmExecutable, exception);
        }

        await WaitForPortAsync(ServerComponent.Realm, _realm, 3724, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
        SetState(ServerComponent.Realm, ComponentState.Running);
        Log("Realm", "Realmserver ist bereit (Port 3724).");
    }

    private async Task StartWorldAsync()
    {
        SetState(ServerComponent.World, ComponentState.Starting);
        EnsurePortAvailable(8085, "Worldserver");
        Log("World", "Starte mangosd.exe …");

        try
        {
            _world = HiddenChildProcess.Start(_layout.WorldExecutable, string.Empty, _layout.ServerDirectory);
            AttachProcessEvents(ServerComponent.World, _world, includeNormalOutput: true);
        }
        catch (Exception exception)
        {
            SetState(ServerComponent.World, ComponentState.Error, exception.Message);
            throw FriendlyStartException("Worldserver", _layout.WorldExecutable, exception);
        }

        await WaitForPortAsync(ServerComponent.World, _world, 8085, TimeSpan.FromMinutes(4)).ConfigureAwait(false);
        SetState(ServerComponent.World, ComponentState.Running);
        Log("World", "Worldserver ist bereit (Port 8085).");
    }

    private async Task StartWebAsync()
    {
        SetState(ServerComponent.Web, ComponentState.Starting);
        EnsurePortAvailable(8080, "Webserver");
        EnsureNoOwnedWebProcesses();
        Log("Web", "Prüfe die Apache-Konfiguration …");

        try
        {
            await ValidateWebConfigurationAsync().ConfigureAwait(false);
            string arguments = $"-d \"{_layout.ApacheDirectory}\" -f \"{_layout.WebConfiguration}\"";
            _web = HiddenChildProcess.Start(_layout.WebExecutable, arguments, _layout.ApacheDirectory, createProcessGroup: false);
            AttachProcessEvents(ServerComponent.Web, _web, includeNormalOutput: true);
        }
        catch (Exception exception)
        {
            SetState(ServerComponent.Web, ComponentState.Error, exception.Message);
            throw FriendlyStartException("Webserver", _layout.WebExecutable, exception);
        }

        await WaitForPortAsync(ServerComponent.Web, _web, 8080, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
        SetState(ServerComponent.Web, ComponentState.Running);
        Log("Web", $"Webserver ist bereit ({_layout.WebAddress}).");
    }

    private async Task StopCoreAsync()
    {
        _intentionalShutdown = true;
        _pipeCancellation?.Cancel();
        
        try
        {
            if (!HasManagedProcesses)
            {
                SetAllStopped();
                Log("Launcher", "Alle Serverkomponenten sind bereits gestoppt.");
                return;
            }

            Log("Launcher", "Beende die Serverkomponenten kontrolliert …");
            await StopWorldAsync().ConfigureAwait(false);
            await StopRealmAsync().ConfigureAwait(false);
            await StopWebAsync().ConfigureAwait(false);
            await StopDatabaseAsync().ConfigureAwait(false);
            Log("Launcher", "Alle Serverkomponenten wurden beendet.");
        }
        finally
        {
            DisposeExitedProcesses();
            _intentionalShutdown = false;
        }
    }

    private async Task StartConsolePipeServerAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested && !_disposed)
        {
            try
            {
                using var pipeServer = new NamedPipeServerStream("nostalgia_console", PipeDirection.In, 1, PipeTransmissionMode.Message, PipeOptions.Asynchronous);
                await pipeServer.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
                
                using var reader = new StreamReader(pipeServer);
                string? command = await reader.ReadLineAsync().ConfigureAwait(false);
                
                if (!string.IsNullOrWhiteSpace(command) && IsAlive(_world))
                {
                    Log("ConsolePipe", $"Führe Befehl aus: {command}");
                    await _world!.WriteLineAsync(command).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception)
            {
                if (!cancellationToken.IsCancellationRequested)
                    await Task.Delay(500, cancellationToken).ConfigureAwait(false);
            }
        }
    }

    private async Task StopWorldAsync()
    {
        HiddenChildProcess? process = _world;
        if (!IsAlive(process))
        {
            SetState(ServerComponent.World, ComponentState.Stopped);
            return;
        }

        SetState(ServerComponent.World, ComponentState.Stopping);
        Log("World", "Sende „server shutdown 0“ an die Worldserver-Konsole …");
        try
        {
            await process!.WriteLineAsync("server shutdown 0").ConfigureAwait(false);
            // vMaNGOS blocks its Windows CLI thread in fgets(stdin). With a pipe
            // there is no console input buffer for its final WriteConsoleInput
            // wake-up, so EOF is the correct way to release that thread after
            // the complete shutdown command has been flushed.
            process.CloseStandardInput();
            if (!await process.WaitForExitAsync(TimeSpan.FromSeconds(90)).ConfigureAwait(false))
            {
                Log("World", "Der Worldserver reagiert nicht; sende CTRL+BREAK als zweiten kontrollierten Versuch.");
                bool signalSent = await process.SendCtrlBreakAsync().ConfigureAwait(false);
                if (!signalSent)
                    Log("World", "CTRL+BREAK konnte nicht zugestellt werden; verwende nach dem Timeout den Fallback.");
            }

            if (!await process.WaitForExitAsync(TimeSpan.FromSeconds(25)).ConfigureAwait(false))
                await ForceStopAsync(ServerComponent.World, process).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Log("World", $"Fehler beim kontrollierten Beenden: {exception.Message}");
            await ForceStopAsync(ServerComponent.World, process!).ConfigureAwait(false);
        }
        finally
        {
            SetState(ServerComponent.World, ComponentState.Stopped);
        }
    }

    private async Task StopRealmAsync()
    {
        HiddenChildProcess? process = _realm;
        if (!IsAlive(process))
        {
            SetState(ServerComponent.Realm, ComponentState.Stopped);
            return;
        }

        SetState(ServerComponent.Realm, ComponentState.Stopping);
        Log("Realm", "Sende CTRL+BREAK für den vorgesehenen realmd-Signalhandler …");
        try
        {
            bool signalSent = await process!.SendCtrlBreakAsync().ConfigureAwait(false);
            if (!signalSent)
                Log("Realm", "CTRL+BREAK konnte nicht zugestellt werden; verwende den Fallback.");

            if (!signalSent || !await process.WaitForExitAsync(TimeSpan.FromSeconds(30)).ConfigureAwait(false))
                await ForceStopAsync(ServerComponent.Realm, process).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Log("Realm", $"Fehler beim kontrollierten Beenden: {exception.Message}");
            await ForceStopAsync(ServerComponent.Realm, process!).ConfigureAwait(false);
        }
        finally
        {
            SetState(ServerComponent.Realm, ComponentState.Stopped);
        }
    }

    private async Task StopWebAsync()
    {
        if (!IsAlive(_web) && !HasOwnedWebProcesses())
        {
            SetState(ServerComponent.Web, ComponentState.Stopped);
            return;
        }

        SetState(ServerComponent.Web, ComponentState.Stopping);
        Log("Web", "Sende CTRL+C an den Apache-Konsolenhandler …");
        try
        {
            bool stopped = false;
            if (IsAlive(_web))
            {
                bool signalSent = await _web!.SendCtrlCAsync().ConfigureAwait(false);
                if (signalSent)
                    stopped = await WaitForWebExitAsync(TimeSpan.FromSeconds(20)).ConfigureAwait(false);
            }

            if (!stopped)
            {
                Log("Web", "Apache reagiert nicht auf CTRL+C; verwende httpd -k shutdown als zweiten Versuch.");
                (int exitCode, string error) = await RunApacheCommandAsync(
                    TimeSpan.FromSeconds(15),
                    "-k", "shutdown",
                    "-d", _layout.ApacheDirectory,
                    "-f", _layout.WebConfiguration).ConfigureAwait(false);

                if (exitCode != 0)
                    Log("Web", string.IsNullOrWhiteSpace(error) ? $"Apache-Shutdown endete mit Code {exitCode}." : error);
                stopped = await WaitForWebExitAsync(TimeSpan.FromSeconds(20)).ConfigureAwait(false);
            }

            if (!stopped)
                await ForceStopWebAsync().ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Log("Web", $"Fehler beim kontrollierten Beenden: {exception.Message}");
            await ForceStopWebAsync().ConfigureAwait(false);
        }
        finally
        {
            SetState(ServerComponent.Web, ComponentState.Stopped);
        }
    }

    private async Task StopDatabaseAsync()
    {
        HiddenChildProcess? process = _database;
        if (!IsAlive(process))
        {
            SetState(ServerComponent.Database, ComponentState.Stopped);
            return;
        }

        SetState(ServerComponent.Database, ComponentState.Stopping);
        Log("Database", "Fordere MariaDB über mariadb-admin shutdown zum Herunterfahren auf …");
        try
        {
            await RunDatabaseAdminShutdownAsync().ConfigureAwait(false);
            if (!await process!.WaitForExitAsync(TimeSpan.FromSeconds(35)).ConfigureAwait(false))
                await ForceStopAsync(ServerComponent.Database, process).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Log("Database", $"MariaDB-Shutdown meldet einen Fehler: {exception.Message}");
            if (IsAlive(process))
            {
                Log("Database", "Versuche CTRL+BREAK als zweiten kontrollierten Shutdown-Weg …");
                await process!.SendCtrlBreakAsync().ConfigureAwait(false);
                if (!await process.WaitForExitAsync(TimeSpan.FromSeconds(20)).ConfigureAwait(false))
                    await ForceStopAsync(ServerComponent.Database, process).ConfigureAwait(false);
            }
        }
        finally
        {
            SetState(ServerComponent.Database, ComponentState.Stopped);
        }
    }

    private async Task ValidateWebConfigurationAsync()
    {
        (int exitCode, string error) = await RunApacheCommandAsync(
            TimeSpan.FromSeconds(20),
            "-t",
            "-d", _layout.ApacheDirectory,
            "-f", _layout.WebConfiguration).ConfigureAwait(false);

        if (exitCode != 0)
            throw new LauncherException(string.IsNullOrWhiteSpace(error) ? $"Die Apache-Konfiguration ist ungültig (Code {exitCode})." : error);
    }

    private async Task<(int ExitCode, string Error)> RunApacheCommandAsync(TimeSpan timeout, params string[] arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = _layout.WebExecutable,
            WorkingDirectory = _layout.ApacheDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (string argument in arguments)
            startInfo.ArgumentList.Add(argument);

        using Process process = Process.Start(startInfo)
            ?? throw new LauncherException("Apache konnte nicht gestartet werden.");
        Task<string> outputTask = process.StandardOutput.ReadToEndAsync();
        Task<string> errorTask = process.StandardError.ReadToEndAsync();
        using var commandTimeout = new CancellationTokenSource(timeout);
        try
        {
            await process.WaitForExitAsync(commandTimeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); }
            catch { }
            throw new LauncherException("Apache hat nicht innerhalb des vorgesehenen Timeouts geantwortet.");
        }

        string output = await outputTask.ConfigureAwait(false);
        string error = await errorTask.ConfigureAwait(false);
        string message = string.Join(Environment.NewLine, new[] { error.Trim(), output.Trim() }.Where(value => value.Length > 0));
        return (process.ExitCode, message);
    }

    private async Task<bool> WaitForWebExitAsync(TimeSpan timeout)
    {
        Stopwatch stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < timeout)
        {
            if (!IsAlive(_web) && !HasOwnedWebProcesses())
                return true;
            await Task.Delay(250).ConfigureAwait(false);
        }
        return !IsAlive(_web) && !HasOwnedWebProcesses();
    }

    private async Task ForceStopWebAsync()
    {
        Log("Web", "Shutdown-Timeout erreicht; verbleibende Nostalgia-Apache-Prozesse werden beendet.");
        if (IsAlive(_web))
        {
            try { _web!.Kill(); }
            catch { }
        }

        await Task.Delay(200).ConfigureAwait(false);
        foreach (Process process in GetOwnedWebProcesses())
        {
            using (process)
            {
                try
                {
                    if (!process.HasExited)
                        process.Kill(entireProcessTree: true);
                }
                catch (InvalidOperationException)
                {
                }
            }
        }
        await WaitForWebExitAsync(TimeSpan.FromSeconds(10)).ConfigureAwait(false);
    }

    private async Task RunDatabaseAdminShutdownAsync()
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = _layout.DatabaseAdminExecutable,
            WorkingDirectory = _layout.DatabaseDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        AddDatabaseAdminConnectionArguments(startInfo);
        startInfo.ArgumentList.Add("shutdown");

        using Process admin = Process.Start(startInfo)
            ?? throw new LauncherException("mariadb-admin konnte nicht gestartet werden.");
        string error = await admin.StandardError.ReadToEndAsync().ConfigureAwait(false);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await admin.WaitForExitAsync(timeout.Token).ConfigureAwait(false);
        if (admin.ExitCode != 0)
            throw new LauncherException(string.IsNullOrWhiteSpace(error) ? $"mariadb-admin endete mit Code {admin.ExitCode}." : error.Trim());
    }

    private static void AddDatabaseAdminConnectionArguments(ProcessStartInfo startInfo)
    {
        startInfo.ArgumentList.Add("--protocol=tcp");
        startInfo.ArgumentList.Add("--host=127.0.0.1");
        startInfo.ArgumentList.Add("--port=3307");
        startInfo.ArgumentList.Add("--user=vmangos");
        startInfo.ArgumentList.Add("--password=vmangos");
    }

    private async Task ForceStopAsync(ServerComponent component, HiddenChildProcess process)
    {
        Log(ComponentName(component), "Shutdown-Timeout erreicht; Prozess wird jetzt als letzter Fallback beendet.");
        process.Kill();
        await process.WaitForExitAsync(TimeSpan.FromSeconds(10)).ConfigureAwait(false);
    }

    private void AttachProcessEvents(ServerComponent component, HiddenChildProcess process, bool includeNormalOutput)
    {
        if (includeNormalOutput)
            process.OutputReceived += line => Log(ComponentName(component), line);
        process.ErrorReceived += line => Log(ComponentName(component), $"FEHLER: {line}");
        process.Exited += exitCode => HandleUnexpectedExit(component, process, exitCode);
    }

    private void HandleUnexpectedExit(ServerComponent component, HiddenChildProcess process, int exitCode)
    {
        if (_intentionalShutdown || _states[component] == ComponentState.Stopping)
            return;

        ComponentState previous = _states[component];
        string detail = $"Unerwartet beendet (Exit-Code {exitCode})";
        SetState(component, ComponentState.StoppedUnexpectedly, detail);
        Log(ComponentName(component), detail);

        if (previous == ComponentState.Starting)
            return;

        // Do not restart automatically. The remaining components stay available
        // until the user explicitly stops and starts the environment again.
    }

    private async Task WaitForPortAsync(
        ServerComponent component,
        HiddenChildProcess process,
        int port,
        TimeSpan timeout)
    {
        Stopwatch stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < timeout)
        {
            if (process.HasExited)
            {
                int exitCode;
                try { exitCode = process.Process.ExitCode; }
                catch { exitCode = -1; }
                throw new LauncherException($"{ComponentName(component)} wurde während des Starts beendet (Exit-Code {exitCode}).");
            }

            if (await CanConnectAsync(port, TimeSpan.FromMilliseconds(500)).ConfigureAwait(false))
                return;

            await Task.Delay(350).ConfigureAwait(false);
        }

        throw new LauncherException($"{ComponentName(component)} wurde nicht innerhalb von {timeout.TotalSeconds:0} Sekunden bereit (Port {port}).");
    }

    private async Task WaitForDatabaseReadyAsync(HiddenChildProcess process, TimeSpan timeout)
    {
        Stopwatch stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < timeout)
        {
            if (process.HasExited)
            {
                int exitCode;
                try { exitCode = process.Process.ExitCode; }
                catch { exitCode = -1; }
                throw new LauncherException($"Database wurde während des Starts beendet (Exit-Code {exitCode}).");
            }

            if (await DatabasePingAsync().ConfigureAwait(false))
                return;

            await Task.Delay(450).ConfigureAwait(false);
        }

        throw new LauncherException($"Database wurde nicht innerhalb von {timeout.TotalSeconds:0} Sekunden bereit (Port 3307).");
    }

    private async Task<bool> DatabasePingAsync()
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = _layout.DatabaseAdminExecutable,
            WorkingDirectory = _layout.DatabaseDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        AddDatabaseAdminConnectionArguments(startInfo);
        startInfo.ArgumentList.Add("--connect-timeout=1");
        startInfo.ArgumentList.Add("--silent");
        startInfo.ArgumentList.Add("ping");

        try
        {
            using Process? admin = Process.Start(startInfo);
            if (admin is null)
                return false;
            using var pingTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await admin.WaitForExitAsync(pingTimeout.Token).ConfigureAwait(false);
            return admin.ExitCode == 0;
        }
        catch (Exception exception) when (exception is OperationCanceledException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

    private static async Task<bool> CanConnectAsync(int port, TimeSpan timeout)
    {
        using var client = new TcpClient();
        using var cancellation = new CancellationTokenSource(timeout);
        try
        {
            await client.ConnectAsync("127.0.0.1", port, cancellation.Token).ConfigureAwait(false);
            return true;
        }
        catch (Exception exception) when (exception is SocketException or OperationCanceledException)
        {
            return false;
        }
    }

    private static void EnsurePortAvailable(int port, string description)
    {
        if (CanConnectAsync(port, TimeSpan.FromMilliseconds(250)).GetAwaiter().GetResult())
            throw new LauncherException($"{description} kann nicht gestartet werden, weil Port {port} bereits verwendet wird.");
    }

    private void EnsureNoOwnedWebProcesses()
    {
        List<Process> processes = GetOwnedWebProcesses();
        try
        {
            if (processes.Count == 0)
                return;
            string ids = string.Join(", ", processes.Select(process => process.Id));
            throw new LauncherException($"Es läuft bereits ein Nostalgia-Webserver (PID {ids}).\n\nBitte beende die vorhandene Serverinstanz zuerst.");
        }
        finally
        {
            foreach (Process process in processes)
                process.Dispose();
        }
    }

    private bool HasOwnedWebProcesses()
    {
        List<Process> processes = GetOwnedWebProcesses();
        foreach (Process process in processes)
            process.Dispose();
        return processes.Count > 0;
    }

    private List<Process> GetOwnedWebProcesses()
    {
        var matches = new List<Process>();
        string expectedPath = Path.GetFullPath(_layout.WebExecutable);
        foreach (Process process in Process.GetProcessesByName("httpd"))
        {
            bool matchesPath = false;
            try
            {
                string? processPath = process.MainModule?.FileName;
                matchesPath = processPath is not null &&
                              string.Equals(Path.GetFullPath(processPath), expectedPath, StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
            {
            }

            if (matchesPath)
                matches.Add(process);
            else
                process.Dispose();
        }
        return matches;
    }

    private static void EnsureNoExternalServerProcesses()
    {
        var processNames = new[] { "mariadbd", "mysqld", "realmd", "mangosd" };
        foreach (string processName in processNames)
        {
            Process[] processes = Process.GetProcessesByName(processName);
            try
            {
                if (processes.Length > 0)
                {
                    string ids = string.Join(", ", processes.Select(process => process.Id));
                    throw new LauncherException($"Es läuft bereits ein Prozess „{processName}.exe“ (PID {ids}).\n\nBitte beende die vorhandene Serverinstanz zuerst.");
                }
            }
            finally
            {
                foreach (Process process in processes)
                    process.Dispose();
            }
        }
    }

    private LauncherException FriendlyStartException(string description, string executable, Exception exception)
    {
        string relativePath = Path.GetRelativePath(_layout.BaseDirectory, executable);
        return new LauncherException($"{description} konnte nicht gestartet werden.\n\nDatei:\n{relativePath}\n\n{exception.Message}", exception);
    }

    private void SetAllStopped()
    {
        SetState(ServerComponent.Web, ComponentState.Stopped);
        SetState(ServerComponent.World, ComponentState.Stopped);
        SetState(ServerComponent.Realm, ComponentState.Stopped);
        SetState(ServerComponent.Database, ComponentState.Stopped);
    }

    private void SetState(ServerComponent component, ComponentState state, string? detail = null)
    {
        _states[component] = state;
        StatusChanged?.Invoke(new StatusChangedEventArgs(component, state, detail));
    }

    private void Log(string source, string message)
    {
        if (string.IsNullOrWhiteSpace(message))
            return;
        LogReceived?.Invoke($"[{DateTime.Now:HH:mm:ss}] [{source}] {message}");
    }

    private static string ComponentName(ServerComponent component) => component switch
    {
        ServerComponent.Database => "Database",
        ServerComponent.Realm => "Realm",
        ServerComponent.World => "World",
        ServerComponent.Web => "Web",
        _ => component.ToString()
    };

    private static bool IsAlive(HiddenChildProcess? process) => process is not null && !process.HasExited;

    private void DisposeExitedProcesses()
    {
        DisposeIfExited(ref _web);
        DisposeIfExited(ref _world);
        DisposeIfExited(ref _realm);
        DisposeIfExited(ref _database);
    }

    private static void DisposeIfExited(ref HiddenChildProcess? process)
    {
        if (process is null || !process.HasExited)
            return;
        process.Dispose();
        process = null;
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;
        _web?.Dispose();
        _world?.Dispose();
        _realm?.Dispose();
        _database?.Dispose();
        _operationLock.Dispose();
    }
}
