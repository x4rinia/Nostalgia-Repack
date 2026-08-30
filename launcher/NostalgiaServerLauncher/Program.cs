using System.Diagnostics;
using System.Runtime.InteropServices;

namespace NostalgiaServer;

internal static class Program
{
    private const string MutexName = "Local\\NostalgiaServerLauncher-7DF0C61F-2CF0-45F5-A238-04108F27CDA7";
    private const string WindowTitle = "Nostalgia Server";

    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(initiallyOwned: true, MutexName, out bool firstInstance);
        if (!firstInstance)
        {
            BringExistingWindowToFront();
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, eventArgs) => ShowUnexpectedError(eventArgs.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, eventArgs) =>
        {
            if (eventArgs.ExceptionObject is Exception exception)
                ShowUnexpectedError(exception);
        };

        Application.Run(new MainForm());
        GC.KeepAlive(mutex);
    }

    private static void BringExistingWindowToFront()
    {
        IntPtr window = NativeMethods.FindWindow(null, WindowTitle);
        if (window == IntPtr.Zero)
            return;

        NativeMethods.ShowWindow(window, NativeMethods.SW_RESTORE);
        NativeMethods.SetForegroundWindow(window);
    }

    private static void ShowUnexpectedError(Exception exception)
    {
        try
        {
            Trace.WriteLine(exception);
            MessageBox.Show(
                $"Im Nostalgia Server Launcher ist ein unerwarteter Fehler aufgetreten.\n\n{exception.Message}",
                WindowTitle,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        catch
        {
            // Nothing useful remains to do if even the error dialog fails.
        }
    }
}
