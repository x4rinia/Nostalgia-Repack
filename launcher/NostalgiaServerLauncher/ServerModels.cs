namespace NostalgiaServer;

internal enum ServerComponent
{
    Database,
    Realm,
    World,
    Web
}

internal enum ComponentState
{
    Stopped,
    Starting,
    Running,
    Stopping,
    StoppedUnexpectedly,
    Error
}

internal sealed record StatusChangedEventArgs(ServerComponent Component, ComponentState State, string? Detail = null);

internal sealed class LauncherException : Exception
{
    public LauncherException(string message) : base(message)
    {
    }

    public LauncherException(string message, Exception innerException) : base(message, innerException)
    {
    }
}
