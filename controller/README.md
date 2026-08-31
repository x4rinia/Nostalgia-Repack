# DinoController 1.0.0 / Bridge 1.0.0

DinoController ist eine kleine Controller-Loesung fuer den originalen
WoW-Client 1.12.1. Sie besteht bewusst nur aus einem normalen Vanilla-Addon,
einer externen XInput-Bruecke und der optionalen Launcher-Integration.

Der WoW-Client selbst wird nicht gepatcht: `WoW.exe`, MPQ-Dateien und andere
originale Clientdateien bleiben unveraendert.

## Komponenten

- `addons/DinoController`: Addon mit `## Interface: 11200` fuer Kamera,
  Fadenkreuz, HUD, gespeicherte Einstellungen, Keybindings und Navigation in
  originalen WoW-Fenstern.
- `controller/DinoControllerBridge`: kleine Windows-x64-Bruecke fuer XInput
  und echte Tastatur-/Mauseingaben.
- `launcher/NostalgiaServerLauncher`: startet die vorhandene Bridge vor WoW
  im Hintergrund. Fehlt die Bridge, startet WoW weiterhin normal.

Die Bridge sendet Eingaben nur, wenn `WoW.exe` im Vordergrund ist. Tastatur und
Maus werden nicht blockiert.

## Installation und Build

1. `addons/DinoController` nach
   `Interface/AddOns/DinoController` des Vanilla-Clients kopieren.
2. Die Bridge als einzelne, selbststaendige Windows-x64-EXE bauen:

   ```powershell
   dotnet publish .\controller\DinoControllerBridge\DinoControllerBridge.csproj -c Release -o <Repack>\tools
   ```

3. `DinoControllerBridge.json` neben `DinoControllerBridge.exe` belassen.
4. WoW ueber den Nostalgia-Launcher starten oder die Bridge vor WoW manuell
   ausfuehren.

Beim Start schreibt die Bridge die JSON-Buttonbelegung in den gefundenen
`Interface/AddOns/DinoController`-Ordner. Dabei werden das Standalone-Layout,
ein lokaler `client`-Unterordner und das bestehende `tools`-/`client`-Layout
unterstuetzt. Nach einer JSON-Aenderung muessen Bridge und WoW neu gestartet
werden.

## Grundsteuerung

| Eingabe | Funktion |
| --- | --- |
| Linker Stick | Charakter bewegen |
| Rechter Stick | Kamera drehen |
| Target-Schultertaste vor | naechstes Ziel gemaess Target-Modus |
| Target-Schultertaste zurueck | vorheriges Ziel gemaess Target-Modus |
| D-Pad | Aktionen 1 bis 4; mit L2/R2 Aktionen 5 bis 12 |
| View/Back | Weltkarte |
| L3 | Autorun |
| R3 | Mount-Aktionsslot |
| Y beziehungsweise ActionNorth | direktes Self-Target |
| X beziehungsweise ActionWest | Klassenmodus oder frei belegte Aktion |

Die beiden A/B-Positionen werden intern als logische Aktionen behandelt. Im
`/dino`-Menue koennen A/B und X/Y passend zum vom XInput-Treiber gemeldeten
Xbox- oder Nintendo-Layout getauscht werden. Die Auswahl wird in
`DinoControllerDB` gespeichert und bei jedem Login erneut auf die WoW-Bindings
angewendet.

## Weltmodus

Im Weltmodus zeigt ein optionales Fadenkreuz auf die Mitte der WoW-Clientflaeche.
Die Interaktionstaste spricht NPCs an, oeffnet Haendler und Briefkaesten, benutzt
Weltobjekte, greift Gegner per Rechtsklick an und oeffnet Loot an Leichen.

Die Bridge berechnet die wirkliche Clientmitte mit `GetClientRect` und
`ClientToScreen`; Fensterrahmen, Borderless-Modus und Windows-DPI-Skalierung
werden dadurch nicht mit der Desktopmitte verwechselt. Der technische Cursor
wird automatisch ausgeblendet und eine echte Mausbewegung blendet ihn fuer die
parallele Mausbedienung wieder ein.

## Target-Modi

Das `/dino`-Menue bietet genau zwei gespeicherte Modi:

- `DPS/Tank`: die beiden bisherigen Vanilla-Bindings fuer den naechsten und
  vorherigen Gegner.
- `Healer`: zyklisches Targeting durch `player` und alle vorhandenen
  `party1` bis `party4`; im Raid durch alle vorhandenen `raidN`, wobei der
  eigene Charakter bereits Teil der Raidliste ist.

Der Wechsel wirkt ohne Relog sofort. Das Ende der Liste springt wieder zum
Anfang und umgekehrt. Y/ActionNorth bleibt in beiden Modi festes Self-Target.

Zusaetzlich stehen folgende Befehle bereit:

- `/dino target dps`
- `/dino target healer`

## UI-Modus

Sobald ein unterstuetztes WoW-Fenster geoeffnet ist, markiert das Addon das
aktuelle Originalelement mit einem schmalen blauen Rahmen:

- D-Pad wechselt zwischen sichtbaren Buttons und Slots.
- Confirm aktiviert das markierte Element.
- Cancel beziehungsweise Escape geht zurueck oder schliesst das Fenster.
- Das Welt-Fadenkreuz wird voruebergehend ausgeblendet.

Unterstuetzt werden unter anderem Loot, Haendler und offene Taschen, Gossip,
Questfenster und Questlog, Trainer, Bank, Post, Charakterfenster sowie normale
Bestaetigungsdialoge. Es werden keine nachgebauten Fenster verwendet.

## Loot und echter Mausklick

Vanilla akzeptiert beim markierten Lootslot in diesem Client nur einen echten
Mausklick zuverlaessig. Deshalb verwendet Loot-Confirm einen eigenen Pfad:

1. Das Addon verschiebt den aktuell blau markierten originalen `LootButton`
   exakt unter die Mitte von `UIParent`.
2. Ein unsichtbares Statuspixel teilt der Bridge mit, welcher der beiden
   physischen A/B-Kanaele laut gespeicherter Einstellung Confirm ist.
3. Nur diese Confirm-Taste setzt den technischen Cursor auf die tatsaechliche
   WoW-Clientmitte.
4. Nach 40 ms Wartezeit sendet die Bridge genau einen echten Linksklick mit
   16 ms Down-/Up-Abstand.
5. Nach dem geleerten Slot markiert das Addon den naechsten vorhandenen
   Originalslot.

Damit entspricht Controller-Confirm einem manuellen Linksklick auf den
markierten Gegenstand. Der sichtbare Mauszeiger wird dafuer nicht benoetigt.

## Kamera

Das Addon setzt beim Login nur in Vanilla 1.12.1 vorhandene Kamera-CVars,
deaktiviert unpassende Glaettung und zoomt bis zur maximal sinnvollen
Vanilla-Distanz heraus. Die Einstellungen koennen mit `/dino camera` erneut
angewendet werden.

## Controller-HUD

Das kleine verschiebbare HUD zeigt vier D-Pad-Aktionen und die wichtigsten
Facebutton-Aktionen. L2 und R2 schalten die D-Pad-Leiste auf weitere Seiten, so
dass insgesamt zwoelf normale ActionSlots erreichbar sind. Klassenhaltung,
Druidenform beziehungsweise Schurken-Stealth und ein Mountslot sind separat
vorbereitet. Spellketten oder automatische Rotationen sind nicht enthalten.

## Konfiguration

`/dino` oeffnet das Ingame-Menue. Wichtige Befehle:

- `/dino target dps|healer`
- `/dino layout xbox|nintendo`
- `/dino reticle on|off`
- `/dino autoquest on|off`
- `/dino autoloot on|off`
- `/dino camera`
- `/dino bind`
- `/dino status`

Die externe `DinoControllerBridge.json` konfiguriert unter anderem Deadzones,
Kamerageschwindigkeit, Cursor-Automatik, D-Pad-Kanaele und Trigger-Modifier.
Fuer den robusten Mausklick gelten standardmaessig:

```json
"CursorSettleDelayMilliseconds": 40,
"InteractionPressMilliseconds": 16
```

## Grenzen

- WoW 1.12.1 liest XInput nicht nativ; die Bridge muss deshalb parallel laufen.
- Vanilla-Lua kann den Windows-Cursor nicht frei positionieren.
- Freie Texteingabe, komplexes Drag-and-drop, Auktionshaus, Handel,
  Berufe/Crafting und Grupp-Loot-Rollfenster sind noch nicht vollstaendig fuer
  Controller-Navigation umgesetzt.
- Es gibt keine Spellketten, Rotationen oder Kampfautomatisierung.
- Die Bridge und kompilierte EXE werden nicht als Quellcodeersatz benoetigt;
  Buildprodukte bleiben durch `.gitignore` aus dem Repository ausgeschlossen.
