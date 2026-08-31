# DinoControllerBridge 1.0.0

Windows-XInput-Bridge fuer DinoController und den originalen
**WoW-Vanilla-1.12.1-Client**. Die Bridge gehoert funktional zum
DinoController und ist kein eigenstaendiges WoW-Addon.

## Endnutzer-Installation

Das DinoController-Release direkt in den WoW-Hauptordner entpacken:

```text
WoW.exe
DinoControllerBridge.exe
DinoControllerBridge.json
Interface/AddOns/DinoController/DinoController.toc
```

`DinoControllerBridge.exe` starten. Sie wartet auf einen XInput-Controller und
auf einen Prozess namens `WoW.exe`. Beim ersten Start wird eine fehlende JSON-
Konfiguration automatisch mit Standardwerten erzeugt.

Die Bridge schreibt die konfigurierten Tasten als `BridgeMappings.lua` in den
gefundenen DinoController-Addonordner. Unterstuetzt werden diese Layouts:

1. `Interface/AddOns/DinoController` neben der EXE (Standalone-Release)
2. `client/Interface/AddOns/DinoController` neben der EXE
3. `../client/Interface/AddOns/DinoController` fuer bestehende Tool-Layouts

## Konfiguration

Die mitgelieferte `DinoControllerBridge.json` ist eine sichere
Beispielkonfiguration ohne persoenliche Pfade. Wichtige Werte:

- `ControllerIndex`: XInput-Controller 0 bis 3
- `LeftStickPressDeadzone` / `LeftStickReleaseDeadzone`
- `RightStickDeadzone`
- `CameraPixelsPerTick`
- `InvertCameraY`
- `CursorAutoHide` und `CursorHideDelayMilliseconds`
- `ButtonMappings`

## Selbsttest

```powershell
.\DinoControllerBridge.exe --self-test
```

Der Selbsttest prueft Konfiguration, Tastenparser, Controllerabfrage und
Mausmonitor. Das Ergebnis steht in `DinoControllerBridge.log`.

## Build

Voraussetzungen:

- Windows x64
- .NET 8 SDK

Build als selbstenthaltende Einzeldatei:

```powershell
dotnet publish .\DinoControllerBridge.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true
```

Die EXE und JSON-Datei liegen anschliessend unter
`bin/Release/net8.0-windows/win-x64/publish/`.

Die Bridge verwendet nur die .NET-Basisklassenbibliothek und Windows-APIs;
es bestehen keine externen NuGet-Paketabhaengigkeiten.
