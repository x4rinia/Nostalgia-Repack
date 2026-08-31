using System.Collections.Concurrent;
using System.Diagnostics;
using System.Drawing.Drawing2D;

namespace NostalgiaServer;

internal sealed class MainForm : Form
{
    private const int MaximumLogLines = 1500;
    private const int MaximumLogCharacters = 300_000;

    private readonly LauncherLayout _layout;
    private readonly ServerManager _manager;
    private readonly Dictionary<ServerComponent, StatusRow> _statusRows = new();
    private readonly ConcurrentQueue<string> _pendingLogLines = new();
    private readonly System.Windows.Forms.Timer _logTimer;
    private readonly RichTextBox _logBox;
    private readonly Button _startButton;
    private readonly Button _stopButton;
    private readonly Button _webButton;
    private readonly Button _wowButton;
    private readonly Button _addonsButton;
    private readonly Button _toolsButton;
    private readonly Button _infoButton;
    private readonly Label _activityLabel;
    private bool _allowClose;
    private bool _closeInProgress;
    private HiddenChildProcess? _controllerBridge;

    public MainForm()
    {
        Text = "Nostalgia Server";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(840, 700);
        Size = new Size(960, 820);
        BackColor = Color.FromArgb(14, 18, 24);
        ForeColor = Color.FromArgb(236, 233, 225);
        Font = new Font("Segoe UI", 10F);
        AutoScaleMode = AutoScaleMode.Dpi;
        System.Drawing.Icon? applicationIcon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        if (applicationIcon is not null)
            Icon = applicationIcon;

        _layout = new LauncherLayout(AppContext.BaseDirectory);
        _manager = new ServerManager(_layout);
        _manager.StatusChanged += ManagerOnStatusChanged;
        _manager.LogReceived += QueueLog;

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            Padding = new Padding(32, 26, 32, 28),
            BackColor = BackColor
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 78));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 172));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 152));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
        Controls.Add(root);

        root.Controls.Add(BuildHeader(), 0, 0);
        root.Controls.Add(BuildStatusPanel(), 0, 1);

        _startButton = CreateButton("Server starten", Color.FromArgb(43, 151, 93));
        _stopButton = CreateButton("Server beenden", Color.FromArgb(161, 61, 65));
        _wowButton = CreateButton("WoW starten", Color.FromArgb(174, 126, 50));
        _addonsButton = CreateButton("AddOns öffnen", Color.FromArgb(65, 84, 105));
        _webButton = CreateButton("Webseite öffnen", Color.FromArgb(137, 91, 43));
        _toolsButton = CreateButton("Tools / Voraussetzungen", Color.FromArgb(65, 84, 105));
        _infoButton = CreateButton("Server Info", Color.FromArgb(65, 84, 105));

        _stopButton.Enabled = false;
        _wowButton.Enabled = false;
        _webButton.Enabled = false;
        _startButton.Click += async (_, _) => await StartServerAsync();
        _stopButton.Click += async (_, _) => await StopServerAsync();
        _wowButton.Click += (_, _) => StartWow();
        _addonsButton.Click += (_, _) => OpenAddOns();
        _webButton.Click += (_, _) => OpenWebsite();
        _toolsButton.Click += (_, _) => OpenPrerequisites();
        _infoButton.Click += (_, _) => MessageBox.Show(this, "Datenbank:\nBenutzer: vmangos\nPasswort: vmangos\nPort: 3307\n\nAdmin (GM-Account):\nAccount: Admin\nPasswort: Admin", "Nostalgia Server Info", MessageBoxButtons.OK, MessageBoxIcon.Information);
        
        root.Controls.Add(BuildActionPanel(), 0, 2);

        var logHeader = new Panel { Dock = DockStyle.Fill };
        logHeader.Controls.Add(new Label
        {
            Text = "SERVER LOG",
            Dock = DockStyle.Left,
            AutoSize = true,
            ForeColor = Color.FromArgb(145, 153, 164),
            Font = new Font(Font, FontStyle.Bold),
            Padding = new Padding(0, 10, 0, 0)
        });
        _activityLabel = new Label
        {
            Text = "Bereit",
            Dock = DockStyle.Right,
            AutoSize = true,
            ForeColor = Color.FromArgb(145, 153, 164),
            Padding = new Padding(0, 10, 0, 0)
        };
        logHeader.Controls.Add(_activityLabel);
        root.Controls.Add(logHeader, 0, 3);

        _logBox = new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            BackColor = Color.FromArgb(7, 10, 14),
            ForeColor = Color.FromArgb(207, 211, 216),
            BorderStyle = BorderStyle.None,
            Font = new Font("Cascadia Mono", 9F),
            DetectUrls = false,
            WordWrap = true,
            ScrollBars = RichTextBoxScrollBars.Vertical,
            TabStop = false
        };
        root.Controls.Add(_logBox, 0, 4);

        var footerLabel = new Label
        {
            Text = "Version 1.0 · X4rinia 2026",
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.BottomRight,
            ForeColor = Color.FromArgb(100, 108, 120),
            Font = new Font("Segoe UI", 8.5F)
        };
        root.Controls.Add(footerLabel, 0, 5);

        _logTimer = new System.Windows.Forms.Timer { Interval = 120 };
        _logTimer.Tick += (_, _) => FlushPendingLogs();
        _logTimer.Start();

        FormClosing += OnFormClosing;
        QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] Bereit. Basisordner: {_layout.BaseDirectory}");
    }

    private Control BuildHeader()
    {
        var panel = new Panel { Dock = DockStyle.Fill };
        panel.Controls.Add(new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 2,
            BackColor = Color.FromArgb(184, 139, 67)
        });
        panel.Controls.Add(new Label
        {
            Text = "Nostalgia Server",
            AutoSize = true,
            Location = new Point(0, 0),
            ForeColor = Color.FromArgb(245, 242, 236),
            Font = new Font("Segoe UI Semibold", 22F, FontStyle.Bold)
        });
        panel.Controls.Add(new Label
        {
            Text = "Vanilla Server Launcher",
            AutoSize = true,
            Location = new Point(3, 43),
            ForeColor = Color.FromArgb(159, 166, 178),
            Font = new Font("Segoe UI", 9.5F)
        });
        return panel;
    }

    private Control BuildStatusPanel()
    {
        var panel = new StatusCard
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            BackColor = Color.FromArgb(22, 27, 35),
            Padding = new Padding(20, 10, 20, 10),
            Margin = new Padding(0, 6, 0, 6)
        };
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 25F));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 25F));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 25F));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 25F));
        panel.Controls.Add(AddStatusRow(ServerComponent.Database, "Datenbank"), 0, 0);
        panel.Controls.Add(AddStatusRow(ServerComponent.Realm, "Realm"), 0, 1);
        panel.Controls.Add(AddStatusRow(ServerComponent.World, "World"), 0, 2);
        panel.Controls.Add(AddStatusRow(ServerComponent.Web, "Web"), 0, 3);
        return panel;
    }

    private Control AddStatusRow(ServerComponent component, string name)
    {
        var container = new Panel { Dock = DockStyle.Fill };
        var dot = new StatusDot
        {
            Size = new Size(18, 18),
            Location = new Point(0, 7),
            DotColor = Color.FromArgb(198, 69, 69)
        };
        var nameLabel = new Label
        {
            Text = name,
            AutoSize = true,
            Location = new Point(32, 5),
            ForeColor = Color.FromArgb(224, 228, 234),
            Font = new Font(Font, FontStyle.Bold)
        };
        var stateLabel = new Label
        {
            Text = "Gestoppt",
            AutoSize = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            ForeColor = Color.FromArgb(198, 69, 69),
            TextAlign = ContentAlignment.MiddleRight
        };

        Button? actionButton = null;
        if (component == ServerComponent.World)
        {
            actionButton = new Button
            {
                Text = "World starten",
                Size = new Size(110, 24),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(43, 151, 93),
                ForeColor = Color.White,
                Cursor = Cursors.Hand,
                Font = new Font("Segoe UI Semibold", 8.5F, FontStyle.Bold)
            };
            actionButton.FlatAppearance.BorderSize = 0;
            actionButton.Click += async (_, _) => await HandleWorldActionAsync();
            container.Controls.Add(actionButton);
        }

        int stateLabelRightPadding = 0;
        
        stateLabel.Location = new Point(Math.Max(0, container.Width - stateLabel.Width - stateLabelRightPadding), 5);
        if (actionButton != null)
            actionButton.Location = new Point(Math.Max(0, (container.Width - actionButton.Width) / 2), Math.Max(0, (container.Height - actionButton.Height) / 2));

        container.Resize += (_, _) => 
        {
            stateLabel.Location = new Point(Math.Max(0, container.ClientSize.Width - stateLabel.Width - stateLabelRightPadding), 5);
            if (actionButton != null)
                actionButton.Location = new Point(Math.Max(0, (container.ClientSize.Width - actionButton.Width) / 2), Math.Max(0, (container.ClientSize.Height - actionButton.Height) / 2));
        };
        
        container.Controls.Add(dot);
        container.Controls.Add(nameLabel);
        container.Controls.Add(stateLabel);
        _statusRows[component] = new StatusRow(dot, stateLabel, actionButton);
        return container;
    }

    private async Task HandleWorldActionAsync()
    {
        if (_manager.IsBusy) return;

        bool isRunning = _manager.States.TryGetValue(ServerComponent.World, out var state) && state == ComponentState.Running;
        
        if (isRunning)
        {
            if (MessageBox.Show(this, "Möchtest du den Worldserver wirklich neu starten?", "Worldserver neu starten", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;
            
            SetBusy(true, "World wird neu gestartet …");
            try
            {
                await _manager.RestartWorldStandaloneAsync();
            }
            catch (Exception ex)
            {
                QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] FEHLER beim Neustart des Worldservers: {ex.Message}");
                MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                SetBusy(false, "Server läuft");
                UpdateButtons();
            }
        }
        else
        {
            SetBusy(true, "World wird gestartet …");
            try
            {
                await _manager.StartWorldStandaloneAsync();
            }
            catch (Exception ex)
            {
                QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] FEHLER beim Start des Worldservers: {ex.Message}");
                MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                SetBusy(false, _manager.HasManagedProcesses ? "Server läuft" : "Bereit");
                UpdateButtons();
            }
        }
    }

    private static Button CreateButton(string text, Color color)
    {
        var button = new RoundedButton
        {
            Text = text,
            Size = new Size(178, 42),
            Margin = new Padding(0, 0, 0, 8),
            FlatStyle = FlatStyle.Flat,
            BackColor = color,
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold)
        };
        button.FlatAppearance.BorderSize = 0;
        button.FlatAppearance.MouseOverBackColor = ControlPaint.Light(color, 0.06F);
        button.FlatAppearance.MouseDownBackColor = ControlPaint.Dark(color, 0.05F);
        return button;
    }

    private Control BuildActionPanel()
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            Padding = new Padding(0, 8, 0, 8),
            BackColor = BackColor
        };
        for (int index = 0; index < 4; index++)
            panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25F));
        panel.Controls.Add(BuildActionGroup("SERVER", _startButton, _stopButton), 0, 0);
        panel.Controls.Add(BuildActionGroup("SPIEL", _wowButton, _addonsButton), 1, 0);
        panel.Controls.Add(BuildActionGroup("WEB", _webButton), 2, 0);
        panel.Controls.Add(BuildActionGroup("SYSTEM", _toolsButton, _infoButton), 3, 0);
        return panel;
    }

    private Control BuildActionGroup(string title, params Button[] buttons)
    {
        var card = new ActionCard
        {
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 10, 0),
            Padding = new Padding(12, 9, 12, 7),
            BackColor = Color.FromArgb(20, 25, 32)
        };
        var titleLabel = new Label
        {
            Text = title,
            Dock = DockStyle.Top,
            Height = 23,
            ForeColor = Color.FromArgb(184, 139, 67),
            Font = new Font("Segoe UI Semibold", 8.5F, FontStyle.Bold)
        };
        var flow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(0, 4, 0, 0)
        };
        flow.Controls.AddRange(buttons);
        card.Controls.Add(flow);
        card.Controls.Add(titleLabel);
        return card;
    }

    private void StartWow()
    {
        if (!IsGameServerRunning())
        {
            MessageBox.Show(this, "Datenbank, Realm und World müssen laufen, bevor WoW gestartet werden kann.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (!File.Exists(_layout.WowExecutable))
        {
            MessageBox.Show(this, $"WoW konnte nicht gefunden werden.\n\nDatei nicht gefunden:\n{Path.GetRelativePath(_layout.BaseDirectory, _layout.WowExecutable)}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        try
        {
            StartControllerBridgeIfAvailable();
            Process.Start(new ProcessStartInfo
            {
                FileName = _layout.WowExecutable,
                WorkingDirectory = _layout.ClientDirectory,
                UseShellExecute = true
            });
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Spiel] WoW wurde gestartet.");
        }
        catch (Exception exception)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Spiel] WoW konnte nicht gestartet werden: {exception.Message}");
            MessageBox.Show(this, $"WoW konnte nicht gestartet werden.\n\n{exception.Message}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void StartControllerBridgeIfAvailable()
    {
        if (!File.Exists(_layout.ControllerBridgeExecutable))
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Controller] Bruecke nicht installiert; WoW startet ohne Controller-Mapping.");
            return;
        }

        if (_controllerBridge != null && !_controllerBridge.HasExited)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Controller] DinoControllerBridge läuft bereits im Hintergrund.");
            return;
        }

        if (Process.GetProcessesByName("DinoControllerBridge").Length > 0)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Controller] DinoControllerBridge läuft bereits im Hintergrund.");
            return;
        }

        try
        {
            _controllerBridge = HiddenChildProcess.Start(_layout.ControllerBridgeExecutable, string.Empty, _layout.ToolsDirectory, createProcessGroup: false);
            _controllerBridge.Exited += (exitCode) =>
            {
                QueueLog($"[{DateTime.Now:HH:mm:ss}] [Controller] DinoControllerBridge wurde beendet.");
            };
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Controller] DinoControllerBridge wurde im Hintergrund gestartet.");
        }
        catch (Exception exception)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Controller] Bruecke konnte nicht gestartet werden: {exception.Message}");
        }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (_controllerBridge != null && !_controllerBridge.HasExited)
        {
            try { _controllerBridge.Kill(); } catch { }
        }
        base.OnFormClosing(e);
    }

    private void OpenAddOns()
    {
        if (!Directory.Exists(_layout.AddOnsDirectory))
        {
            MessageBox.Show(this, $"Der AddOns-Ordner wurde nicht gefunden.\n\nOrdner nicht gefunden:\n{Path.GetRelativePath(_layout.BaseDirectory, _layout.AddOnsDirectory)}", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo { FileName = _layout.AddOnsDirectory, UseShellExecute = true });
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Spiel] AddOns-Ordner wurde geöffnet.");
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, $"Der AddOns-Ordner konnte nicht geöffnet werden.\n\n{exception.Message}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OpenPrerequisites()
    {
        if (!Directory.Exists(_layout.ToolsDirectory))
        {
            MessageBox.Show(this, $"Der Tools-Ordner wurde nicht gefunden.\n\nOrdner nicht gefunden:\n{Path.GetRelativePath(_layout.BaseDirectory, _layout.ToolsDirectory)}", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        using var dialog = new PrerequisitesForm(_layout.ToolsDirectory, QueueLog);
        dialog.ShowDialog(this);
    }

    private void OpenWebsite()
    {
        if (!IsWebRunning())
        {
            MessageBox.Show(this, "Der Webserver läuft derzeit nicht.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = _layout.WebAddress.AbsoluteUri,
                UseShellExecute = true
            });
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Web] Öffne {_layout.WebAddress} im Standardbrowser.");
        }
        catch (Exception exception)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Web] Webseite konnte nicht geöffnet werden: {exception.Message}");
            MessageBox.Show(this, $"Die Webseite konnte nicht geöffnet werden.\n\n{exception.Message}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private bool PromptAndKillExistingProcesses()
    {
        var processNames = new[] { "mariadbd", "mysqld", "realmd", "mangosd", "httpd", "php-cgi" };
        var runningProcesses = new Dictionary<int, Process>();

        // 1. Suche nach Namen
        foreach (var name in processNames)
        {
            foreach (var p in Process.GetProcessesByName(name))
            {
                runningProcesses[p.Id] = p;
            }
        }

        // 2. Suche nach belegten Ports (3307=DB, 3724=Realm, 8085=World, 8080=Web)
        try
        {
            var ports = new[] { 3307, 3724, 8085, 8080 };
            var startInfo = new ProcessStartInfo
            {
                FileName = "netstat",
                Arguments = "-ano",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var netstat = Process.Start(startInfo);
            if (netstat != null)
            {
                string output = netstat.StandardOutput.ReadToEnd();
                netstat.WaitForExit();
                var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var line in lines)
                {
                    var parts = line.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length >= 5 && parts[0] == "TCP")
                    {
                        string localAddress = parts[1];
                        string pidStr = parts[4];
                        foreach (int port in ports)
                        {
                            if (localAddress.EndsWith(":" + port) || localAddress.EndsWith("]" + port))
                            {
                                if (int.TryParse(pidStr, out int pid) && pid > 0 && pid != Process.GetCurrentProcess().Id)
                                {
                                    if (!runningProcesses.ContainsKey(pid))
                                    {
                                        try
                                        {
                                            runningProcesses[pid] = Process.GetProcessById(pid);
                                        }
                                        catch { }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        catch { }

        if (runningProcesses.Count > 0)
        {
            string processList = string.Join(", ", runningProcesses.Values.Select(p => $"{p.ProcessName}.exe (PID {p.Id})"));
            var result = MessageBox.Show(this,
                $"Es laufen bereits Server-Prozesse oder Prozesse blockieren die nötigen Ports:\n{processList}\n\nMöchtest du diese Prozesse beenden, um den Server starten zu können?",
                "Prozesse beenden",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning);

            if (result == DialogResult.Yes)
            {
                foreach (var process in runningProcesses.Values)
                {
                    try
                    {
                        process.Kill();
                        process.WaitForExit(2000);
                    }
                    catch { }
                    finally { process.Dispose(); }
                }
                return true;
            }
            else
            {
                foreach (var process in runningProcesses.Values) process.Dispose();
                return false;
            }
        }
        return true;
    }

    private async Task StartServerAsync()
    {
        if (!PromptAndKillExistingProcesses())
        {
            return;
        }

        SetBusy(true, "Server wird gestartet …");
        try
        {
            await _manager.StartAsync();
            _activityLabel.Text = "Server läuft";
        }
        catch (LauncherException exception)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] FEHLER: {exception.Message.Replace(Environment.NewLine, " ")}");
            MessageBox.Show(this, exception.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            _activityLabel.Text = "Start fehlgeschlagen";
        }
        catch (Exception exception)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] FEHLER: {exception.Message}");
            MessageBox.Show(this, $"Der Server konnte nicht gestartet werden.\n\n{exception.Message}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            _activityLabel.Text = "Start fehlgeschlagen";
        }
        finally
        {
            SetBusy(false, _activityLabel.Text);
        }
    }

    private async Task StopServerAsync()
    {
        SetBusy(true, "Server wird beendet …");
        try
        {
            await _manager.StopAsync();
            _activityLabel.Text = "Server gestoppt";
        }
        catch (Exception exception)
        {
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] FEHLER beim Beenden: {exception.Message}");
            MessageBox.Show(this, $"Beim Beenden ist ein Fehler aufgetreten. Der Launcher hat seine Fallbacks ausgeführt.\n\n{exception.Message}", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            _activityLabel.Text = "Stop mit Fehlern beendet";
        }
        finally
        {
            SetBusy(false, _activityLabel.Text);
        }
    }

    private async void OnFormClosing(object? sender, FormClosingEventArgs eventArgs)
    {
        if (_allowClose)
            return;

        eventArgs.Cancel = true;
        if (_closeInProgress)
            return;
        _closeInProgress = true;

        if (_manager.HasManagedProcesses || _manager.IsBusy)
        {
            SetBusy(true, "Server wird vor dem Schließen beendet …");
            QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] Fenster wird geschlossen; kontrollierter Shutdown beginnt.");
            try
            {
                await _manager.StopAsync();
            }
            catch (Exception exception)
            {
                QueueLog($"[{DateTime.Now:HH:mm:ss}] [Launcher] FEHLER beim Shutdown: {exception.Message}");
                MessageBox.Show(
                    this,
                    $"Beim Herunterfahren trat ein Fehler auf. Die definierten Fallbacks wurden ausgeführt.\n\n{exception.Message}",
                    Text,
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }
        }

        FlushPendingLogs();
        _allowClose = true;
        Close();
    }

    private void ManagerOnStatusChanged(StatusChangedEventArgs eventArgs)
    {
        if (IsDisposed)
            return;
        if (InvokeRequired)
        {
            BeginInvoke(() => ManagerOnStatusChanged(eventArgs));
            return;
        }

        if (!_statusRows.TryGetValue(eventArgs.Component, out StatusRow? row))
            return;

        (string text, Color color) = eventArgs.State switch
        {
            ComponentState.Starting => ("Startet …", Color.FromArgb(224, 175, 72)),
            ComponentState.Running => ("Läuft", Color.FromArgb(65, 190, 112)),
            ComponentState.Stopping => ("Wird beendet …", Color.FromArgb(224, 175, 72)),
            ComponentState.StoppedUnexpectedly => ("Unerwartet beendet", Color.FromArgb(224, 104, 72)),
            ComponentState.Error => ("Fehler", Color.FromArgb(198, 69, 69)),
            _ => ("Gestoppt", Color.FromArgb(198, 69, 69))
        };
        row.Label.Text = text;
        row.Label.ForeColor = color;
        row.Dot.DotColor = color;
        row.Label.Location = new Point(Math.Max(0, row.Label.Parent!.ClientSize.Width - row.Label.Width), 5);
        
        if (row.ActionButton != null)
        {
            if (eventArgs.State == ComponentState.Running)
            {
                row.ActionButton.Text = "Neu starten";
                row.ActionButton.BackColor = Color.FromArgb(224, 175, 72);
            }
            else
            {
                row.ActionButton.Text = "World starten";
                row.ActionButton.BackColor = Color.FromArgb(43, 151, 93);
            }
        }
        
        UpdateButtons();
    }

    private void SetBusy(bool busy, string activity)
    {
        _activityLabel.Text = activity;
        _startButton.Enabled = !busy && !_manager.HasManagedProcesses;
        _stopButton.Enabled = !busy && _manager.HasManagedProcesses;
        _wowButton.Enabled = !busy && !_closeInProgress && IsGameServerRunning();
        _webButton.Enabled = !busy && !_closeInProgress && IsWebRunning();
        _addonsButton.Enabled = !_closeInProgress;
        _toolsButton.Enabled = !_closeInProgress;
        _infoButton.Enabled = !_closeInProgress;
        UseWaitCursor = busy;
        
        if (_statusRows.TryGetValue(ServerComponent.World, out var row) && row.ActionButton != null)
        {
            var state = _manager.States.TryGetValue(ServerComponent.World, out var s) ? s : ComponentState.Stopped;
            bool isBusyComponent = state == ComponentState.Starting || state == ComponentState.Stopping;
            row.ActionButton.Enabled = !busy && !isBusyComponent;
        }
    }

    private void UpdateButtons()
    {
        bool busy = _manager.IsBusy || _closeInProgress;
        _startButton.Enabled = !busy && !_manager.HasManagedProcesses;
        _stopButton.Enabled = !busy && _manager.HasManagedProcesses;
        _wowButton.Enabled = !busy && IsGameServerRunning();
        _webButton.Enabled = !busy && IsWebRunning();
        _addonsButton.Enabled = !_closeInProgress;
        _toolsButton.Enabled = !_closeInProgress;
        _infoButton.Enabled = !_closeInProgress;

        if (_statusRows.TryGetValue(ServerComponent.World, out var row) && row.ActionButton != null)
        {
            var state = _manager.States.TryGetValue(ServerComponent.World, out var s) ? s : ComponentState.Stopped;
            bool isBusyComponent = state == ComponentState.Starting || state == ComponentState.Stopping;
            row.ActionButton.Enabled = !busy && !isBusyComponent;
        }
    }

    private bool IsWebRunning() =>
        _manager.States.TryGetValue(ServerComponent.Web, out ComponentState state) && state == ComponentState.Running;

    private bool IsGameServerRunning() =>
        IsRunning(ServerComponent.Database) && IsRunning(ServerComponent.Realm) && IsRunning(ServerComponent.World);

    private bool IsRunning(ServerComponent component) =>
        _manager.States.TryGetValue(component, out ComponentState state) && state == ComponentState.Running;

    private void QueueLog(string line)
    {
        // Ein BEL-Steuerzeichen aus umgeleiteten Konsolenausgaben darf nicht
        // als Windows-Systemton bis zur RichEdit-Loganzeige gelangen.
        _pendingLogLines.Enqueue(line.Replace("\a", string.Empty));
    }

    private void FlushPendingLogs()
    {
        if (_logBox.IsDisposed)
            return;

        var batch = new List<string>(128);
        while (batch.Count < 500 && _pendingLogLines.TryDequeue(out string? line))
            batch.Add(line);
        if (batch.Count == 0)
            return;

        bool wasAtEnd = _logBox.SelectionStart >= Math.Max(0, _logBox.TextLength - 2);
        _logBox.AppendText(string.Join(Environment.NewLine, batch) + Environment.NewLine);
        TrimLog();
        if (wasAtEnd)
        {
            // Ohne Caret-/Fokuswechsel ans Ende scrollen. RichEdit kann beim
            // Bewegen des Carets in einer schreibgeschuetzten Box sonst den
            // Windows-Hinweiston ausloesen.
            NativeMethods.SendMessage(
                _logBox.Handle,
                NativeMethods.WM_VSCROLL,
                new IntPtr(NativeMethods.SB_BOTTOM),
                IntPtr.Zero);
        }
    }

    private void TrimLog()
    {
        string[] lines = _logBox.Lines;
        int removeLineCount = Math.Max(0, lines.Length - MaximumLogLines);
        int removeCharacters = Math.Max(0, _logBox.TextLength - MaximumLogCharacters);
        if (removeLineCount == 0 && removeCharacters == 0)
            return;

        int cutAt = removeCharacters;
        if (removeLineCount > 0)
        {
            int lineCut = 0;
            for (int index = 0; index < removeLineCount && index < lines.Length; index++)
                lineCut += lines[index].Length + Environment.NewLine.Length;
            cutAt = Math.Max(cutAt, lineCut);
        }

        if (cutAt < _logBox.TextLength)
        {
            int nextLine = _logBox.Text.IndexOf('\n', cutAt);
            if (nextLine >= 0)
                cutAt = nextLine + 1;
        }
        _logBox.Select(0, Math.Min(cutAt, _logBox.TextLength));
        _logBox.SelectedText = string.Empty;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _logTimer?.Dispose();
            _manager.Dispose();
        }
        base.Dispose(disposing);
    }

    private sealed record StatusRow(StatusDot Dot, Label Label, Button? ActionButton = null);

    private sealed class StatusCard : TableLayoutPanel
    {
        public StatusCard()
        {
            DoubleBuffered = true;
        }

        protected override void OnPaint(PaintEventArgs eventArgs)
        {
            base.OnPaint(eventArgs);
            eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var pen = new Pen(Color.FromArgb(53, 59, 70));
            using GraphicsPath path = RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), 10);
            eventArgs.Graphics.DrawPath(pen, path);
        }
    }

    private sealed class ActionCard : Panel
    {
        public ActionCard()
        {
            DoubleBuffered = true;
        }

        protected override void OnPaint(PaintEventArgs eventArgs)
        {
            base.OnPaint(eventArgs);
            eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var pen = new Pen(Color.FromArgb(45, 52, 63));
            using GraphicsPath path = RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), 9);
            eventArgs.Graphics.DrawPath(pen, path);
        }
    }

    private sealed class RoundedButton : Button
    {
        protected override void OnResize(EventArgs eventArgs)
        {
            base.OnResize(eventArgs);
            if (Width <= 0 || Height <= 0)
                return;
            using GraphicsPath path = RoundedRectangle(new Rectangle(0, 0, Width, Height), 9);
            Region?.Dispose();
            Region = new Region(path);
        }
    }

    private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
    {
        int diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private sealed class StatusDot : Control
    {
        private Color _dotColor;

        public Color DotColor
        {
            get => _dotColor;
            set
            {
                _dotColor = value;
                Invalidate();
            }
        }

        public StatusDot()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        }

        protected override void OnPaint(PaintEventArgs eventArgs)
        {
            base.OnPaint(eventArgs);
            eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var glow = new SolidBrush(Color.FromArgb(42, DotColor));
            eventArgs.Graphics.FillEllipse(glow, 0, 0, Width, Height);
            using var brush = new SolidBrush(DotColor);
            eventArgs.Graphics.FillEllipse(brush, 4, 4, Width - 8, Height - 8);
        }
    }
}
