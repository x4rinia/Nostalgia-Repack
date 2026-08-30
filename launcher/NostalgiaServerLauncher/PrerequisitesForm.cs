using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace NostalgiaServer;

internal sealed class PrerequisitesForm : Form
{
    private readonly string _toolsDirectory;
    private readonly Action<string> _log;
    private readonly TableLayoutPanel _installerList;

    public PrerequisitesForm(string toolsDirectory, Action<string> log)
    {
        _toolsDirectory = Path.GetFullPath(toolsDirectory);
        _log = log;

        Text = "Tools / Voraussetzungen";
        StartPosition = FormStartPosition.CenterParent;
        MinimumSize = new Size(700, 350);
        Size = new Size(780, 420);
        BackColor = Color.FromArgb(14, 18, 24);
        ForeColor = Color.FromArgb(236, 233, 225);
        Font = new Font("Segoe UI", 10F);
        AutoScaleMode = AutoScaleMode.Dpi;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        System.Drawing.Icon? applicationIcon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        if (applicationIcon is not null)
            Icon = applicationIcon;

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            Padding = new Padding(24, 20, 24, 20),
            BackColor = BackColor
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 72));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 56));
        Controls.Add(root);

        var heading = new Panel { Dock = DockStyle.Fill };
        heading.Controls.Add(new Label
        {
            Text = "Tools & Voraussetzungen",
            Dock = DockStyle.Top,
            Height = 33,
            ForeColor = Color.FromArgb(244, 238, 224),
            Font = new Font("Segoe UI Semibold", 17F, FontStyle.Bold)
        });
        heading.Controls.Add(new Label
        {
            Text = "Installiert wird nur das Werkzeug, das ausdrücklich ausgewählt wird.",
            Dock = DockStyle.Bottom,
            Height = 29,
            ForeColor = Color.FromArgb(155, 163, 174)
        });
        root.Controls.Add(heading, 0, 0);

        _installerList = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            BackColor = Color.FromArgb(21, 26, 34),
            CellBorderStyle = TableLayoutPanelCellBorderStyle.Single,
            Padding = new Padding(1)
        };
        _installerList.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 48F));
        _installerList.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 29F));
        _installerList.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 23F));
        root.Controls.Add(_installerList, 0, 1);

        var footer = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false,
            Padding = new Padding(0, 12, 0, 0)
        };
        var closeButton = CreateButton("Schließen", Color.FromArgb(65, 84, 105));
        closeButton.DialogResult = DialogResult.OK;
        var refreshButton = CreateButton("Neu prüfen", Color.FromArgb(137, 91, 43));
        refreshButton.Click += (_, _) => RefreshInstallers();
        footer.Controls.Add(closeButton);
        footer.Controls.Add(refreshButton);
        root.Controls.Add(footer, 0, 2);
        AcceptButton = closeButton;
        CancelButton = closeButton;

        RefreshInstallers();
    }

    private void RefreshInstallers()
    {
        _installerList.SuspendLayout();
        foreach (Control control in _installerList.Controls.Cast<Control>().ToArray())
            control.Dispose();
        _installerList.Controls.Clear();
        _installerList.RowStyles.Clear();

        IReadOnlyList<InstallerEntry> installers = DiscoverInstallers();
        _installerList.RowCount = installers.Count + 1;
        _installerList.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        AddHeader("VORHANDENER INSTALLER", 0);
        AddHeader("STATUS", 1);
        AddHeader("AKTION", 2);

        if (installers.Count == 0)
        {
            _installerList.RowCount = 2;
            _installerList.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            var emptyLabel = CreateCell("Im tools-Ordner wurden keine EXE- oder MSI-Installer gefunden.", Color.FromArgb(214, 169, 82));
            _installerList.Controls.Add(emptyLabel, 0, 1);
            _installerList.SetColumnSpan(emptyLabel, 3);
        }
        else
        {
            for (int index = 0; index < installers.Count; index++)
            {
                InstallerEntry installer = installers[index];
                int row = index + 1;
                _installerList.RowStyles.Add(new RowStyle(SizeType.Percent, 100F / installers.Count));
                _installerList.Controls.Add(CreateCell($"{installer.DisplayName}\n{installer.Architecture} · Installer {installer.InstallerVersion}", Color.FromArgb(229, 230, 228)), 0, row);
                _installerList.Controls.Add(CreateCell(installer.Status, installer.IsInstalled ? Color.FromArgb(77, 190, 120) : Color.FromArgb(224, 175, 72)), 1, row);

                var installButton = CreateButton(installer.IsInstalled ? "Bereits installiert" : "Installer starten", Color.FromArgb(150, 101, 43));
                installButton.Enabled = !installer.IsInstalled;
                installButton.Tag = installer;
                installButton.Click += InstallerButtonOnClick;
                _installerList.Controls.Add(installButton, 2, row);
            }
        }

        _installerList.ResumeLayout(true);
    }

    private IReadOnlyList<InstallerEntry> DiscoverInstallers()
    {
        if (!Directory.Exists(_toolsDirectory))
            return Array.Empty<InstallerEntry>();

        return Directory.EnumerateFiles(_toolsDirectory, "*", SearchOption.TopDirectoryOnly)
            .Where(path => string.Equals(Path.GetExtension(path), ".exe", StringComparison.OrdinalIgnoreCase)
                || string.Equals(Path.GetExtension(path), ".msi", StringComparison.OrdinalIgnoreCase))
            .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
            .Select(DescribeInstaller)
            .ToArray();
    }

    private static InstallerEntry DescribeInstaller(string path)
    {
        FileVersionInfo versionInfo = FileVersionInfo.GetVersionInfo(path);
        string fileName = Path.GetFileName(path);
        string productName = string.IsNullOrWhiteSpace(versionInfo.ProductName) ? fileName : versionInfo.ProductName;
        string architecture = ContainsArchitecture(productName, fileName, "x64") ? "x64"
            : ContainsArchitecture(productName, fileName, "x86") ? "x86"
            : "Architektur unbekannt";
        Version? installerVersion = ParseVersion(versionInfo.ProductVersion) ?? ParseVersion(versionInfo.FileVersion);
        bool isVcRuntime = fileName.StartsWith("VC_redist.", StringComparison.OrdinalIgnoreCase)
            || productName.Contains("Visual C++", StringComparison.OrdinalIgnoreCase);

        if (isVcRuntime && (architecture == "x64" || architecture == "x86"))
        {
            Version? installedVersion = GetInstalledVcRuntimeVersion(architecture);
            bool installed = installedVersion is not null
                && (installerVersion is null || installedVersion >= installerVersion);
            string status = installed
                ? $"Installiert · {installedVersion}"
                : installedVersion is null
                    ? "Nicht erkannt"
                    : $"Update verfügbar · {installedVersion}";
            return new InstallerEntry(path, productName, architecture, installerVersion?.ToString() ?? "unbekannt", status, installed);
        }

        return new InstallerEntry(path, productName, architecture, installerVersion?.ToString() ?? "unbekannt", "Status nicht automatisch ermittelbar", false);
    }

    private static bool ContainsArchitecture(string productName, string fileName, string architecture) =>
        productName.Contains($"({architecture})", StringComparison.OrdinalIgnoreCase)
        || fileName.Contains($".{architecture}", StringComparison.OrdinalIgnoreCase)
        || fileName.Contains($"_{architecture}", StringComparison.OrdinalIgnoreCase);

    private static Version? GetInstalledVcRuntimeVersion(string architecture)
    {
        var candidates = new[]
        {
            (RegistryView.Registry64, $"SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\{architecture}"),
            (RegistryView.Registry64, $"SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\{architecture}"),
            (RegistryView.Registry32, $"SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\{architecture}")
        };

        foreach ((RegistryView view, string subKey) in candidates)
        {
            using RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            using RegistryKey? key = baseKey.OpenSubKey(subKey);
            if (key?.GetValue("Installed") is not object installed || Convert.ToInt32(installed) != 1)
                continue;
            Version? version = ParseVersion(key.GetValue("Version")?.ToString());
            if (version is not null)
                return version;
        }
        return null;
    }

    private static Version? ParseVersion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return null;
        Match match = Regex.Match(value, @"\d+(?:\.\d+){1,3}");
        return match.Success && Version.TryParse(match.Value, out Version? version) ? version : null;
    }

    private void InstallerButtonOnClick(object? sender, EventArgs eventArgs)
    {
        if (sender is not Button { Tag: InstallerEntry installer })
            return;

        string toolsRoot = _toolsDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string installerPath = Path.GetFullPath(installer.FilePath);
        if (!installerPath.StartsWith(toolsRoot, StringComparison.OrdinalIgnoreCase) || !File.Exists(installerPath))
        {
            MessageBox.Show(this, "Der ausgewählte Installer befindet sich nicht mehr im tools-Ordner.", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = installerPath,
                WorkingDirectory = _toolsDirectory,
                UseShellExecute = true
            });
            _log($"[{DateTime.Now:HH:mm:ss}] [System] Installer ausgewählt: {Path.GetFileName(installerPath)}");
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, $"Der Installer konnte nicht gestartet werden.\n\n{exception.Message}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void AddHeader(string text, int column)
    {
        _installerList.Controls.Add(CreateCell(text, Color.FromArgb(157, 164, 174), FontStyle.Bold), column, 0);
    }

    private Label CreateCell(string text, Color color, FontStyle style = FontStyle.Regular) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        ForeColor = color,
        Font = new Font(Font, style),
        Padding = new Padding(10, 7, 8, 4),
        TextAlign = ContentAlignment.MiddleLeft,
        AutoEllipsis = true
    };

    private static Button CreateButton(string text, Color color)
    {
        var button = new Button
        {
            Text = text,
            Size = new Size(150, 34),
            Margin = new Padding(7),
            FlatStyle = FlatStyle.Flat,
            BackColor = color,
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI Semibold", 9F, FontStyle.Bold)
        };
        button.FlatAppearance.BorderSize = 0;
        return button;
    }

    private sealed record InstallerEntry(
        string FilePath,
        string DisplayName,
        string Architecture,
        string InstallerVersion,
        string Status,
        bool IsInstalled);
}
