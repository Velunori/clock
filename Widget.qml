pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "../lib/kit" as Velunori
import "CalendarModel.js" as Calendar

Item {
    id: root
    property var bar: null
    property string moduleName: "velunori.clock"
    property var settings: ({})
    property bool opened: false
    readonly property real openPanelIndicatorWidth: label.implicitWidth
    implicitWidth: label.implicitWidth + 24
    implicitHeight: bar ? bar.barSize : 40
    Velunori.Theme { id: theme; bar: root.bar }
    function setting(key, fallback) { return settings[key] === undefined ? fallback : settings[key]; }
    function open() {
        if (!bar) return;
        if (panel.item) panel.item.resetToday();
        opened = true;
        bar.requestPopout(root);
    }
    function close() { opened = false; if (bar) bar.releasePopout(root); }
    function closeForPopoutSwitch() { close(); }
    function toggle() { if (opened) close(); else open(); }
    SystemClock { id: clock; precision: String(root.setting("timeFormat", "HH:mm")).indexOf("s") >= 0 ? SystemClock.Seconds : SystemClock.Minutes }

    Backend { id: data; active: root.opened }

    WidgetButton {
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        tooltipText: Qt.formatDate(clock.date, "dddd, d MMMM yyyy")
        onPressed: function(button) { if (button === Qt.LeftButton) root.toggle(); }
        Row {
            id: label
            anchors.centerIn: parent
            spacing: 10
            Text {
                text: Qt.formatTime(clock.date, String(root.setting("timeFormat", "HH:mm")))
                color: theme.text; font.family: theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                visible: root.setting("showDate", true)
                width: 1; height: 12; color: theme.border; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: root.setting("showDate", true)
                text: Qt.formatDate(clock.date, String(root.setting("dateFormat", "ddd, d MMM")))
                color: theme.muted; font.family: theme.fontFamily; font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Loader {
        id: panel
        active: root.bar !== null
        sourceComponent: calendarPanel
    }
    Component {
        id: calendarPanel
        Velunori.Panel {
            id: popup
            anchorItem: root
            bar: root.bar
            owner: root
            open: root.opened
            contentWidth: fittedContentWidth(420)
            contentHeight: fittedContentHeight(calendar.implicitHeight + padding * 2 + 2, screenH > 0 ? Math.floor(screenH * .8) : 640)
            focusTarget: keys
            function resetToday() { calendar.resetToday(); }
            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) { if (!calendar.back()) root.close(); event.accepted = true; }
                    else if (!calendar.editing && !calendar.sourcesOpen) {
                        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) { calendar.step(event.key === Qt.Key_Left ? -1 : 1); event.accepted = true; }
                        else if (event.key === Qt.Key_Home) { calendar.resetToday(); event.accepted = true; }
                    }
                }
                CalendarContent {
                    id: calendar
                    anchors.fill: parent
                    backend: data
                    bar: root.bar
                    today: clock.date
                    onWindowStartChanged: data.start = windowStart
                    onWindowEndChanged: data.end = windowEnd
                    Component.onCompleted: { data.start = windowStart; data.end = windowEnd; }
                    weekStart: Calendar.normalizedWeekStart(root.setting("weekStartDay", Qt.locale().firstDayOfWeek))
                }
            }
        }
    }
    IpcHandler {
        target: "velunori.clock"
        function status(): string {
            var widgets = root.bar ? root.bar.moduleWidgets(root.moduleName) : [root];
            return JSON.stringify({apiVersion: theme.apiVersion, accent: theme.accent.toString(),
                instances: widgets.map(function(widget) {
                    return {opened: widget.opened, width: widget.width, height: widget.height};
                })});
        }
        function toggle(): void { root.toggle(); }
        function show(): void { root.open(); }
        function hide(): void { root.close(); }
    }
}
