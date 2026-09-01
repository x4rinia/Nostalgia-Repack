using System.Diagnostics;

namespace DinoControllerBridge;

internal static class Program
{
    private const string MutexName = "Local\\DinoControllerBridge-270F4F16-5194-4577-AD7D-85800C2274BB";

    private static int Main(string[] args)
    {
        using var mutex = new Mutex(true, MutexName, out bool firstInstance);
        if (!firstInstance)
            return 0;

        string baseDirectory = AppContext.BaseDirectory;
        string configPath = Path.Combine(baseDirectory, "DinoControllerBridge.json");
        string logPath = Path.Combine(baseDirectory, "DinoControllerBridge.log");

        try
        {
            BridgeConfig.WriteDefault(configPath);
            BridgeConfig config = BridgeConfig.Load(configPath);
            config.Validate();
            config.WriteAddonSnapshot(baseDirectory);

            if (args.Any(value => value.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
            {
                NativeMethods.TryGetControllerState(config.ControllerIndex, out _);
                KeyMappingParser.Parse("CTRL+5");
                KeyMappingParser.Parse("SHIFT+F12");
                KeyMappingParser.Parse("NUMPAD9");
                KeyMappingParser.Parse("NUMPADPLUS");
                KeyMappingParser.Parse("NUMPADMINUS");
                _ = new ControllerMapper(config);
                using var cursorTest = new CursorVisibilityController(config);
                cursorTest.Update(controllerModeActive: true, controllerInput: true, cursorMayRemainVisible: false);
                cursorTest.Update(controllerModeActive: false, controllerInput: false, cursorMayRemainVisible: false);
                Log(logPath, $"Selbsttest erfolgreich; Mausmonitor={cursorTest.MonitorAvailable}.");
                return 0;
            }

            return Run(config, logPath);
        }
        catch (Exception exception)
        {
            Log(logPath, $"FEHLER: {exception}");
            return 1;
        }
        finally
        {
            GC.KeepAlive(mutex);
        }
    }

    private static int Run(BridgeConfig config, string logPath)
    {
        using var cursor = new CursorVisibilityController(config);
        var mapper = new ControllerMapper(config, cursor.ReassertHiddenAfterCursorMove);
        bool sawWow = false;
        bool wowRunning = false;
        bool controllerConnected = false;
        DateTime nextWowCheck = DateTime.MinValue;
        Log(logPath, $"Gestartet; Aktiv={config.Enabled}, Mausmonitor={cursor.MonitorAvailable}; warte auf WoW.exe und XInput-Controller {config.ControllerIndex + 1}.");

        try
        {
            while (true)
            {
                if (DateTime.UtcNow >= nextWowCheck)
                {
                    Process[] wowProcesses = Process.GetProcessesByName("WoW");
                    wowRunning = wowProcesses.Length > 0;
                    foreach (Process process in wowProcesses)
                        process.Dispose();

                    if (wowRunning)
                        sawWow = true;
                    else if (sawWow)
                        break;

                    nextWowCheck = DateTime.UtcNow.AddMilliseconds(500);
                }

                bool connected = NativeMethods.TryGetControllerState(config.ControllerIndex, out NativeMethods.XInputState state);
                if (connected != controllerConnected)
                {
                    controllerConnected = connected;
                    Log(logPath, connected ? "Controller verbunden." : "Controller getrennt.");
                }

                IntPtr wowWindow = IntPtr.Zero;
                bool wowForeground = config.Enabled && connected && mapper.IsWowForeground(out wowWindow);
                bool controllerInput = false;
                if (wowForeground)
                {
                    if ((state.Gamepad.Buttons & (NativeMethods.XINPUT_GAMEPAD_A | NativeMethods.XINPUT_GAMEPAD_B)) != 0)
                        cursor.PrepareForControllerActivation();
                    controllerInput = mapper.Update(state.Gamepad, wowWindow);
                }
                else
                    mapper.ReleaseAll();
                cursor.Update(wowForeground, controllerInput, mapper.CursorMayRemainVisible);

                Thread.Sleep(config.PollIntervalMilliseconds);
            }
        }
        finally
        {
            mapper.ReleaseAll();
        }

        Log(logPath, "WoW wurde beendet; Controller-Bruecke beendet.");
        return 0;
    }

    private static void Log(string path, string message)
    {
        try
        {
            File.AppendAllText(path, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}");
        }
        catch
        {
            // Die Eingabebruecke soll auch in einem schreibgeschuetzten Ordner laufen.
        }
    }
}
