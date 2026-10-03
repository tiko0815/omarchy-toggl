# Toggl Track for Omarchy

Native Quickshell bar plugin with Start, Stop, Switch timer, recent-entry Resume,
project search and workspace selection. The desktop theme and shell typography
are inherited through Omarchy's shared UI components.

## Installation

Requires Omarchy's Quickshell plugin system, Python 3, `secret-tool` (libsecret),
a working desktop Secret Service/keyring, and `xdg-open`. There are no third-party
Python dependencies. This is an unofficial Toggl Track integration.

From a checkout of this repository:

```sh
mkdir -p ~/.config/omarchy/plugins/fabi.toggl
cp manifest.json Service.qml TogglWidget.qml backend.py ~/.config/omarchy/plugins/fabi.toggl/
```

Back up `~/.config/omarchy/shell.json`, then add `{"id": "fabi.toggl"}` to the
chosen section of `bar.layout` (for example, `center`). Preserve existing entries.
Omarchy discovers the plugin automatically. If an older compiled widget remains
visible after an update, restart the shell with `omarchy restart shell`.

## Setup

Click the Toggl power-ring icon in the bar. Choose **Get token** to open
Toggl's profile, copy your API token into the masked field, then click **Connect**.
Choose your workspace using the named **Workspace** selector above the timer.
Setup explains the rolling API request limit and that this app requires an API
token. Password sign-in is not implemented here; this is an app limitation,
not a claim that Toggl’s API cannot authenticate with a password.
The token is stored through Secret Service (`secret-tool`). Unlock your desktop
keyring if requested. Tokens never enter shell.json, command arguments or logs.
**Disconnect account** removes the stored credential; it does not stop a running
Toggl timer.

## Behavior

- The primary button starts a timer when idle and stops it when running.
- Start with an optional description and project. Switch timer stops the previous
  entry before creating the next. Resume always creates a new entry.
- Elapsed time ticks locally. The server is checked every five minutes, before
  changes, and on Refresh. Refresh also reloads projects, workspaces and recents.
- Projects refresh at least daily when synchronization runs. Five recent entries
  in the selected workspace are shown; successful local stops update that list.
- A dot beside elapsed time means the display is stale. Refresh before changing
  timers after a connection error. Offline changes are not queued.
- If another device changed the current timer, the action is canceled and the
  new state is displayed. Review it, refresh, and retry.
- Failed or uncertain writes are never retried automatically. Refresh reconciles
  state first. A failed switch may leave the old entry stopped without starting
  the next; the panel shows the last confirmed state.
- Requests are serialized, spaced at least one second apart, and conservatively
  capped at 30 total requests per rolling hour. The budget survives shell reloads.
  Server quota responses pause requests for Retry-After (or an hour by default).
  Other clients using the account can consume quota independently.

## Files and development

Installed plugin: `~/.config/omarchy/plugins/fabi.toggl/`.
Source and tests live in this repository.
Private state: `${XDG_STATE_HOME:-~/.local/state}/omarchy/toggl/`.
The state directory is mode 700 and cache files mode 600. Only explicitly selected
API response fields are cached, so the `/me` response's API token is discarded.
A file lock prevents two helper instances from changing timers simultaneously.

Run tests without an account:

```sh
python3 -B -m unittest discover -s . -v
```

Parse QML with `/usr/lib/qt6/bin/qmlformat FILE >/dev/null`. Copy changed source
files to the installed plugin; Omarchy hot-reloads it. Do not edit packaged shell
files. Inspect status with `omarchy-shell fabi.toggl status`; open the panel with
`omarchy-shell shell summon fabi.toggl '{}'`.

To uninstall, remove the `fabi.toggl` bar entry and its plugin directory. Use
**Disconnect account** first if you also want to remove the keyring credential.
Removing the plugin does not stop a running Toggl timer.

Validation performed: mocked backend tests and installed-panel visual inspection.
Live account start/stop verification requires local account setup. Once connected,
create a clearly labelled short test entry, stop it, and confirm it in Toggl.

API reference: https://engineering.toggl.com/docs/track/api/time_entries/

Version 1.0.1 fixes active project filtering and zero-height selection lists.
Existing project caches are refreshed automatically on upgrade. Generic workspace
names are qualified with their organization name; identical labels include the
workspace ID so every workspace stays distinguishable.

Version 1.1.0 adds a theme-aware power-ring bar icon, a larger elapsed-time
display, a prominent Start/Stop button, and project labels on recent entries.
