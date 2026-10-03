import QtQuick
import QtQuick.Layouts
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
    FontMetrics { id: metrics; font.family: Style.font.family; font.pixelSize: Style.font.body }
    function fit(text) { return metrics.elidedText(text, Qt.ElideRight, popup.contentWidth - Style.space(45)); }
    function act(action, values) { if (service) service.act(action, values); }
    function projectLabel(id) { var p = (state.projects || []).find(p => p.id === id); return p ? p.name : (id ? "Unavailable project" : "No project"); }
    WidgetButton {
        id: button
        bar: root.bar
        text: "󱎫" + (root.state.current && root.service ? " " + root.service.elapsed : "") + (root.state.connected && !root.state.online ? " ·" : "")
        dimmed: !root.state.current
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
            spacing: Style.space(8)
            focus: true
            Keys.onEscapePressed: root.close()
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Toggl Track"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.fillWidth: true }
                Button { text: root.account ? "Timer" : "Account"; focusable: true; onClicked: root.account = !root.account }
            }
            Text {
                Layout.fillWidth: true
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
                text: root.fit("Workspace · " + root.workspaceName + " ▾")
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
                Text {
                    visible: !!root.state.current
                    Layout.fillWidth: true
                    text: root.service ? root.service.elapsed + "  " + ((root.state.current || {}).description || "Untitled") : ""
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                TextField { id: description; Layout.fillWidth: true; placeholderText: "What are you working on?"; onAccepted: start.clicked() }
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
                RowLayout {
                    Layout.fillWidth: true
                    Button { id: start; Layout.fillWidth: true; text: root.state.current ? "Switch timer" : "Start"; selected: true; focusable: true; enabled: root.service && root.service.canChange; onClicked: { if (enabled) root.act("start", {description: description.text, project_id: root.projectId}); } }
                    Button { visible: !!root.state.current; text: "Stop"; focusable: true; enabled: root.service && root.service.canChange; onClicked: root.act("stop") }
                }
                Text { visible: root.recent.length > 0; text: "Recent"; color: Color.foreground; opacity: 0.7; font.family: Style.font.family; font.pixelSize: Style.font.body }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count * Style.space(35), Style.space(165))
                    clip: true
                    model: root.recent
                    spacing: Style.space(3)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Button {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: Style.space(32)
                        text: root.fit((root.state.current ? "Switch · " : "Resume · ") + (modelData.description || "Untitled"))
                        tooltipText: (modelData.description || "Untitled") + "\n" + root.projectLabel(modelData.project_id)
                        leftAlign: true
                        focusable: true
                        enabled: root.service && root.service.canChange
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
