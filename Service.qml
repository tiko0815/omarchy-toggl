import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var settings: ({})
    property var state: ({connected: false, online: false, busy: true, message: "Loading Toggl…"})
    readonly property var pomodoro: state.pomodoro || {phase: "focus", status: "idle", completed: 0, remaining: 1500, deadline: 0}
    readonly property string pomodoroText: {
        var seconds = Math.max(0, Math.ceil(pomodoro.status === "running" ? pomodoro.deadline - now / 1000 : pomodoro.remaining));
        return String(Math.floor(seconds / 60)).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
    }
    readonly property string pomodoroLabel: pomodoro.phase === "focus" ? "Focus" : pomodoro.phase === "short" ? "Short break" : "Long break"
    readonly property string pomodoroNext: pomodoro.phase === "focus" ? (pomodoro.completed % 4 === 0 ? "Long break" : "Short break") : "Focus"
    property bool pending: false
    property double now: Date.now()
    readonly property bool busy: pending || !!state.busy
    readonly property bool canChange: state.connected && state.online && !state.uncertain && !busy
    readonly property string elapsed: {
        if (!state.current) return "";
        var seconds = Math.max(0, Math.floor((now - Date.parse(state.current.start)) / 1000));
        if (!isFinite(seconds)) return "--:--";
        return String(Math.floor(seconds / 3600)).padStart(2, "0") + ":" + String(Math.floor(seconds / 60) % 60).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
    }
    function act(action, values) {
        if (busy || !helper.running) return;
        var command = Object.assign({action: action, expected_id: state.current ? state.current.id : null}, values || {});
        pending = true;
        helper.write(JSON.stringify(command) + "\n");
    }
    Process {
        id: helper
        command: ["python3", "-B", "-u", Qt.resolvedUrl("backend.py").toString().replace("file://", "")]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                try { root.now = Date.now(); root.state = JSON.parse(line); root.pending = false; } catch (e) {}
            }
        }
        onExited: {
            root.pending = false;
            root.state = Object.assign({}, root.state, {busy: false, online: false, message: "Toggl helper stopped. Restarting…"});
            restart.restart();
        }
    }
    Timer { id: restart; interval: 5000; onTriggered: helper.running = true }
    Timer { interval: 1000; running: !!root.state.current || root.pomodoro.status === "running"; repeat: true; onTriggered: root.now = Date.now() }
    Timer { interval: 300000; running: true; repeat: true; onTriggered: if (root.state.connected) root.act("poll") }
    IpcHandler {
        target: "fabi.toggl"
        function status(): string { return JSON.stringify({connected: !!root.state.connected, online: !!root.state.online, busy: root.busy, running: !!root.state.current, message: root.state.message}); }
    }
}
