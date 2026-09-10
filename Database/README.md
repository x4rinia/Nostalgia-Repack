# Database notes

The portable MariaDB data directory is already initialized and ready to run through the launcher.

- `vmangos` contains the full current Nostalgia world and custom content.
- `logon`, `characters`, and `logs` retain their required schemas and migration state.
- No game accounts, player characters, gameplay logs, private dumps, or private backups are included.
- The realm is named `Nostalgia` and defaults to `127.0.0.1`.
- The database listener is restricted to `127.0.0.1:3307`.

`english_content_patch.sql` is a repeatable localization patch for the custom ambient-chat table. It has already been applied to the bundled database and is included for maintenance or clean re-imports.

The local technical database user is `vmangos`. It is used by the supplied server and website configuration and is not a playable account. Create game accounts through the website.
