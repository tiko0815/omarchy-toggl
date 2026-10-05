import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "fabi.toggl"
    manageIpc: false
    readonly property var service: bar?.shell?.serviceFor("fabi.toggl") || null
    readonly property var state: service ? service.state : ({})
    property bool account: false
    property bool pomodoroMode: false
    readonly property var pomo: service ? service.pomodoro : ({phase: "focus", status: "idle", completed: 0})
    readonly property bool pomoLocked: ["running", "starting", "stop_pending"].indexOf(pomo.status) >= 0
    readonly property string actionLabel: {
        if (!pomodoroMode) return root.state.current ? "Stop timer" : "Start timer";
        if (pomo.status === "running") return "Pause " + service.pomodoroLabel.toLowerCase();
        if (pomo.status === "finished") return "Start " + service.pomodoroNext.toLowerCase();
        if (pomo.status === "paused") return "Resume " + service.pomodoroLabel.toLowerCase();
        return "Start " + (service ? service.pomodoroLabel.toLowerCase() : "focus");
    }
    function primaryAction() {
        if (!start.enabled) return;
        var action = pomodoroMode ? (pomo.status === "running" ? "pomo_pause" : "pomo_start") : (state.current ? "stop" : "start");
        act(action, {description: description.text, project_id: projectId});
    }
    property bool pickingProject: false
    property bool pickingWorkspace: false
    readonly property string workspaceName: ((state.workspaces || []).find(w => w.id === state.workspace) || {}).name || "Choose workspace"
    property var projectId: null
    property string projectName: "No project"
    readonly property var projects: (state.projects || []).filter(p => p.workspace_id === state.workspace && p.name.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
    readonly property bool timerActive: !!state.current || ["running", "starting", "stop_pending"].indexOf(pomo.status) >= 0
    readonly property bool revealed: opened || timerActive || button.tooltipHovered || (bar && bar.centerSectionRevealHeld && !bar.centerHoverRevealSuppressed)
    implicitWidth: revealed ? button.implicitWidth : 0
    implicitHeight: revealed ? button.implicitHeight : 0
    visible: revealed
    onOpenedChanged: if (opened) { account = !state.connected; if (pomo.status !== "idle") pomodoroMode = true; }
    Connections {
        target: root.service
        function onStateChanged() {
            if (root.projectId !== null && !(root.state.projects || []).some(p => p.id === root.projectId && p.workspace_id === root.state.workspace)) {
                root.projectId = null; root.projectName = "No project";
            }
        }
    }
    component TrackMark: Canvas {
        property color ink: Color.foreground
        implicitWidth: Style.space(18)
        implicitHeight: Style.space(18)
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            ctx.strokeStyle = ink; ctx.lineCap = "round";
            ctx.lineWidth = width * 0.075;
            ctx.beginPath(); ctx.arc(width / 2, height / 2, width * 0.445, 0, Math.PI * 2); ctx.stroke();
            ctx.lineWidth = width * 0.095;
            ctx.beginPath(); ctx.arc(width / 2, height * 0.54, width * 0.235, -Math.PI / 4, Math.PI * 1.25); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(width / 2, height * 0.22); ctx.lineTo(width / 2, height * 0.49); ctx.stroke();
        }
    }
    component TomatoMark: Canvas {
        property color ink: Color.muted
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset(); ctx.scale(width, height);
            ctx.strokeStyle = ink; ctx.fillStyle = ink; ctx.lineWidth = 0.065; ctx.lineCap = "round"; ctx.lineJoin = "round";
            ctx.beginPath(); ctx.moveTo(0.5, 0.37);
            ctx.bezierCurveTo(0.14, 0.17, 0.03, 0.55, 0.22, 0.8);
            ctx.bezierCurveTo(0.36, 0.97, 0.67, 0.97, 0.8, 0.78);
            ctx.bezierCurveTo(0.99, 0.5, 0.83, 0.2, 0.5, 0.37); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(0.5, 0.36); ctx.lineTo(0.31, 0.24); ctx.lineTo(0.48, 0.27);
            ctx.lineTo(0.56, 0.12); ctx.lineTo(0.59, 0.29); ctx.lineTo(0.76, 0.29); ctx.lineTo(0.62, 0.41); ctx.closePath(); ctx.fill();
        }
    }
    function accentInk() { return inkFor(Color.accent); }
    function inkFor(color) {
        function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b) > 0.179 ? "#000000" : "#ffffff";
    }
    FontMetrics { id: metrics; font.family: Style.font.family; font.pixelSize: Style.font.body }
    function fit(text) { return metrics.elidedText(text, Qt.ElideRight, popup.contentWidth - Style.space(45)); }
    function act(action, values) { if (service) service.act(action, values); }
    function projectLabel(id) { var p = (state.projects || []).find(p => p.id === id); return p ? p.name : (id ? "Unavailable project" : "No project"); }
    WidgetButton {
        id: button
        bar: root.bar
        text: "Toggl"
        labelVisible: false
        fixedWidth: barContents.implicitWidth + Style.space(12)
        dimmed: !root.timerActive
        Row {
            id: barContents
            anchors.centerIn: parent
            spacing: Style.space(6)
            TrackMark { width: Style.space(13); height: width; anchors.verticalCenter: parent.verticalCenter; ink: root.state.current || root.pomo.status === "running" ? Color.accent : button.foreground }
            Text {
                visible: !!root.state.current || root.pomo.status === "running" || root.pomo.status === "paused"
                anchors.verticalCenter: parent.verticalCenter
                text: root.service ? (["running", "paused"].indexOf(root.pomo.status) >= 0 ? root.service.pomodoroText : root.service.elapsed) : ""
                color: button.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Rectangle {
                visible: root.state.connected && !root.state.online
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(4); height: width; radius: width / 2
                color: Color.urgent
            }
        }
        horizontalMargin: 5
        verticalPadding: 5
        maintainIndicatorReveal: true
        tooltipText: root.state.current ? "Toggl · " + (root.state.current.description || "Untitled") + "\n" + root.projectLabel(root.state.current.project_id) + (!root.state.online ? "\nLast known timer · refresh needed" : "") : "Toggl Track"
        onPressed: function(mouseButton) { if (mouseButton === Qt.LeftButton) root.toggle(); }
    }
    KeyboardPanel {
        id: popup
        bar: root.bar
        owner: root
        anchorItem: button
        open: root.opened
        centerOnBar: true
        focusTarget: content
        contentWidth: popup.fittedContentWidth(Style.space(420))
        contentHeight: popup.fittedContentHeight(content.implicitHeight)
        Controls.ScrollView {
            id: scroll
            width: parent.width
            height: popup.contentHeight
            contentWidth: availableWidth
            contentHeight: content.implicitHeight
            clip: true
            ColumnLayout {
                id: content
                width: scroll.availableWidth
                spacing: Style.space(8)
                focus: true
                Keys.onEscapePressed: root.close()
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)
                    Button {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.state.connected ? metrics.elidedText(root.workspaceName + " ▾", Qt.ElideRight, Math.max(0, popup.contentWidth - Style.space(105))) : "Toggl Track"
                        tooltipText: root.workspaceName
                        focusable: true
                        enabled: !!root.state.connected && !root.pomoLocked
                        onClicked: root.pickingWorkspace = !root.pickingWorkspace
                    }
                    Button { text: root.account ? "Back" : "Account"; focusable: true; onClicked: root.account = !root.account }
                }
                ListView {
                    visible: root.pickingWorkspace && !!root.state.connected
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count * Style.space(32), Style.space(96))
                    model: root.state.workspaces || []
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Button {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: Style.space(32)
                        text: root.fit(modelData.name)
                        selected: modelData.id === root.state.workspace
                        focusable: true
                        enabled: root.service && !root.service.busy && !root.pomoLocked
                        onActiveFocusChanged: if (activeFocus) ListView.view.positionViewAtIndex(index, ListView.Contain)
                        onClicked: { root.act("workspace", {id: modelData.id}); root.pickingWorkspace = false; }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: !root.state.connected || !root.state.online || ["review", "stop_pending", "starting"].indexOf(root.pomo.status) >= 0
                    text: root.pomo.status === "review" ? "Check the Toggl timer before resetting Pomodoro; its start could not be confirmed." : root.pomo.status === "stop_pending" ? "Toggl may still be running. Refresh to confirm the stop." : (root.state.message || "Loading…")
                    color: Color.foreground
                    opacity: 0.8
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
            ColumnLayout {
                visible: root.account
                Layout.fillWidth: true
                spacing: Style.space(8)
                Text {
                    Layout.fillWidth: true
                    text: "This app uses Toggl’s public API. Connect with an API token from your Toggl profile. Email and password sign-in isn’t supported in this app."
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    text: "API usage is limited. This app allows up to 30 requests per rolling hour. Refreshing and timer changes use requests; one action can use several. When a limit is reached, syncing and timer changes pause until quota is available."
                    color: Color.foreground
                    opacity: 0.8
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
                TextField { id: token; Layout.fillWidth: true; placeholderText: "Toggl API token"; password: true; onAccepted: connect.clicked() }
                RowLayout {
                    Button { id: connect; text: "Connect"; focusable: true; enabled: token.text.length > 0 && root.service && !root.service.busy; onClicked: { if (!enabled) return; root.act("connect", {token: token.text}); token.text = ""; } }
                    Button { text: "Get token"; focusable: true; onClicked: Quickshell.execDetached(["xdg-open", "https://track.toggl.com/profile"]) }
                    Button { text: "Retry keyring"; focusable: true; enabled: root.service && !root.service.busy; onClicked: root.act("init") }
                }
                Button { visible: root.state.connected; text: "Disconnect account"; focusable: true; enabled: root.service && !root.service.busy; onClicked: root.act("disconnect") }
            }
                ColumnLayout {
                    visible: !root.account
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(10)
                        Controls.AbstractButton {
                            id: pomoToggle
                            implicitWidth: Style.space(28)
                            implicitHeight: implicitWidth
                            text: "Pomodoro"
                            activeFocusOnTab: true
                            Accessible.name: "Toggle Pomodoro controls"
                            background: Rectangle {
                                radius: width / 2
                                color: "transparent"
                                border.width: 1
                                border.color: root.pomodoroMode || pomoToggle.activeFocus ? Color.accent : Color.muted
                            }
                            contentItem: Item {
                                TomatoMark {
                                    anchors.centerIn: parent
                                    width: Style.space(17)
                                    height: width
                                    ink: root.pomo.status === "running" ? Color.accent : (pomoToggle.hovered ? Color.foreground : Color.muted)
                                }
                            }
                            Controls.ToolTip.visible: hovered
                            Controls.ToolTip.text: "Pomodoro"
                            Controls.ToolTip.delay: 400
                            onClicked: root.pomodoroMode = !root.pomodoroMode
                        }
                        TextField {
                            id: description
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            placeholderText: "What are you working on?"
                            enabled: !root.pomoLocked
                            onAccepted: if (!root.state.current && root.pomo.status !== "running") root.primaryAction()
                        }
                        Text {
                            text: root.pomodoroMode && root.service ? root.service.pomodoroText : (root.service && root.state.current ? root.service.elapsed : "0:00:00")
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }
                        Controls.AbstractButton {
                            id: start
                            implicitWidth: Style.space(34)
                            implicitHeight: implicitWidth
                            text: root.actionLabel
                            activeFocusOnTab: true
                            Accessible.name: text
                            enabled: root.service && !root.service.busy && root.state.connected &&
                                (root.pomodoroMode ? (["starting", "stop_pending", "review"].indexOf(root.pomo.status) < 0 && (root.pomo.phase !== "focus" || root.service.canChange || root.pomo.status === "running")) : root.service.canChange && !root.pomoLocked)
                            background: Rectangle {
                                radius: width / 2
                                color: Color.accent
                                opacity: !start.enabled ? 0.4 : (start.down ? 0.7 : start.hovered ? 0.85 : 1)
                                border.width: start.activeFocus ? Style.space(2) : 0
                                border.color: Color.foreground
                            }
                            contentItem: Text {
                                text: root.pomodoroMode ? (root.pomo.status === "running" ? "Ⅱ" : "▶") : (root.state.current ? "■" : "▶")
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: root.accentInk()
                                font.family: Style.font.family
                                font.pixelSize: Style.space(17)
                            }
                            Controls.ToolTip.visible: hovered
                            Controls.ToolTip.text: text
                            Controls.ToolTip.delay: 400
                            onClicked: root.primaryAction()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Button { Layout.fillWidth: true; leftAlign: true; text: root.fit(root.projectName + " ▾"); tooltipText: root.projectName; focusable: true; enabled: !root.pomoLocked; onClicked: root.pickingProject = !root.pickingProject }
                    }
                    ColumnLayout {
                        visible: root.pickingProject
                        Layout.fillWidth: true
                        TextField { id: search; Layout.fillWidth: true; placeholderText: "Search projects" }
                        Button { text: "No project"; focusable: true; onClicked: { root.projectId = null; root.projectName = "No project"; root.pickingProject = false; } }
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(count * Style.space(32), Style.space(128))
                            clip: true
                            model: root.projects
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Button {
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: Style.space(32)
                                text: root.fit(modelData.name)
                                tooltipText: modelData.name
                                focusable: true
                                onActiveFocusChanged: if (activeFocus) ListView.view.positionViewAtIndex(index, ListView.Contain)
                                onClicked: { root.projectId = modelData.id; root.projectName = modelData.name; root.pickingProject = false; }
                            }
                        }
                    }
                    Text {
                        visible: !!root.state.current && !root.pomodoroMode
                        Layout.fillWidth: true
                        text: "Tracking · " + ((root.state.current || {}).description || "Untitled") + " · " + root.projectLabel((root.state.current || {}).project_id)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Color.foreground
                        opacity: 0.65
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }
                    ColumnLayout {
                        visible: root.pomodoroMode
                        Layout.fillWidth: true
                        spacing: Style.space(6)
                        Rectangle { Layout.fillWidth: true; height: 1; color: Color.foreground; opacity: 0.12 }
                        RowLayout {
                            Layout.fillWidth: true
                            Repeater {
                                model: [{phase: "focus", label: "Focus 25"}, {phase: "short", label: "Break 5"}, {phase: "long", label: "Long 15"}]
                                Button {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    selected: root.pomo.phase === modelData.phase
                                    focusable: true
                                    enabled: root.service && !root.service.busy && ["idle", "finished"].indexOf(root.pomo.status) >= 0
                                    onClicked: root.act("pomo_select", {phase: modelData.phase})
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: root.pomo.status === "finished" ? "Done · next: " + root.service.pomodoroNext : root.pomo.status === "paused" ? "Paused" : "Focus " + (root.pomo.completed % 4 + 1) + "/4 · " + (root.pomo.phase === "focus" ? "tracked in Toggl" : "untracked break")
                                color: Color.foreground
                                opacity: 0.7
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                            }
                            Button { text: "Reset"; focusable: true; enabled: root.service && !root.service.busy; onClicked: root.act("pomo_reset") }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Color.foreground; opacity: 0.12 }
                RowLayout {
                    Layout.fillWidth: true
                    Button { text: "Refresh"; focusable: true; enabled: root.state.connected && root.service && !root.service.busy; onClicked: root.act("refresh") }
                    Item { Layout.fillWidth: true }
                    Button { text: "Open Toggl ↗"; focusable: true; onClicked: Quickshell.execDetached(["xdg-open", "https://track.toggl.com/timer"]) }
                }
            }
        }
    }
}
