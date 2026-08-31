namespace NostalgiaServer;

internal sealed class LauncherLayout
{
    public LauncherLayout(string baseDirectory)
    {
        BaseDirectory = Path.GetFullPath(baseDirectory);
        DatabaseDirectory = Path.Combine(BaseDirectory, "MariaDB");
        ServerDirectory = Path.Combine(BaseDirectory, "Server");
        DatabaseExecutable = Path.Combine(DatabaseDirectory, "bin", "mariadbd.exe");
        DatabaseAdminExecutable = Path.Combine(DatabaseDirectory, "bin", "mariadb-admin.exe");
        DatabaseConfiguration = Path.Combine(DatabaseDirectory, "my.ini");
        RealmExecutable = Path.Combine(ServerDirectory, "realmd.exe");
        RealmConfiguration = Path.Combine(ServerDirectory, "realmd.conf");
        WorldExecutable = Path.Combine(ServerDirectory, "mangosd.exe");
        WorldConfiguration = Path.Combine(ServerDirectory, "mangosd.conf");
        WebDirectory = Path.Combine(BaseDirectory, "Web");
        ApacheDirectory = Path.Combine(WebDirectory, "Apache");
        WebExecutable = Path.Combine(ApacheDirectory, "bin", "httpd.exe");
        WebConfiguration = Path.Combine(ApacheDirectory, "conf", "httpd.conf");
        ToolsDirectory = Path.Combine(BaseDirectory, "tools");
        ControllerBridgeExecutable = Path.Combine(ToolsDirectory, "DinoControllerBridge.exe");
        ClientDirectory = Path.Combine(BaseDirectory, "client");
        WowExecutable = Path.Combine(ClientDirectory, "WoW.exe");
        AddOnsDirectory = Path.Combine(ClientDirectory, "Interface", "AddOns");
    }

    public string BaseDirectory { get; }
    public string DatabaseDirectory { get; }
    public string ServerDirectory { get; }
    public string DatabaseExecutable { get; }
    public string DatabaseAdminExecutable { get; }
    public string DatabaseConfiguration { get; }
    public string RealmExecutable { get; }
    public string RealmConfiguration { get; }
    public string WorldExecutable { get; }
    public string WorldConfiguration { get; }
    public string WebDirectory { get; }
    public string ApacheDirectory { get; }
    public string WebExecutable { get; }
    public string WebConfiguration { get; }
    public string ToolsDirectory { get; }
    public string ControllerBridgeExecutable { get; }
    public string ClientDirectory { get; }
    public string WowExecutable { get; }
    public string AddOnsDirectory { get; }
    public Uri WebAddress { get; } = new("http://127.0.0.1:8080/");

    public void Validate()
    {
        RequireFile("MariaDB", DatabaseExecutable);
        RequireFile("MariaDB-Konfiguration", DatabaseConfiguration);
        RequireFile("MariaDB-Verwaltungsprogramm", DatabaseAdminExecutable);
        RequireFile("Realmserver", RealmExecutable);
        RequireFile("Realmserver-Konfiguration", RealmConfiguration);
        RequireFile("Worldserver", WorldExecutable);
        RequireFile("Worldserver-Konfiguration", WorldConfiguration);
        RequireFile("Webserver", WebExecutable);
        RequireFile("Webserver-Konfiguration", WebConfiguration);
    }

    private void RequireFile(string description, string path)
    {
        if (File.Exists(path))
            return;

        string relativePath = Path.GetRelativePath(BaseDirectory, path);
        throw new LauncherException($"{description} konnte nicht gefunden werden.\n\nDatei nicht gefunden:\n{relativePath}");
    }
}
