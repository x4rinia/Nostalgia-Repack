using System.Diagnostics;
using System.Runtime.InteropServices;

namespace DinoControllerBridge;

internal sealed class CursorVisibilityController : IDisposable
{
    private readonly bool _enabled;
    private readonly long _hideDelayTicks;
    private readonly long _syntheticCursorIgnoreTicks = Stopwatch.Frequency / 4;
    private readonly PhysicalMouseMonitor? _mouseMonitor;
    private long _lastControllerInput;
    private bool _hidden;

    public CursorVisibilityController(BridgeConfig config)
    {
        _enabled = config.CursorAutoHide;
        _hideDelayTicks = config.CursorHideDelayMilliseconds * Stopwatch.Frequency / 1000;
        _lastControllerInput = Stopwatch.GetTimestamp();
        if (_enabled)
            _mouseMonitor = new PhysicalMouseMonitor();
    }

    internal bool MonitorAvailable => _mouseMonitor?.Available ?? false;

    // Vor dem technisch notwendigen Zentrieren eines Facebuttons ausblenden,
    // damit nie ein sichtbarer virtueller Cursor ueber den Bildschirm springt.
    public void PrepareForControllerActivation()
    {
        if (!_enabled)
            return;

        _lastControllerInput = Stopwatch.GetTimestamp();
        Hide();
    }

    // SetCursorPos erzeugt im WoW-Client ein echtes Mausbewegungsereignis.
    // Der Client kann den Cursor dadurch trotz der vorherigen Ausblendung
    // wieder einschalten. Direkt nach dem Zentrieren wird der Windows-
    // Sichtbarkeitszaehler deshalb noch einmal sicher unter null gebracht.
    public void ReassertHiddenAfterCursorMove()
    {
        if (!_enabled)
            return;

        _lastControllerInput = Stopwatch.GetTimestamp();
        _mouseMonitor?.IgnoreUntil(_lastControllerInput + _syntheticCursorIgnoreTicks);
        if (!NativeMethods.IsCursorVisible())
            return;
        Hide(force: true);
    }

    public void Update(bool controllerModeActive, bool controllerInput)
    {
        if (!_enabled || !controllerModeActive)
        {
            Show();
            return;
        }

        long now = Stopwatch.GetTimestamp();
        if (controllerInput)
        {
            _lastControllerInput = now;
            Hide(force: NativeMethods.IsCursorVisible());
            return;
        }

        long lastPhysicalMouse = _mouseMonitor?.LastPhysicalInput ?? 0;
        if (lastPhysicalMouse > _lastControllerInput && now - lastPhysicalMouse < _hideDelayTicks)
            Show();
        else
            Hide();
    }

    public void Dispose()
    {
        Show();
        _mouseMonitor?.Dispose();
    }

    private void Hide(bool force = false)
    {
        if (_hidden && !force)
            return;

        int adjustments = 0;
        int result;
        do
        {
            result = NativeMethods.ShowCursor(false);
            adjustments++;
        }
        while (result >= 0 && adjustments < 16);
        _hidden = true;
    }

    private void Show()
    {
        if (!_hidden)
            return;

        if (NativeMethods.IsCursorVisible())
        {
            _hidden = false;
            return;
        }

        int adjustments = 0;
        int result;
        do
        {
            result = NativeMethods.ShowCursor(true);
            adjustments++;
        }
        while (result < 0 && adjustments < 16);
        _hidden = false;
    }

    private sealed class PhysicalMouseMonitor : IDisposable
    {
        private const int WH_MOUSE_LL = 14;
        private const int HC_ACTION = 0;
        private const uint LLMHF_INJECTED = 0x00000001;
        private const uint WM_QUIT = 0x0012;

        private readonly HookProcedure _procedure;
        private readonly Thread _thread;
        private readonly ManualResetEventSlim _started = new(false);
        private IntPtr _hook;
        private uint _threadId;
        private long _lastPhysicalInput;
        private long _ignoreUntil;
        private bool _disposed;

        internal PhysicalMouseMonitor()
        {
            _procedure = MouseHook;
            _thread = new Thread(MessageLoop)
            {
                IsBackground = true,
                Name = "DinoController physical mouse monitor"
            };
            _thread.Start();
            _started.Wait(TimeSpan.FromSeconds(2));
        }

        internal bool Available => _hook != IntPtr.Zero;
        internal long LastPhysicalInput => Interlocked.Read(ref _lastPhysicalInput);

        internal void IgnoreUntil(long timestamp)
        {
            Interlocked.Exchange(ref _ignoreUntil, timestamp);
        }

        public void Dispose()
        {
            if (_disposed)
                return;
            _disposed = true;
            if (_threadId != 0)
                PostThreadMessage(_threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
            _thread.Join(TimeSpan.FromSeconds(2));
            _started.Dispose();
        }

        private void MessageLoop()
        {
            _threadId = GetCurrentThreadId();
            _hook = SetWindowsHookEx(WH_MOUSE_LL, _procedure, GetModuleHandle(null), 0);
            _started.Set();
            if (_hook == IntPtr.Zero)
                return;

            try
            {
                while (GetMessage(out Message message, IntPtr.Zero, 0, 0) > 0)
                {
                    TranslateMessage(ref message);
                    DispatchMessage(ref message);
                }
            }
            finally
            {
                UnhookWindowsHookEx(_hook);
                _hook = IntPtr.Zero;
            }
        }

        private IntPtr MouseHook(int code, IntPtr message, IntPtr data)
        {
            if (code == HC_ACTION)
            {
                MouseHookData input = Marshal.PtrToStructure<MouseHookData>(data);
                long now = Stopwatch.GetTimestamp();
                if ((input.Flags & LLMHF_INJECTED) == 0 && now > Interlocked.Read(ref _ignoreUntil))
                    Interlocked.Exchange(ref _lastPhysicalInput, now);
            }
            return CallNextHookEx(_hook, code, message, data);
        }

        private delegate IntPtr HookProcedure(int code, IntPtr message, IntPtr data);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int hookId, HookProcedure procedure, IntPtr module, uint threadId);

        [DllImport("user32.dll")]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);

        [DllImport("user32.dll")]
        private static extern int GetMessage(out Message message, IntPtr window, uint minimum, uint maximum);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref Message message);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref Message message);

        [DllImport("user32.dll")]
        private static extern bool PostThreadMessage(uint threadId, uint message, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string? moduleName);

        [StructLayout(LayoutKind.Sequential)]
        private struct MouseHookData
        {
            internal NativeMethods.Point Point;
            internal uint MouseData;
            internal uint Flags;
            internal uint Time;
            internal UIntPtr ExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Message
        {
            internal IntPtr Window;
            internal uint Value;
            internal UIntPtr WParam;
            internal IntPtr LParam;
            internal uint Time;
            internal NativeMethods.Point Point;
        }
    }
}
