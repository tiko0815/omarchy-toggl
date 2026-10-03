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
    property bool pickingProject: false
    property bool pickingWorkspace: false
    readonly property string workspaceName: ((state.workspaces || []).find(w => w.id === state.workspace) || {}).name || "Choose workspace"
    property var projectId: null
    property string projectName: "No project"
    readonly property var projects: (state.projects || []).filter(p => p.workspace_id === state.workspace && p.name.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
    readonly property var recent: (state.recent || []).filter(e => e.workspace_id === state.workspace).slice(0, 5)
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    onOpenedChanged: if (opened) { account = !state.connected; }
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
            ctx.strokeStyle = ink; ctx.lineWidth = width * 0.13; ctx.lineCap = "round";
            ctx.beginPath(); ctx.arc(width / 2, height * 0.55, width * 0.35, -Math.PI / 4, Math.PI * 1.25); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(width / 2, height * 0.08); ctx.lineTo(width / 2, height * 0.48); ctx.stroke();
        }
    }
    function accentInk() {
        function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
        return 0.2126 * linear(Color.accent.r) + 0.7152 * linear(Color.accent.g) + 0.0722 * linear(Color.accent.b) > 0.179 ? "#000000" : "#ffffff";
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
        dimmed: false
        Row {
            id: barContents
            anchors.centerIn: parent
            spacing: Style.space(6)
            TrackMark { anchors.verticalCenter: parent.verticalCenter; ink: root.state.current ? Color.accent : button.foreground }
            Text {
                visible: !!root.state.current
                anchors.verticalCenter: parent.verticalCenter
                text: root.service ? root.service.elapsed : ""
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
        contentWidth: popup.fittedContentWidth(Style.space(380))
        contentHeight: popup.fittedContentHeight(content.implicitHeight)
        ColumnLayout {
            id: content
            width: parent.width
            spacing: Style.space(12)
            focus: true
            Keys.onEscapePressed: root.close()
            RowLayout {
                Layout.fillWidth: true
                TrackMark { ink: Color.accent }
                Text { text: "Toggl Track"; font.bold: true; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.fillWidth: true }
                Button { text: root.account ? "Timer" : "Account"; focusable: true; onClicked: root.account = !root.account }
            }
            Text {
                Layout.fillWidth: true
                visible: !root.state.connected || !root.state.online
                text: root.service && root.service.busy ? "Connecting…" : (root.state.message || "Loading…")
                color: Color.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            Button {
                visible: !!root.state.connected
                Layout.fillWidth: true
                text: root.fit(root.workspaceName + " ▾")
                leftAlign: true
                bordered: true
                tooltipText: root.workspaceName
                focusable: true
                onClicked: root.pickingWorkspace = !root.pickingWorkspace
            }
                ListView {
                    visible: root.state.connected && root.pickingWorkspace
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count * Style.space(35), Style.space(110))
                    clip: true
                    model: root.state.workspaces || []
                    spacing: Style.space(3)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Button {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: Style.space(32)
                        text: root.fit(modelData.name)
                        tooltipText: modelData.name
                        selected: modelData.id === root.state.workspace
                        focusable: true
                        enabled: root.service && !root.service.busy
                        onActiveFocusChanged: if (activeFocus) ListView.view.positionViewAtIndex(index, ListView.Contain)
                        onClicked: { root.act("workspace", {id: modelData.id}); root.pickingWorkspace = false; root.pickingProject = false; }
                    }
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
                spacing: Style.space(8)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(116)
                    radius: Style.space(6)
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.045)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Style.space(14)
                        spacing: Style.space(5)
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Style.space(6)
                            Rectangle { width: Style.space(5); height: width; radius: width / 2; color: root.state.current ? Color.accent : Color.muted }
                            Text { text: root.state.current ? "Tracking time" : "Ready when you are"; color: Color.foreground; opacity: 0.7; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.state.current && root.service ? root.service.elapsed : "00:00:00"
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.space(34)
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: root.state.current ? (root.state.current.description || "Untitled") + " · " + root.projectLabel(root.state.current.project_id) : "Start a fresh entry or pick up a recent one"
                            color: Color.foreground
                            opacity: 0.65
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }
                }
                TextField { id: description; Layout.fillWidth: true; placeholderText: "What are you working on?"; onAccepted: if (!root.state.current) start.clicked() }
                Button { text: root.fit(root.projectName + " ▾"); tooltipText: root.projectName; Layout.fillWidth: true; focusable: true; onClicked: root.pickingProject = !root.pickingProject }
                ColumnLayout {
                    visible: root.pickingProject
                    Layout.fillWidth: true
                    TextField { id: search; Layout.fillWidth: true; placeholderText: "Search projects" }
                    Button { text: "No project"; focusable: true; onClicked: { root.projectId = null; root.projectName = "No project"; root.pickingProject = false; } }
                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(count * Style.space(35), Style.space(130))
                        clip: true
                        model: root.projects
                        spacing: Style.space(3)
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
                Controls.AbstractButton {
                    id: start
                    Layout.fillWidth: true
                    implicitHeight: Style.space(44)
                    text: root.service && root.service.busy ? "Please wait…" : (root.state.current ? "Stop timer" : "Start timer")
                    enabled: root.service && root.service.canChange
                    activeFocusOnTab: true
                    Accessible.name: text
                    background: Rectangle {
                        radius: Style.space(5)
                        color: Color.accent
                        opacity: !start.enabled ? 0.4 : (start.down ? 0.75 : (start.hovered ? 0.9 : 1))
                        border.width: start.activeFocus ? Style.space(2) : 0
                        border.color: Color.foreground
                    }
                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: Style.space(9)
                            Text { text: root.state.current ? "■" : "▶"; color: root.accentInk(); font.family: Style.font.family; font.pixelSize: Style.font.body }
                            Text { text: start.text; color: root.accentInk(); font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
                        }
                    }
                    onClicked: if (enabled) root.act(root.state.current ? "stop" : "start", {description: description.text, project_id: root.projectId})
                }
                Button {
                    visible: !!root.state.current
                    Layout.fillWidth: true
                    text: "Switch to new entry"
                    focusable: true
                    enabled: root.service && root.service.canChange
                    onClicked: root.act("start", {description: description.text, project_id: root.projectId})
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Color.foreground; opacity: 0.12 }
                Text { visible: root.recent.length > 0; text: "Recent"; color: Color.foreground; opacity: 0.7; font.family: Style.font.family; font.pixelSize: Style.font.body }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count * Style.space(51), Style.space(200))
                    clip: true
                    model: root.recent
                    spacing: Style.space(3)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Controls.AbstractButton {
                        id: recentButton
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: Style.space(48)
                        activeFocusOnTab: true
                        enabled: root.service && root.service.canChange
                        Accessible.name: (root.state.current ? "Switch to " : "Resume ") + (modelData.description || "Untitled")
                        background: Rectangle {
                            radius: Style.space(4)
                            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, recentButton.hovered || recentButton.activeFocus ? 0.08 : 0)
                            border.width: recentButton.activeFocus ? 1 : 0
                            border.color: Color.accent
                        }
                        contentItem: RowLayout {
                            spacing: Style.space(12)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Style.space(8)
                                spacing: Style.space(2)
                                Text { Layout.fillWidth: true; text: recentButton.modelData.description || "Untitled"; textFormat: Text.PlainText; elide: Text.ElideRight; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                                Text { Layout.fillWidth: true; text: root.projectLabel(recentButton.modelData.project_id); textFormat: Text.PlainText; elide: Text.ElideRight; color: Color.foreground; opacity: 0.55; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
                            }
                            Text { Layout.rightMargin: Style.space(10); text: "▶"; color: Color.accent; opacity: recentButton.enabled ? 1 : 0.4; font.family: Style.font.family; font.pixelSize: Style.font.body }
                        }
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.text: Accessible.name + " · " + root.projectLabel(modelData.project_id)
                        Controls.ToolTip.delay: 500
                        onActiveFocusChanged: if (activeFocus) ListView.view.positionViewAtIndex(index, ListView.Contain)
                        onClicked: root.act("resume", {id: modelData.id})
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Button { text: "Refresh"; focusable: true; enabled: root.state.connected && root.service && !root.service.busy; onClicked: root.act("refresh") }
                Item { Layout.fillWidth: true }
                Button { text: "Open Toggl ↗"; focusable: true; onClicked: Quickshell.execDetached(["xdg-open", "https://track.toggl.com/timer"]) }
            }
        }
    }
}
