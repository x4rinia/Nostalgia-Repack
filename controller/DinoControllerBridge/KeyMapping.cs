namespace DinoControllerBridge;

internal sealed record KeyChord(ushort Key, IReadOnlyList<ushort> Modifiers)
{
    internal static readonly KeyChord Disabled = new(0, []);
    internal bool IsDisabled => Key == 0;
}

internal static class KeyMappingParser
{
    private static readonly Dictionary<string, ushort> NamedKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        ["SPACE"] = 0x20,
        ["TAB"] = 0x09,
        ["ENTER"] = 0x0D,
        ["RETURN"] = 0x0D,
        ["ESC"] = 0x1B,
        ["ESCAPE"] = 0x1B,
        ["BACKSPACE"] = 0x08,
        ["INSERT"] = 0x2D,
        ["DELETE"] = 0x2E,
        ["HOME"] = 0x24,
        ["END"] = 0x23,
        ["PAGEUP"] = 0x21,
        ["PAGEDOWN"] = 0x22,
        ["NUMPADPLUS"] = NativeMethods.VK_NUMPAD_PLUS,
        ["NUMPADMINUS"] = NativeMethods.VK_NUMPAD_MINUS,
        ["NUMPADMULTIPLY"] = NativeMethods.VK_NUMPAD_MULTIPLY,
        ["UP"] = 0x26,
        ["DOWN"] = 0x28,
        ["LEFT"] = 0x25,
        ["RIGHT"] = 0x27,
        ["SHIFT"] = NativeMethods.VK_SHIFT,
        ["CTRL"] = NativeMethods.VK_CONTROL,
        ["CONTROL"] = NativeMethods.VK_CONTROL,
        ["ALT"] = NativeMethods.VK_ALT
    };

    internal static KeyChord Parse(string? expression)
    {
        if (string.IsNullOrWhiteSpace(expression) || expression.Equals("NONE", StringComparison.OrdinalIgnoreCase))
            return KeyChord.Disabled;

        string[] parts = expression.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
            return KeyChord.Disabled;

        var modifiers = new List<ushort>();
        for (int index = 0; index < parts.Length - 1; index++)
        {
            ushort modifier = ParseModifier(parts[index]);
            if (!modifiers.Contains(modifier))
                modifiers.Add(modifier);
        }

        ushort key = ParseSingleKey(parts[^1]);
        return new KeyChord(key, modifiers);
    }

    private static ushort ParseModifier(string value)
    {
        ushort key = ParseSingleKey(value);
        if (key != NativeMethods.VK_SHIFT && key != NativeMethods.VK_CONTROL && key != NativeMethods.VK_ALT)
            throw new InvalidDataException($"'{value}' ist kein gueltiger Modifier (CTRL, SHIFT oder ALT).");
        return key;
    }

    private static ushort ParseSingleKey(string value)
    {
        if (NamedKeys.TryGetValue(value, out ushort named))
            return named;

        if (value.Length == 1)
        {
            char character = char.ToUpperInvariant(value[0]);
            if (character is >= 'A' and <= 'Z' or >= '0' and <= '9')
                return character;
        }

        if (value.StartsWith("F", StringComparison.OrdinalIgnoreCase) &&
            int.TryParse(value.AsSpan(1), out int functionKey) && functionKey is >= 1 and <= 24)
            return (ushort)(0x70 + functionKey - 1);

        if (value.StartsWith("NUMPAD", StringComparison.OrdinalIgnoreCase) &&
            int.TryParse(value.AsSpan(6), out int number) && number is >= 0 and <= 9)
            return (ushort)(0x60 + number);

        throw new InvalidDataException($"Unbekannte Taste in ButtonMappings: '{value}'.");
    }
}
