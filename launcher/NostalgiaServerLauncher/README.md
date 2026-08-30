# Nostalgia Server Launcher

Der Launcher ist eine kleine WinForms-Anwendung für die portable Struktur unter
`Nostalgia`. Er verwaltet MariaDB, `realmd.exe`, `mangosd.exe` und den lokalen Apache-Webserver.

## Bauen

Im Repository-Stamm:

```powershell
dotnet publish .\launcher\NostalgiaServerLauncher\NostalgiaServerLauncher.csproj -c Release -o .\Nostalgia
```

Das Projekt ist als selbstenthaltende `win-x64`-Einzeldatei konfiguriert. Das
Ergebnis ist `Nostalgia\NostalgiaServer.exe`; auf dem Zielrechner muss keine
.NET-Runtime installiert sein.

## Relative Laufzeitstruktur

```text
Nostalgia\
  NostalgiaServer.exe
  MariaDB\bin\mariadbd.exe
  MariaDB\bin\mariadb-admin.exe
  MariaDB\my.ini
  Server\realmd.exe
  Server\realmd.conf
  Server\mangosd.exe
  Server\mangosd.conf
  Web\Apache\bin\httpd.exe
  Web\Apache\conf\httpd.conf
```

Es gibt absichtlich keine zusätzliche Konfigurationsdatei: Die mitgelieferte
portable Nostalgia-Struktur ist der Standard und alle Pfade werden relativ zum
Speicherort der Launcher-EXE aufgelöst.

## Shutdown

1. World erhält über seine umgeleitete Standardeingabe `server shutdown 0`.
2. Realm erhält `CTRL+BREAK`; dieser Signalweg wird vom vorhandenen realmd-Code
   als sauberer Shutdown behandelt.
3. Web erhält `httpd -k shutdown`; übrig gebliebene Apache-Kindprozesse werden kontrolliert geprüft.
4. MariaDB erhält `mariadb-admin ... shutdown`.
5. Nur nach den dokumentierten Timeouts wird der jeweilige Prozess als letzter
   Fallback beendet.

Beim Schließen des Fensters läuft dieselbe Stop-Sequenz vollständig ab, bevor
die Anwendung geschlossen wird.

Die bisherigen Batch-Dateien werden für den normalen Betrieb nicht mehr benötigt.
`web.bat` kann den Webserver weiterhin separat starten, öffnet aber keinen Browser mehr.
Die Webseite wird im Launcher bewusst nur über `Webseite öffnen` geöffnet.
