# DinoMacroManager 1.0.0

Eigenstaendiges Addon fuer WoW 1.12.1 (Interface 11200). Es veraendert keine
Datei von DinoController.

## Bedienung

- `/dmm` blendet die Uebersicht ein oder aus.
- `/dmm reset` setzt die gespeicherte Fensterposition zurueck.
- Linksklick auf einen Slot loest genau den aktuell angezeigten Zauber aus.
- Rechtsklick auf einen Slot oeffnet den Editor.
- Im Editor Zauber aus dem normalen Spieler-Zauberbuch auf eines der vier
  Felder ziehen. Rechtsklick auf ein Feld entfernt diesen Zauberplatz.
- Jede Kette besitzt eine eigene Zeitreset-Angabe. `0` deaktiviert nur den
  Zeitreset. Die Targetwechsel-Checkbox kann unabhaengig davon gesetzt werden,
  sodass Zeit- und Targetreset einzeln oder gemeinsam funktionieren.
- `In Leiste ziehen` erstellt bei Bedarf ein charakterspezifisches WoW-Makro.
  Den Button mit gedrueckter linker Maustaste direkt auf den gewuenschten
  Platz der normalen Blizzard-Aktionsleiste ziehen und dort loslassen.
- Unter `Tastenbelegung > DinoMacroManager` kann jeder der 14 Slots separat
  belegt werden.

## Vanilla-APIs und Fortschritt

Der eingesetzte 1.12.1-Client exportiert kein `GetCursorInfo()`. Deshalb merkt
sich das Addon beim originalen `PickupSpell(index, bookType)` den Spellbook-
Index und Book-Type. Beim Drop bestaetigt `CursorHasSpell()`, dass wirklich
ein Zauber am Cursor liegt. Falls ein anderer 1.12-Client `GetCursorInfo()`
bereitstellt, wird dessen Rueckgabe weiterhin direkt unterstuetzt.
`GetSpellName()` speichert den lokalisierten Namen und Rang;
`GetSpellTexture()` speichert das Icon.
Beim Laden und vor jedem Cast wird die Referenz ueber `GetNumSpellTabs()`,
`GetSpellTabInfo()` und `GetSpellName()` erneut gegen das Spieler-Zauberbuch
aufgeloest. Dadurch bleiben verschobene Spellbook-Indizes gueltig; ein nicht
mehr vorhandener Name/Rang wird rot als ungueltig markiert.

Ausgeloest wird mit `CastSpellByName(Name.."("..Rang..")")`. Der Index wird
nicht beim Funktionsaufruf erhoeht. Erst `SPELLCAST_STOP` beziehungsweise
`SPELLCAST_CHANNEL_STOP` startet eine kurze 0,12-Sekunden-Bestaetigung. Trifft
in diesem Fenster `SPELLCAST_FAILED`, `SPELLCAST_INTERRUPTED` oder eine
`UI_ERROR_MESSAGE` ein, bleibt der Schritt stehen. Das verhindert ein Weiterspringen bei
Cooldown, fehlender Ressource oder Abbruch. Pro Bestaetigung wird exakt ein
Schritt weitergeschaltet und nach dem letzten wieder Schritt 1 gewaehlt.
Das Icon des naechsten Zaubers besitzt ein Vanilla-Cooldown-Overlay. Nach
einem Zeit- oder Targetreset wird damit sofort der verbleibende Cooldown von
Zauber 1 angezeigt; `SPELL_UPDATE_COOLDOWN` aktualisiert die Anzeige. Auch ein
DMM-Makro auf den originalen Blizzard-ActionButtons erhaelt dieses Overlay,
da Blizzard den Cooldown eines `/script`-Makros nicht selbst ableiten kann.

## Blizzard-Aktionsleiste

Der Client stellt `CreateMacro()`, `GetMacroInfo()`, `EditMacro()` und
`PickupMacro()` bereit. Das Addon erstellt nur auf Anforderung ein Makro mit
dem Inhalt `/script DinoMacroManager_ExecuteSlot(n)`. Dieses Makro belegt einen
der begrenzten charakterspezifischen WoW-Makroplaetze. Sein Icon wird beim
Kettenfortschritt auf den jeweils naechsten Zauber aktualisiert. Die fuer
diesen Client erforderliche Fuenf-Parameter-Signatur und numerischen
Macro-Icon-Indizes werden verwendet.

## Oeffentliches API

`DinoMacroManager_ExecuteSlot(slot)` fuehrt fuer `slot` von 1 bis 14 exakt
einen Kettenschritt aus. DinoMacroManager bleibt dabei eigenstaendig; eine
Installation von DinoController ist nicht erforderlich.

## Speicherung

Die TOC-Datei verwendet `SavedVariablesPerCharacter: DinoMacroManagerDB`.
Gespeichert werden Fensterposition und alle 14 Slots mit Name, individueller
Resetzeit, Targetreset-Option, aktuellem Schritt und zwei bis vier
Spell-Datensaetzen. Nach einem Relog gilt
die Sitzung als inaktiv und der aktuelle Schritt wird auf 1 gesetzt; die
Ketten selbst bleiben erhalten.

## Clienttest

Datei- und Syntaxpruefungen koennen ausserhalb des Spiels erfolgen. Nur im
echten 1.12.1-Client pruefbar sind Cursor-Payload, Server-Cast-Events,
Cooldown-/Ressourcenfehler, Tastenbelegungen sowie Persistenz nach Relog.
