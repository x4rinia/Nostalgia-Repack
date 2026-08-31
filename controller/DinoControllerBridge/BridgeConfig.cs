using System.Text;
using System.Text.Json;

namespace DinoControllerBridge;

internal sealed class BridgeConfig
{
    private static readonly IReadOnlyDictionary<string, string> DefaultButtonMappings =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["X"] = "5",
            ["Y"] = "6",
            ["R3"] = "F1",
            ["DPadUp"] = "1",
            ["DPadRight"] = "2",
            ["DPadDown"] = "3",
            ["DPadLeft"] = "4",
            ["L2"] = "F9",
            ["R2"] = "F10"
        };

    public bool Enabled { get; set; } = true;
    public int ControllerIndex { get; set; }
    public double LeftStickPressDeadzone { get; set; } = 0.30;
    public double LeftStickReleaseDeadzone { get; set; } = 0.22;
    public double RightStickDeadzone { get; set; } = 0.18;
    public double CameraPixelsPerTick { get; set; } = 12.0;
    public bool InvertCameraY { get; set; }
    public int PollIntervalMilliseconds { get; set; } = 8;
    public int CursorSettleDelayMilliseconds { get; set; } = 40;
    public int InteractionPressMilliseconds { get; set; } = 16;
    public bool CursorAutoHide { get; set; } = true;
    public int CursorHideDelayMilliseconds { get; set; } = 1800;
    public Dictionary<string, string> ButtonMappings { get; set; } = CreateDefaultMappings();

    public static BridgeConfig Load(string path)
    {
        if (!File.Exists(path))
            return new BridgeConfig();

        string json = File.ReadAllText(path);
        BridgeConfig config = JsonSerializer.Deserialize<BridgeConfig>(json, JsonOptions())
            ?? throw new InvalidDataException("Die Controller-Konfiguration ist leer.");
        config.MergeMappingDefaults();
        config.Validate();
        return config;
    }

    public static void WriteDefault(string path)
    {
        if (File.Exists(path))
            return;

        File.WriteAllText(path, JsonSerializer.Serialize(new BridgeConfig(), JsonOptions()));
    }

    public void Validate()
    {
        if (ControllerIndex < 0 || ControllerIndex > 3)
            throw new InvalidDataException("ControllerIndex muss zwischen 0 und 3 liegen.");
        if (LeftStickReleaseDeadzone < 0 || LeftStickPressDeadzone <= LeftStickReleaseDeadzone || LeftStickPressDeadzone >= 1)
            throw new InvalidDataException("Die Deadzones des linken Sticks sind ungueltig.");
        if (RightStickDeadzone < 0 || RightStickDeadzone >= 1)
            throw new InvalidDataException("RightStickDeadzone muss zwischen 0 und 1 liegen.");
        if (CameraPixelsPerTick <= 0 || CameraPixelsPerTick > 100)
            throw new InvalidDataException("CameraPixelsPerTick muss groesser 0 und hoechstens 100 sein.");
        if (PollIntervalMilliseconds < 4 || PollIntervalMilliseconds > 50)
            throw new InvalidDataException("PollIntervalMilliseconds muss zwischen 4 und 50 liegen.");
        if (CursorSettleDelayMilliseconds < 0 || CursorSettleDelayMilliseconds > 50)
            throw new InvalidDataException("CursorSettleDelayMilliseconds muss zwischen 0 und 50 liegen.");
        if (InteractionPressMilliseconds < 1 || InteractionPressMilliseconds > 50)
            throw new InvalidDataException("InteractionPressMilliseconds muss zwischen 1 und 50 liegen.");
        if (CursorHideDelayMilliseconds < 250 || CursorHideDelayMilliseconds > 30000)
            throw new InvalidDataException("CursorHideDelayMilliseconds muss zwischen 250 und 30000 liegen.");

        foreach ((string button, string key) in ButtonMappings)
        {
            if (!DefaultButtonMappings.ContainsKey(button))
                throw new InvalidDataException($"Unbekannter Controllerbutton in ButtonMappings: {button}");
            KeyChord chord = KeyMappingParser.Parse(key);
            if (chord.Key == NativeMethods.VK_NUMPAD0 || chord.Key == NativeMethods.VK_NUMPAD9 ||
                chord.Key == NativeMethods.VK_NUMPAD_PLUS || chord.Key == NativeMethods.VK_NUMPAD_MINUS)
                throw new InvalidDataException("NUMPAD0, NUMPAD9, NUMPADPLUS und NUMPADMINUS sind fuer logische DinoController-Aktionen reserviert.");
        }
    }

    public void WriteAddonSnapshot(string bridgeDirectory)
    {
        string? addonDirectory = FindAddonDirectory(bridgeDirectory);
        if (addonDirectory is null)
            return;

        string path = Path.Combine(addonDirectory, "BridgeMappings.lua");
        var lua = new StringBuilder();
        lua.AppendLine("-- Automatisch von DinoControllerBridge.exe erzeugt; JSON ist die Quelle.");
        lua.AppendLine("-- Author: x4rinia");
        lua.AppendLine("DinoControllerBridgeConfig = {");
        lua.AppendLine($"    Enabled = {(Enabled ? 1 : 0)},");
        lua.AppendLine("    ButtonMappings = {");
        string[] order = ["X", "Y", "R3", "DPadUp", "DPadRight", "DPadDown", "DPadLeft", "L2", "R2"];
        for (int index = 0; index < order.Length; index++)
        {
            string name = order[index];
            string suffix = index == order.Length - 1 ? string.Empty : ",";
            lua.AppendLine($"        {name} = \"{EscapeLua(ButtonMappings[name])}\"{suffix}");
        }
        lua.AppendLine("    }");
        lua.AppendLine("}");
        File.WriteAllText(path, lua.ToString(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    private static string? FindAddonDirectory(string bridgeDirectory)
    {
        string[] candidates =
        [
            // Standalone release: EXE liegt direkt neben dem Interface-Ordner.
            Path.Combine(bridgeDirectory, "Interface", "AddOns", "DinoController"),
            // Alternative: EXE und Client-Unterordner liegen im selben Verzeichnis.
            Path.Combine(bridgeDirectory, "client", "Interface", "AddOns", "DinoController"),
            // Kompatibles tools-Layout: EXE liegt in einem Unterordner neben client.
            Path.Combine(bridgeDirectory, "..", "client", "Interface", "AddOns", "DinoController")
        ];

        foreach (string candidate in candidates)
        {
            string fullPath = Path.GetFullPath(candidate);
            if (Directory.Exists(fullPath))
                return fullPath;
        }
        return null;
    }

    private void MergeMappingDefaults()
    {
        var normalized = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (ButtonMappings is not null)
        {
            foreach ((string key, string value) in ButtonMappings)
                normalized[key] = string.IsNullOrWhiteSpace(value) ? "NONE" : value;
        }
        foreach ((string key, string value) in DefaultButtonMappings)
        {
            if (!normalized.ContainsKey(key))
                normalized[key] = value;
        }
        ButtonMappings = normalized;
    }

    private static Dictionary<string, string> CreateDefaultMappings() =>
        new(DefaultButtonMappings, StringComparer.OrdinalIgnoreCase);

    private static string EscapeLua(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("\"", "\\\"", StringComparison.Ordinal)
        .Replace("\r", string.Empty, StringComparison.Ordinal)
        .Replace("\n", " ", StringComparison.Ordinal);

    private static JsonSerializerOptions JsonOptions() => new()
    {
        AllowTrailingCommas = true,
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        WriteIndented = true
    };
}
