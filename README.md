# Toggl Track for Omarchy

Compact Quickshell bar plugin with Start/Stop, project and workspace selection,
and Pomodoro focus sessions automatically tracked in Toggl. There is no recent list. The desktop theme and shell typography
are inherited through Omarchy's shared UI components.

## Installation

Requires `notify-send` for Pomodoro completion alerts, plus Omarchy's Quickshell plugin system, Python 3, `secret-tool` (libsecret),
a working desktop Secret Service/keyring, and `xdg-open`. There are no third-party
Python dependencies. This is an unofficial Toggl Track integration.

From a checkout of this repository:

```sh
mkdir -p ~/.config/omarchy/plugins/fabi.toggl
cp manifest.json Service.qml TogglWidget.qml backend.py pomodoro.py local_ipc.py ~/.config/omarchy/plugins/fabi.toggl/
```

Back up `~/.config/omarchy/shell.json`, then add `{"id": "fabi.toggl"}` to the
chosen section of `bar.layout` (for example, `center`). Preserve existing entries.
Omarchy discovers the plugin automatically. If an older compiled widget remains
visible after an update, restart the shell with `omarchy restart shell`.

## Setup

Hover over the clock area to reveal the Toggl power-ring icon, then click it.
The icon stays visible while Toggl or Pomodoro is running and hides when idle
or paused (unless the popup is open or the clock area is hovered). Choose **Get token** to open
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
- Start with an optional description and project. Stop ends the current entry.
- Typing a description suggests matching cached entries from the selected workspace.
  Choose with the mouse or arrow keys and Enter to fill the description and project;
  selection does not start a timer. Escape dismisses suggestions. No recent list is
  shown while the field is empty, and autocomplete uses no API requests.
- Elapsed time ticks locally. The server is checked every five minutes, before
  changes, and on Refresh. Refresh also reloads projects, workspaces and recents.
- Projects refresh at least daily when synchronization runs.
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

## Pomodoro

Click the circled tomato icon beside the description to reveal the Pomodoro controls. The round play button starts a
25-minute focus session and creates its Toggl entry using the selected project
and description. Starting a focus session while another entry runs switches to
a new entry. The button becomes Pause while the session runs.

- Pausing stops the focus entry; resuming creates a new segment for the remaining
  time. Reset stops the associated entry and resets the current phase.
- Completed focus sessions stop automatically. A notification announces completion.
- Short breaks last 5 minutes; every fourth focus session offers a 15-minute break.
  Breaks are not tracked. Start each next phase yourself using the play button.
- The bar shows the Pomodoro countdown while running or paused. Deadlines and
  the session count survive closing the popup, shell restarts, and sleep.
- A delayed automatic stop uses the original deadline, so sleep or lost connectivity
  does not add that extra time to the focus entry. If a stop fails, **Refresh**
  reconciles it; the Toggl entry may remain running until connectivity/quota returns.
- A timer changed on another device is never stopped by Pomodoro. A detected
  external stop or switch pauses the focus countdown.
- An uncertain start requires reviewing the current Toggl timer and resetting
  Pomodoro; it is never retried automatically. Do not start another entry blindly.
- Automatic tracking uses the same API quota as manual tracking. Focus starts
  require a connection; breaks use the local clock.

## Files and development

Installed plugin: `~/.config/omarchy/plugins/fabi.toggl/`.
Source and tests live in this repository.
Private state: `${XDG_STATE_HOME:-~/.local/state}/omarchy/toggl/`.
The state directory is mode 700 and cache files mode 600. Only explicitly selected
API response fields are cached, so the `/me` response's API token is discarded.
A file lock prevents two helper instances from changing timers simultaneously.
The widget communicates with that helper over an owner-only Unix socket, including
when a custom bar cannot expose plugin services. State updates are pushed locally;
opening the popup does not consume API requests. The connection retries after a
helper restart, without replaying timer or account actions.

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

Version 1.2.0 uses a compact timer row without the recent list and adds persisted
Pomodoro sessions with automatic Toggl tracking and completion notifications.

Version 1.2.2 keeps the idle icon hidden with clock-area hover access and removes
the three window circles from the header. Escape or an outside click closes the
popup without stopping an active timer.

Version 1.2.3 adds an outer ring to the small bar mark and replaces the Pomodoro
text button with a circled tomato icon. The idle bar icon uses the same dimmed
style as Omarchy’s timer widget; the inactive tomato uses the theme’s muted color.

Version 1.2.4 fixes an unresponsive account panel under custom replacement bars.

## License

[MIT](LICENSE) © 2026 Fabian.
