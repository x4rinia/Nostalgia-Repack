# Nostalgia English Repack

This is a portable, English-language Windows release of the Nostalgia Vanilla server. It includes the current custom world, server binaries, local account website, controller tools, and required AddOns. It does **not** include a World of Warcraft client.

## Requirements

- Windows 10 or Windows 11, 64-bit
- Your own clean World of Warcraft 1.12.1 (build 5875) client
- About 4 GB of free disk space in addition to your client
- Microsoft Visual C++ runtimes; offline installers are provided in `Tools`

Keep this entire folder together. All bundled paths are relative and no installation location is required.

## Quick start

1. Copy the folders inside `AddOns` into your own client's `Interface\AddOns` folder. Do not copy the outer `AddOns` folder itself.
2. In your client's `realmlist.wtf`, use this one line:

       set realmlist 127.0.0.1

3. Run `Launcher\NostalgiaServer.exe`.
4. Select **Start Server** and wait until MariaDB, realm server, world server, and website show as running.
5. Select **Open Website**, or browse to <http://127.0.0.1:8080/>. Create a game account there. No personal or default game account is bundled.
6. Start your own `WoW.exe` and sign in with the account you created.

The launcher does not start or contain the game client. Use **Start Controller Bridge** when you want gamepad support, or launch `Bridge\DinoControllerBridge.exe` directly. Close the launcher normally to shut down all server components cleanly.

## Controller support

`DinoController` supplies controller navigation, action mappings, camera handling, cursor reset behavior, LootFrame positioning, and the `/dino` menu. `DinoMacroManager` supplies its current macro-chain workflow. The bridge translates the configured XInput controller buttons into keyboard input; its portable settings are in `Bridge\DinoControllerBridge.json`.

For the intended setup:

- enable `DinoController` and `DinoMacroManager` at the character-selection AddOns screen;
- connect an XInput-compatible controller before starting the bridge;
- use `/dino` in game to open the English controller menu;
- close and restart the bridge after manually changing its JSON configuration.

## Included Nostalgia features

- PartyBot and BattleBot systems, including battleground auto-join
- ambient `/1 General` zone chat with faction separation and inviteable identities
- outdoor rivals and rotating Gurubashi Arena rivals
- custom small-group instance rules and transmog support
- the current Nostalgia world changes and content progression state
- ZG locked, including disabled Yojamba/Zandalar ZG functions
- AQ20 and AQ40 locked, with AQ-only rewards, Scepter/gate-opening chain, and War Effort disabled
- normal non-AQ Silithus content retained
- local account, character-backup, restore, and level-55 management website

## Folder guide

- `Launcher` — English launcher (`NostalgiaServer.exe`)
- `Server` — active realm/world binaries, configuration, and map data
- `MariaDB` — portable database engine and sanitized database files
- `Web` — local Apache/PHP account website
- `Database` — database notes and the repeatable English custom-content SQL patch
- `AddOns` — AddOns to copy into your own client
- `Bridge` — current DinoControllerBridge and portable mapping file
- `Tools` — offline Visual C++ runtime installers

## Account and backup notes

The shipped login and character databases are empty. Create the first account on the website. Character backups made through the website are stored under this repack at runtime and are not part of this release. The local database service listens only on `127.0.0.1:3307`; the technical `vmangos` credential is for local server components, not a game login.

## Playing from another computer

The default configuration is a local single-computer setup. To allow another computer on your trusted LAN, update the realm address in the `logon.realmlist` database row and point that client's `realmlist.wtf` at the host computer's LAN address. Firewall and bind-address changes are an administrator task; never expose this repack directly to the public internet without hardening it first.

## Known limitations

- Only a Vanilla 1.12.1 build 5875 client is supported.
- An English client is recommended. Blizzard's stock game text follows the client locale; only Nostalgia's custom player-facing text is localized here.
- `DinoGroundSpells.lua` intentionally contains multilingual spell aliases for client-locale compatibility. They are internal lookups, not UI copy.
- Controller support targets XInput-style controllers and still depends on the game's keyboard bindings.
- Runtime logs, temporary website sessions, and character backups are created after use; none are bundled in the clean release.
- This is a prepared self-contained local runtime. GitHub stores the large runtime files through Git LFS.

For component-specific details, see the README files inside `AddOns`, `Bridge`, `Database`, and `Tools`.
