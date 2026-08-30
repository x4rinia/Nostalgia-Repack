using Microsoft.Win32.SafeHandles;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace NostalgiaServer;

internal sealed class HiddenChildProcess : IDisposable
{
    private static readonly object StartLock = new();
    private static readonly SemaphoreSlim ConsoleSignalLock = new(1, 1);
    private static readonly NativeMethods.ConsoleCtrlHandler IgnoreConsoleSignal = _ => true;

    private readonly StreamReader _standardOutput;
    private readonly StreamReader _standardError;
    private readonly StreamWriter _standardInput;
    private readonly CancellationTokenSource _readerCancellation = new();
    private bool _disposed;

    private HiddenChildProcess(Process process, StreamReader output, StreamReader error, StreamWriter input)
    {
        Process = process;
        _standardOutput = output;
        _standardError = error;
        _standardInput = input;
    }

    public Process Process { get; }
    public int Id => Process.Id;
    public bool HasExited
    {
        get
        {
            try { return Process.HasExited; }
            catch (InvalidOperationException) { return true; }
        }
    }

    public event Action<string>? OutputReceived;
    public event Action<string>? ErrorReceived;
    public event Action<int>? Exited;

    public static HiddenChildProcess Start(string executable, string arguments, string workingDirectory, bool createProcessGroup = true)
    {
        IntPtr stdoutRead = IntPtr.Zero;
        IntPtr stdoutWrite = IntPtr.Zero;
        IntPtr stderrRead = IntPtr.Zero;
        IntPtr stderrWrite = IntPtr.Zero;
        IntPtr stdinRead = IntPtr.Zero;
        IntPtr stdinWrite = IntPtr.Zero;
        NativeMethods.ProcessInformation processInformation = default;

        lock (StartLock)
        {
            try
            {
                var attributes = new NativeMethods.SecurityAttributes
                {
                    Length = Marshal.SizeOf<NativeMethods.SecurityAttributes>(),
                    InheritHandle = true
                };

                CreateRedirectPipe(out stdoutRead, out stdoutWrite, ref attributes, parentUsesReadEnd: true);
                CreateRedirectPipe(out stderrRead, out stderrWrite, ref attributes, parentUsesReadEnd: true);
                CreateRedirectPipe(out stdinRead, out stdinWrite, ref attributes, parentUsesReadEnd: false);

                var startupInfo = new NativeMethods.StartupInfo
                {
                    Size = Marshal.SizeOf<NativeMethods.StartupInfo>(),
                    Flags = NativeMethods.STARTF_USESTDHANDLES | NativeMethods.STARTF_USESHOWWINDOW,
                    ShowWindow = NativeMethods.SW_HIDE,
                    StdOutput = stdoutWrite,
                    StdError = stderrWrite,
                    StdInput = stdinRead
                };

                string commandLine = $"\"{executable}\"{(string.IsNullOrWhiteSpace(arguments) ? string.Empty : " " + arguments)}";
                uint flags = NativeMethods.CREATE_NEW_CONSOLE | NativeMethods.CREATE_UNICODE_ENVIRONMENT;
                if (createProcessGroup)
                    flags |= NativeMethods.CREATE_NEW_PROCESS_GROUP;

                if (!NativeMethods.CreateProcess(
                        executable,
                        commandLine,
                        IntPtr.Zero,
                        IntPtr.Zero,
                        inheritHandles: true,
                        flags,
                        IntPtr.Zero,
                        workingDirectory,
                        ref startupInfo,
                        out processInformation))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                Close(ref stdoutWrite);
                Close(ref stderrWrite);
                Close(ref stdinRead);

                Process process = Process.GetProcessById((int)processInformation.ProcessId);

                Encoding encoding = GetConsoleEncoding();
                var output = new StreamReader(new FileStream(new SafeFileHandle(stdoutRead, ownsHandle: true), FileAccess.Read, 4096, isAsync: false), encoding, true);
                stdoutRead = IntPtr.Zero;
                var error = new StreamReader(new FileStream(new SafeFileHandle(stderrRead, ownsHandle: true), FileAccess.Read, 4096, isAsync: false), encoding, true);
                stderrRead = IntPtr.Zero;
                var input = new StreamWriter(new FileStream(new SafeFileHandle(stdinWrite, ownsHandle: true), FileAccess.Write, 4096, isAsync: false), encoding)
                {
                    AutoFlush = true,
                    NewLine = "\r\n"
                };
                stdinWrite = IntPtr.Zero;

                var child = new HiddenChildProcess(process, output, error, input);
                child.BeginReading();
                return child;
            }
            catch
            {
                if (processInformation.Process != IntPtr.Zero)
                {
                    try { Process.GetProcessById((int)processInformation.ProcessId).Kill(entireProcessTree: true); }
                    catch { }
                }
                throw;
            }
            finally
            {
                Close(ref stdoutRead);
                Close(ref stdoutWrite);
                Close(ref stderrRead);
                Close(ref stderrWrite);
                Close(ref stdinRead);
                Close(ref stdinWrite);
                Close(ref processInformation.Thread);
                Close(ref processInformation.Process);
            }
        }
    }

    public async Task WriteLineAsync(string line)
    {
        if (HasExited)
            return;

        try
        {
            await _standardInput.WriteLineAsync(line).ConfigureAwait(false);
        }
        catch (IOException) when (HasExited)
        {
        }
        catch (ObjectDisposedException) when (HasExited)
        {
        }
    }

    public async Task<bool> SendCtrlBreakAsync()
    {
        return await SendConsoleSignalAsync(NativeMethods.CTRL_BREAK_EVENT, (uint)Id).ConfigureAwait(false);
    }

    public async Task<bool> SendCtrlCAsync()
    {
        return await SendConsoleSignalAsync(NativeMethods.CTRL_C_EVENT, 0).ConfigureAwait(false);
    }

    private async Task<bool> SendConsoleSignalAsync(uint signal, uint processGroupId)
    {
        if (HasExited)
            return true;

        await ConsoleSignalLock.WaitAsync().ConfigureAwait(false);
        try
        {
            NativeMethods.FreeConsole();
            if (!NativeMethods.AttachConsole((uint)Id))
                return false;

            // Attaching a console resets the process control-handler table, so
            // the launcher protection must be registered after AttachConsole.
            NativeMethods.SetConsoleCtrlHandler(IgnoreConsoleSignal, add: true);
            bool sent = NativeMethods.GenerateConsoleCtrlEvent(signal, processGroupId);
            await Task.Delay(250).ConfigureAwait(false);
            return sent;
        }
        finally
        {
            NativeMethods.FreeConsole();
            NativeMethods.SetConsoleCtrlHandler(IgnoreConsoleSignal, add: false);
            ConsoleSignalLock.Release();
        }
    }

    public async Task<bool> WaitForExitAsync(TimeSpan timeout)
    {
        if (HasExited)
            return true;

        using var timeoutCancellation = new CancellationTokenSource(timeout);
        try
        {
            await Process.WaitForExitAsync(timeoutCancellation.Token).ConfigureAwait(false);
            return true;
        }
        catch (OperationCanceledException)
        {
            return HasExited;
        }
    }

    public void CloseStandardInput()
    {
        try { _standardInput.Close(); }
        catch { }
    }

    public void Kill()
    {
        if (HasExited)
            return;

        Process.Kill(entireProcessTree: true);
    }

    private void BeginReading()
    {
        Process.Exited += (_, _) =>
        {
            int exitCode;
            try { exitCode = Process.ExitCode; }
            catch { exitCode = -1; }
            Exited?.Invoke(exitCode);
        };
        Process.EnableRaisingEvents = true;

        _ = ReadLinesAsync(_standardOutput, line => OutputReceived?.Invoke(line), _readerCancellation.Token);
        _ = ReadLinesAsync(_standardError, line => ErrorReceived?.Invoke(line), _readerCancellation.Token);
    }

    private static async Task ReadLinesAsync(StreamReader reader, Action<string> receiver, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                string? line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false);
                if (line is null)
                    break;
                receiver(line);
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (IOException)
        {
        }
        catch (ObjectDisposedException)
        {
        }
    }

    private static Encoding GetConsoleEncoding()
    {
        try
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            return Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.OEMCodePage);
        }
        catch
        {
            return Encoding.UTF8;
        }
    }

    private static void CreateRedirectPipe(
        out IntPtr readPipe,
        out IntPtr writePipe,
        ref NativeMethods.SecurityAttributes attributes,
        bool parentUsesReadEnd)
    {
        if (!NativeMethods.CreatePipe(out readPipe, out writePipe, ref attributes, 0))
            throw new Win32Exception(Marshal.GetLastWin32Error());

        IntPtr parentHandle = parentUsesReadEnd ? readPipe : writePipe;
        if (!NativeMethods.SetHandleInformation(parentHandle, NativeMethods.HANDLE_FLAG_INHERIT, 0))
        {
            int error = Marshal.GetLastWin32Error();
            Close(ref readPipe);
            Close(ref writePipe);
            throw new Win32Exception(error);
        }
    }

    private static void Close(ref IntPtr handle)
    {
        if (handle == IntPtr.Zero || handle == new IntPtr(-1))
            return;
        NativeMethods.CloseHandle(handle);
        handle = IntPtr.Zero;
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;
        _readerCancellation.Cancel();
        CloseStandardInput();
        _standardOutput.Dispose();
        _standardError.Dispose();
        _readerCancellation.Dispose();
        Process.Dispose();
    }
}
