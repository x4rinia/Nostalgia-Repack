using System.Runtime.InteropServices;

namespace DinoControllerBridge;

internal static class NativeMethods
{
    internal const ushort XINPUT_GAMEPAD_DPAD_UP = 0x0001;
    internal const ushort XINPUT_GAMEPAD_DPAD_DOWN = 0x0002;
    internal const ushort XINPUT_GAMEPAD_DPAD_LEFT = 0x0004;
    internal const ushort XINPUT_GAMEPAD_DPAD_RIGHT = 0x0008;
    internal const ushort XINPUT_GAMEPAD_START = 0x0010;
    internal const ushort XINPUT_GAMEPAD_BACK = 0x0020;
    internal const ushort XINPUT_GAMEPAD_LEFT_THUMB = 0x0040;
    internal const ushort XINPUT_GAMEPAD_RIGHT_THUMB = 0x0080;
    internal const ushort XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100;
    internal const ushort XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200;
    internal const ushort XINPUT_GAMEPAD_A = 0x1000;
    internal const ushort XINPUT_GAMEPAD_B = 0x2000;
    internal const ushort XINPUT_GAMEPAD_X = 0x4000;
    internal const ushort XINPUT_GAMEPAD_Y = 0x8000;

    internal const ushort VK_SHIFT = 0x10;
    internal const ushort VK_CONTROL = 0x11;
    internal const ushort VK_ALT = 0x12;
    internal const ushort VK_ESCAPE = 0x1B;
    internal const ushort VK_F11 = 0x7A;
    internal const ushort VK_NUMPAD0 = 0x60;
    internal const ushort VK_NUMPAD1 = 0x61;
    internal const ushort VK_NUMPAD2 = 0x62;
    internal const ushort VK_NUMPAD3 = 0x63;
    internal const ushort VK_NUMPAD4 = 0x64;
    internal const ushort VK_NUMPAD5 = 0x65;
    internal const ushort VK_NUMPAD6 = 0x66;
    internal const ushort VK_NUMPAD7 = 0x67;
    internal const ushort VK_NUMPAD8 = 0x68;
    internal const ushort VK_NUMPAD9 = 0x69;
    internal const ushort VK_NUMPAD_MULTIPLY = 0x6A;
    internal const ushort VK_NUMPAD_PLUS = 0x6B;
    internal const ushort VK_NUMPAD_MINUS = 0x6D;
    internal const ushort VK_DIVIDE = 0x6F;

    private const uint INPUT_MOUSE = 0;
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;

    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
    private static extern uint XInputGetState14(uint userIndex, out XInputState state);

    [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")]
    private static extern uint XInputGetState910(uint userIndex, out XInputState state);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint inputCount, Input[] inputs, int inputSize);

    [DllImport("user32.dll")]
    internal static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    internal static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    internal static extern bool GetClientRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    internal static extern bool ClientToScreen(IntPtr window, ref Point point);

    [DllImport("user32.dll")]
    internal static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    internal static extern int ShowCursor(bool show);

    [DllImport("user32.dll")]
    internal static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    internal static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    internal static extern uint GetPixel(IntPtr hdc, int nXPos, int nYPos);

    internal static bool TryGetControllerState(int index, out XInputState state)
    {
        try
        {
            return XInputGetState14((uint)index, out state) == 0;
        }
        catch (DllNotFoundException)
        {
            return XInputGetState910((uint)index, out state) == 0;
        }
        catch (EntryPointNotFoundException)
        {
            return XInputGetState910((uint)index, out state) == 0;
        }
    }

    internal static void SendKey(ushort virtualKey, bool down)
    {
        Send(new Input
        {
            Type = INPUT_KEYBOARD,
            Union = new InputUnion
            {
                Keyboard = new KeyboardInput
                {
                    VirtualKey = virtualKey,
                    Flags = down ? 0 : KEYEVENTF_KEYUP
                }
            }
        });
    }

    internal static void SendMouseMove(int x, int y)
    {
        if (x == 0 && y == 0)
            return;

        Send(new Input
        {
            Type = INPUT_MOUSE,
            Union = new InputUnion
            {
                Mouse = new MouseInput { X = x, Y = y, Flags = MOUSEEVENTF_MOVE }
            }
        });
    }

    internal static void SendRightMouse(bool down)
    {
        Send(CreateRightMouseInput(down));
    }

    internal static void SendLeftMouse(bool down)
    {
        Send(new Input
        {
            Type = INPUT_MOUSE,
            Union = new InputUnion
            {
                Mouse = new MouseInput { Flags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP }
            }
        });
    }

    private static Input CreateRightMouseInput(bool down) => new()
    {
        Type = INPUT_MOUSE,
        Union = new InputUnion
        {
            Mouse = new MouseInput { Flags = down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP }
        }
    };

    private static void Send(params Input[] inputs)
    {
        uint expected = (uint)inputs.Length;
        if (SendInput(expected, inputs, Marshal.SizeOf<Input>()) != expected)
            throw new InvalidOperationException($"SendInput ist fehlgeschlagen (Win32 {Marshal.GetLastWin32Error()}).");
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct XInputState
    {
        internal uint PacketNumber;
        internal XInputGamepad Gamepad;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct XInputGamepad
    {
        internal ushort Buttons;
        internal byte LeftTrigger;
        internal byte RightTrigger;
        internal short ThumbLX;
        internal short ThumbLY;
        internal short ThumbRX;
        internal short ThumbRY;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Point
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Rect
    {
        internal int Left;
        internal int Top;
        internal int Right;
        internal int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        internal uint Type;
        internal InputUnion Union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] internal MouseInput Mouse;
        [FieldOffset(0)] internal KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        internal int X;
        internal int Y;
        internal uint MouseData;
        internal uint Flags;
        internal uint Time;
        internal UIntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        internal ushort VirtualKey;
        internal ushort ScanCode;
        internal uint Flags;
        internal uint Time;
        internal UIntPtr ExtraInfo;
    }
}
