# Outrun
Outrun based digital dashboard 

Check out a video here:
[
https://www.youtube.com/shorts/oORS55_4-DE](https://www.youtube.com/shorts/oORS55_4-DE)


## Layout

- `Outrun.qml` - entry file: live data, config load/save, joystick handling, settings menu
- `OutrunDisplay.qml` - the dial itself
- `PseudoRoad.qml`, `pseudoroad.frag` - the scrolling road
- `SettingsMenu.qml`, `SettingBox.qml`, `MonoText.qml`, `Theme.qml`, `GridBackground.qml` - settings menu (shared with AgeSolo)
- `SettingsPreview.qml` - standalone menu preview, not loaded by the dash
- `Outrun.qml.png` - preview shown in the dash picker

The wideband input (`o2data`) arrives as lambda. The AFR menu can hide the readout, show it as lambda or AFR (lambda x 14.7), and set High / Low limits. The limits are always in AFR; outside them the readout turns red and flashes, and 0 turns a limit off.

The Oil temp and Oil press menus also have a Show row to hide those readouts.

Settings are saved as JSON in `/opt/IC7/screen_configs/Outrun_config.json`. An existing `Outrun.txt` is imported once on first run.

# Installation notes:

1) Install with GARW Genie:  https://github.com/dustinsterk/GARWGenie