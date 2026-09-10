# DinoController

Controller and HUD support for World of Warcraft 1.12.1.

- Open the settings menu with `/dino`.
- Copy this folder and `DinoMacroManager` into your client's `Interface\AddOns` directory.
- Run the separately supplied `Bridge\DinoControllerBridge.exe` for XInput camera, cursor and button mapping.
- The current build includes the camera/cursor reset fixes, LootFrame positioning, UI navigation, controller layout handling and automatic ground-target spell support.
- DinoMacroManager action-bar macros can be triggered from controller-managed action slots.

No SavedVariables are included. Settings are created locally in the user's own client.

Localization note: German spell-name aliases, legacy SavedVariable layout values,
and legacy German `/dino` aliases remain as internal compatibility identifiers.
They are required for German-client detection or existing user macros/settings and
are never presented as English-release UI text.
