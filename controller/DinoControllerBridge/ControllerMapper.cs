using System.Diagnostics;

namespace DinoControllerBridge;

internal sealed class ControllerMapper
{
    private readonly BridgeConfig _config;
    private readonly Action _cursorMoved;
    private readonly HashSet<ushort> _heldKeys = [];
    private readonly List<(ushort Button, KeyChord Chord)> _configurableMappings = [];
    private ushort _previousButtons;
    private bool _rightMouseHeld;
    private bool _cursorReturnPending;
    private long _cursorReturnAt;
    private NativeMethods.Point _cursorReturnPosition;
    private IntPtr _lastForegroundWindow;
    private bool _lastWindowWasWow;

    private readonly KeyChord _l2Chord;
    private readonly KeyChord _r2Chord;

    public bool CursorMayRemainVisible { get; private set; }

    public ControllerMapper(BridgeConfig config, Action? cursorMoved = null)
    {
        _config = config;
        _cursorMoved = cursorMoved ?? (() => { });
        _l2Chord = config.ButtonMappings.TryGetValue("L2", out string? l2Key) ? KeyMappingParser.Parse(l2Key) : KeyChord.Disabled;
        _r2Chord = config.ButtonMappings.TryGetValue("R2", out string? r2Key) ? KeyMappingParser.Parse(r2Key) : KeyChord.Disabled;

        foreach ((string button, string key) in config.ButtonMappings)
        {
            if (!button.Equals("X", StringComparison.OrdinalIgnoreCase) &&
                !button.Equals("Y", StringComparison.OrdinalIgnoreCase) &&
                !button.Equals("L2", StringComparison.OrdinalIgnoreCase) &&
                !button.Equals("R2", StringComparison.OrdinalIgnoreCase))
                _configurableMappings.Add((ControllerButtonMask(button), KeyMappingParser.Parse(key)));
        }
    }

    public bool IsWowForeground(out IntPtr window)
    {
        window = NativeMethods.GetForegroundWindow();
        if (window == IntPtr.Zero)
            return false;
        if (window == _lastForegroundWindow)
            return _lastWindowWasWow;

        _lastForegroundWindow = window;
        _lastWindowWasWow = false;
        NativeMethods.GetWindowThreadProcessId(window, out uint processId);
        if (processId == 0)
            return false;

        try
        {
            using Process process = Process.GetProcessById((int)processId);
            _lastWindowWasWow = process.ProcessName.Equals("WoW", StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException)
        {
            _lastWindowWasWow = false;
        }

        return _lastWindowWasWow;
    }

    public bool Update(NativeMethods.XInputGamepad gamepad, IntPtr wowWindow)
    {
        ApplyPendingCursorReturn();
        UpdateLeftStick(gamepad);
        bool cameraActive = UpdateCamera(gamepad);
        ushort actionKey = GetActionKey(wowWindow, out bool lootActive, out bool cursorMayRemainVisible);
        CursorMayRemainVisible = cursorMayRemainVisible;
        if (Pressed(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_A))
            ActivateFaceButton(wowWindow, NativeMethods.VK_NUMPAD0, actionKey, lootActive);
        if (Pressed(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_B))
            ActivateFaceButton(wowWindow, NativeMethods.VK_NUMPAD9, actionKey, lootActive);
        TapOnPress(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_X, NativeMethods.VK_NUMPAD_MINUS);
        TapOnPress(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_Y, NativeMethods.VK_NUMPAD_PLUS);
        TapOnPress(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_RIGHT_SHOULDER, NativeMethods.VK_NUMPAD1);
        TapOnPress(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_LEFT_SHOULDER, NativeMethods.VK_NUMPAD3);
        TapOnPress(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_START, 0x77); // F8
        TapOnPress(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_BACK, NativeMethods.VK_NUMPAD5);
        TapOnPress(gamepad.Buttons, NativeMethods.XINPUT_GAMEPAD_LEFT_THUMB, NativeMethods.VK_NUMPAD7);

        UpdateTrigger(_l2Chord, gamepad.LeftTrigger);
        UpdateTrigger(_r2Chord, gamepad.RightTrigger);

        foreach ((ushort button, KeyChord chord) in _configurableMappings)
            TapChordOnPress(gamepad.Buttons, button, chord);

        bool controllerInput = gamepad.Buttons != 0 || gamepad.LeftTrigger >= 40 || gamepad.RightTrigger >= 40 ||
            Math.Abs(NormalizeAxis(gamepad.ThumbLX)) >= _config.LeftStickPressDeadzone ||
            Math.Abs(NormalizeAxis(gamepad.ThumbLY)) >= _config.LeftStickPressDeadzone || cameraActive;

        _previousButtons = gamepad.Buttons;
        return controllerInput;
    }

    public void ReleaseAll()
    {
        foreach (ushort key in _heldKeys.ToArray())
            SetKey(key, false);

        if (_rightMouseHeld)
        {
            NativeMethods.SendRightMouse(false);
            _rightMouseHeld = false;
        }

        _previousButtons = 0;
    }

    private void UpdateLeftStick(NativeMethods.XInputGamepad gamepad)
    {
        double x = NormalizeAxis(gamepad.ThumbLX);
        double y = NormalizeAxis(gamepad.ThumbLY);
        UpdateAxisKey(NativeMethods.VK_NUMPAD4, x < 0 ? -x : 0);
        UpdateAxisKey(NativeMethods.VK_NUMPAD6, x > 0 ? x : 0);
        UpdateAxisKey(NativeMethods.VK_NUMPAD8, y > 0 ? y : 0);
        UpdateAxisKey(NativeMethods.VK_NUMPAD2, y < 0 ? -y : 0);
    }

    private void UpdateAxisKey(ushort key, double amount)
    {
        bool held = _heldKeys.Contains(key);
        double threshold = held ? _config.LeftStickReleaseDeadzone : _config.LeftStickPressDeadzone;
        SetKey(key, amount >= threshold);
    }

    private bool UpdateCamera(NativeMethods.XInputGamepad gamepad)
    {
        double x = ApplyRadialDeadzone(NormalizeAxis(gamepad.ThumbRX), NormalizeAxis(gamepad.ThumbRY), out double y);
        bool active = x != 0 || y != 0;

        if (active && !_rightMouseHeld)
        {
            NativeMethods.SendRightMouse(true);
            _rightMouseHeld = true;
        }
        else if (!active && _rightMouseHeld)
        {
            NativeMethods.SendRightMouse(false);
            _rightMouseHeld = false;
        }

        if (!active)
            return false;

        int deltaX = (int)Math.Round(x * _config.CameraPixelsPerTick);
        double pitch = _config.InvertCameraY ? y : -y;
        int deltaY = (int)Math.Round(pitch * _config.CameraPixelsPerTick);
        NativeMethods.SendMouseMove(deltaX, deltaY);
        return true;
    }

    private double ApplyRadialDeadzone(double x, double inputY, out double outputY)
    {
        double length = Math.Sqrt(x * x + inputY * inputY);
        if (length <= _config.RightStickDeadzone)
        {
            outputY = 0;
            return 0;
        }

        double scaledLength = Math.Min(1, (length - _config.RightStickDeadzone) / (1 - _config.RightStickDeadzone));
        double scale = scaledLength / length;
        outputY = inputY * scale;
        return x * scale;
    }

    private void TapOnPress(ushort buttons, ushort button, ushort key)
    {
        if (!Pressed(buttons, button))
            return;

        NativeMethods.SendKey(key, true);
        NativeMethods.SendKey(key, false);
    }

    private void TapChordOnPress(ushort buttons, ushort button, KeyChord chord)
    {
        if (!Pressed(buttons, button) || chord.IsDisabled)
            return;

        foreach (ushort modifier in chord.Modifiers)
            NativeMethods.SendKey(modifier, true);
        NativeMethods.SendKey(chord.Key, true);
        NativeMethods.SendKey(chord.Key, false);
        for (int index = chord.Modifiers.Count - 1; index >= 0; index--)
            NativeMethods.SendKey(chord.Modifiers[index], false);
    }

    private void UpdateTrigger(KeyChord chord, byte triggerValue)
    {
        if (chord.IsDisabled)
            return;

        bool held = triggerValue >= 40;
        SetKey(chord.Key, held);
    }

    private bool Pressed(ushort buttons, ushort button) =>
        (buttons & button) != 0 && (_previousButtons & button) == 0;

    private void SetKey(ushort key, bool down)
    {
        if (down)
        {
            if (_heldKeys.Add(key))
                NativeMethods.SendKey(key, true);
        }
        else if (_heldKeys.Remove(key))
        {
            NativeMethods.SendKey(key, false);
        }
    }

    private ushort GetActionKey(IntPtr wowWindow, out bool lootActive, out bool cursorMayRemainVisible)
    {
        lootActive = false;
        cursorMayRemainVisible = false;
        IntPtr hdc = NativeMethods.GetDC(wowWindow);
        if (hdc == IntPtr.Zero)
            return 0;

        try
        {
            uint pixel = NativeMethods.GetPixel(hdc, 2, 2);
            if (pixel == 0xFFFFFFFF)
                return 0;

            byte r = (byte)(pixel & 0xFF);
            byte g = (byte)((pixel >> 8) & 0xFF);
            byte b = (byte)((pixel >> 16) & 0xFF);

            lootActive = Math.Max(r, Math.Max(g, b)) > 200;
            cursorMayRemainVisible = b >= 80;
            if (r < 50 && g > 20 && b > 20)
                return NativeMethods.VK_NUMPAD0;
            if (r > 20 && g < 50 && b > 20)
                return NativeMethods.VK_NUMPAD9;
            return 0;
        }
        finally
        {
            NativeMethods.ReleaseDC(wowWindow, hdc);
        }
    }

    private void ActivateFaceButton(IntPtr wowWindow, ushort logicalKey, ushort actionKey, bool lootActive)
    {
        if (logicalKey != actionKey)
        {
            NativeMethods.SendKey(logicalKey, true);
            NativeMethods.SendKey(logicalKey, false);
            return;
        }

        if (lootActive)
        {
            ClickLootAtReticle(wowWindow);
            return;
        }

        ActivateFaceAtReticle(wowWindow, logicalKey);
    }

    private void ClickLootAtReticle(IntPtr wowWindow)
    {
        if (!NativeMethods.GetClientRect(wowWindow, out NativeMethods.Rect rect))
            return;

        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (width <= 0 || height <= 0)
            return;

        var center = new NativeMethods.Point
        {
            X = rect.Left + width / 2,
            Y = rect.Top + height / 2
        };
        if (!NativeMethods.ClientToScreen(wowWindow, ref center))
            return;

        NativeMethods.Point returnCursor = GetCursorReturnPosition(wowWindow, rect);

        bool resumeCamera = _rightMouseHeld;
        if (resumeCamera)
            NativeMethods.SendRightMouse(false);

        try
        {
            _cursorMoved();
            if (!NativeMethods.SetCursorPos(center.X, center.Y))
                return;
            _cursorMoved();
            if (_config.CursorSettleDelayMilliseconds > 0)
                Thread.Sleep(_config.CursorSettleDelayMilliseconds);

            NativeMethods.SendLeftMouse(true);
            Thread.Sleep(_config.InteractionPressMilliseconds);
            NativeMethods.SendLeftMouse(false);
            _cursorMoved();
        }
        finally
        {
            ScheduleCursorReturn(returnCursor);
            if (resumeCamera)
                NativeMethods.SendRightMouse(true);
        }
    }

    // Beide physischen Facebuttons werden getrennt an das Addon gemeldet. Das
    // gespeicherte Xbox-/Nintendo-Layout entscheidet dort, welcher davon im
    // Weltmodus TURNORACTION und welcher im UI-Modus Confirm ist. Zentrieren
    // ist fuer beide unsichtbar und macht den Wechsel ohne Bridge-IPC robust.
    private void ActivateFaceAtReticle(IntPtr wowWindow, ushort logicalKey)
    {
        if (!NativeMethods.GetClientRect(wowWindow, out NativeMethods.Rect rect))
            return;

        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (width <= 0 || height <= 0)
            return;

        var center = new NativeMethods.Point
        {
            X = rect.Left + width / 2,
            Y = rect.Top + height / 2
        };
        if (!NativeMethods.ClientToScreen(wowWindow, ref center))
            return;

        NativeMethods.Point returnCursor = GetCursorReturnPosition(wowWindow, rect);

        bool resumeCamera = _rightMouseHeld;
        if (resumeCamera)
            NativeMethods.SendRightMouse(false);

        try
        {
            // Niemals am aktuellen echten Mauszeiger klicken: Schlaegt das
            // Positionieren fehl, wird die Interaktion komplett verworfen.
            _cursorMoved();
            if (!NativeMethods.SetCursorPos(center.X, center.Y))
                return;
            _cursorMoved();

            // Der alte Client muss die neue Cursorposition mindestens einen
            // Inputzyklus lang sehen, bevor TurnOrActionStart ausgewertet wird.
            if (_config.CursorSettleDelayMilliseconds > 0)
                Thread.Sleep(_config.CursorSettleDelayMilliseconds);

            // Auch im Lootfenster immer den logischen WoW-Key senden. Nur Lua
            // kennt den blau markierten LootButton und dessen echte slot-ID;
            // ein Mausklick auf die Clientmitte kann diesen Frame nicht
            // aufloesungs- und UI-Scale-unabhaengig treffen.
            NativeMethods.SendKey(logicalKey, true);
            Thread.Sleep(_config.InteractionPressMilliseconds);
            NativeMethods.SendKey(logicalKey, false);
            NativeMethods.SendKey(NativeMethods.VK_F12, true);
            NativeMethods.SendKey(NativeMethods.VK_F12, false);
            _cursorMoved();
        }
        finally
        {
            ScheduleCursorReturn(returnCursor);
            if (resumeCamera)
                NativeMethods.SendRightMouse(true);
        }
    }

    private static NativeMethods.Point GetCursorReturnPosition(IntPtr wowWindow, NativeMethods.Rect rect)
    {
        var topLeft = new NativeMethods.Point { X = rect.Left, Y = rect.Top };
        var bottomRight = new NativeMethods.Point { X = rect.Right, Y = rect.Bottom };
        bool haveClientBounds = NativeMethods.ClientToScreen(wowWindow, ref topLeft) &&
            NativeMethods.ClientToScreen(wowWindow, ref bottomRight);

        if (haveClientBounds && NativeMethods.GetCursorPos(out NativeMethods.Point current))
        {
            const int edgeMargin = 16;
            if (current.X <= topLeft.X + edgeMargin || current.X >= bottomRight.X - edgeMargin ||
                current.Y <= topLeft.Y + edgeMargin || current.Y >= bottomRight.Y - edgeMargin)
                return current;
        }

        return bottomRight;
    }

    private void ScheduleCursorReturn(NativeMethods.Point position)
    {
        _cursorReturnPosition = position;
        _cursorReturnAt = Stopwatch.GetTimestamp() + Stopwatch.Frequency / 10;
        _cursorReturnPending = true;
    }

    private void ApplyPendingCursorReturn()
    {
        if (!_cursorReturnPending || _rightMouseHeld || Stopwatch.GetTimestamp() < _cursorReturnAt)
            return;

        _cursorReturnPending = false;
        NativeMethods.SetCursorPos(_cursorReturnPosition.X, _cursorReturnPosition.Y);
        _cursorMoved();
    }



    private static ushort ControllerButtonMask(string name) => name.ToUpperInvariant() switch
    {
        "X" => NativeMethods.XINPUT_GAMEPAD_X,
        "Y" => NativeMethods.XINPUT_GAMEPAD_Y,
        "R3" => NativeMethods.XINPUT_GAMEPAD_RIGHT_THUMB,
        "DPADUP" => NativeMethods.XINPUT_GAMEPAD_DPAD_UP,
        "DPADRIGHT" => NativeMethods.XINPUT_GAMEPAD_DPAD_RIGHT,
        "DPADDOWN" => NativeMethods.XINPUT_GAMEPAD_DPAD_DOWN,
        "DPADLEFT" => NativeMethods.XINPUT_GAMEPAD_DPAD_LEFT,
        _ => throw new InvalidDataException($"Unbekannter Controllerbutton: {name}")
    };

    private static double NormalizeAxis(short value) => value < 0 ? value / 32768.0 : value / 32767.0;
}
