pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kit" as Velunori
import "CalendarModel.js" as Calendar

Item {
    id: root
    property var bar: null
    property var backend: null
    property bool editing: false
    property bool sourcesOpen: false
    property string sourcePage: "overview"
    onSourcePageChanged: { scroll.contentY = 0; if (backend) backend.errorText = ""; }
    onEditingChanged: { scroll.contentY = 0; if (backend) backend.errorText = ""; }
    onSourcesOpenChanged: { sourcePage = "overview"; scroll.contentY = 0; if (backend) backend.errorText = ""; }
    property string filterCalendar: ""
    readonly property var events: backend ? backend.snapshot.events : []
    readonly property string selectedDay: Calendar.isoDay(selectedDate)
    readonly property var agenda: Calendar.eventsForDay(events, selectedDay, filterCalendar)
    readonly property string windowStart: cells.length ? Calendar.isoDay(Calendar.cellDate(cells[0])) : ""
    readonly property string windowEnd: cells.length ? Calendar.isoDay(Calendar.cellDate(cells[41])) : ""
    function editEvent(event) { editor.event = event; editor.day = selectedDay; editing = true; editor.load(); }
    Connections {
        target: root.backend
        function onCompleted(request, response) {
            if (!response.ok) return;
            if (request.action === "addCalendar") { calendarName.clear(); root.sourcePage = "overview"; }
            if (request.action === "connectGoogle" || request.action === "connectIcloud") root.sourcePage = "overview";
            if (request.action === "disconnect" || request.action === "visibility") { root.filterCalendar = ""; filter.currentIndex = 0; }
        }
    }
    function back() { if (editing) editing = false; else if (sourcesOpen && sourcePage !== "overview") sourcePage = "overview"; else if (sourcesOpen) sourcesOpen = false; else return false; return true; }
    property date today: new Date()
    property int weekStart: Qt.locale().firstDayOfWeek % 7
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    property date selectedDate: today
    readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
    readonly property var cells: Calendar.monthCells(viewYear, viewMonth, weekStart, today, selectedDate)
    Keys.onEscapePressed: function(event) { event.accepted = root.back(); }
    implicitWidth: 336
    implicitHeight: sourcesOpen ? Math.min(600, Math.max(300, sources.implicitHeight + 120)) : 600
    Velunori.Theme { id: theme; bar: root.bar }

    function resetToday() {
        editing = false; sourcesOpen = false;
        viewYear = today.getFullYear();
        viewMonth = today.getMonth();
        selectedDate = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12);
    }
    function step(delta) {
        var next = Calendar.shiftMonth(viewYear, viewMonth, delta);
        viewYear = next.year;
        viewMonth = next.month;
    }
    function selectCell(cell) {
        selectedDate = new Date(cell.year, cell.month, cell.day, 12);
        viewYear = cell.year;
        viewMonth = cell.month;
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Text { text: "CALENDAR"; color: theme.accent; font.family: theme.fontFamily; font.pixelSize: 11; font.letterSpacing: 2 }
            Item { Layout.fillWidth: true }
            Velunori.Button { visible: !root.editing; bar: root.bar; text: root.sourcesOpen ? (root.sourcePage === "overview" ? "Done" : "Back") : "Calendars"; implicitHeight: 30; implicitWidth: 92; onClicked: { if (root.sourcesOpen) root.back(); else root.sourcesOpen = true; } }
        }
        Flickable {
            id: scroll
            objectName: "calendarScroll"
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
            clip: true; contentWidth: width; contentHeight: root.editing ? editor.implicitHeight : root.sourcesOpen ? sources.implicitHeight + 12 : content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
            WheelHandler {
                target: null; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) { scroll.contentY = Math.max(0, Math.min(Math.max(0, scroll.contentHeight - scroll.height), scroll.contentY - (event.pixelDelta.y || event.angleDelta.y * .8))); event.accepted = true; }
            }
            ScrollBar.vertical: ScrollBar { policy: scroll.contentHeight > scroll.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
            EventEditor { id: editor; visible: root.editing; width: parent.width - 10; backend: root.backend; bar: root.bar; onDone: { root.editing = false; scroll.contentY = 0; } }
            ColumnLayout {
                id: sources; objectName: "calendarSources"; visible: root.sourcesOpen && !root.editing; width: parent.width - 10; spacing: 14
                ColumnLayout {
                    visible: root.sourcePage === "overview"; Layout.fillWidth: true; spacing: 10
                    Text { text: "Your calendars"; color: theme.text; font.pixelSize: 20; font.weight: Font.DemiBold }
                    Text { text: "Choose which calendars appear in your agenda."; color: theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Repeater {
                        model: root.backend ? root.backend.snapshot.calendars : []
                        RowLayout {
                            id: sourceRow
                            Layout.minimumWidth: 0; Layout.minimumHeight: 42
                            required property var modelData
                            Layout.fillWidth: true
                            Rectangle { width: 8; height: 8; radius: 4; color: sourceRow.modelData.color }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 3
                                Text { objectName: "sourceName"; text: sourceRow.modelData.name; textFormat: Text.PlainText; color: theme.text; font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: sourceRow.modelData.provider === "local" ? "On this computer" : sourceRow.modelData.provider === "google" ? "Google Calendar" : "iCloud Calendar"; textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 11 }
                            }
                            Velunori.Toggle { checked: !!sourceRow.modelData.enabled; accent: theme.accent; enabled: !root.backend.busy; onClicked: root.backend.perform({action: "visibility", id: sourceRow.modelData.id, enabled: checked}) }
                        }
                    }
                    Repeater {
                        model: root.backend ? root.backend.snapshot.calendars.filter(function(row, index, rows) { return row.account && rows.findIndex(function(other) { return other.account === row.account; }) === index; }) : []
                        RowLayout {
                            id: accountRow
                            required property var modelData
                            property bool confirming: false
                            Layout.fillWidth: true
                            Text { text: accountRow.modelData.provider === "google" ? "Google account" : "iCloud account"; color: theme.muted; font.pixelSize: 12; Layout.fillWidth: true }
                            Velunori.Button { bar: root.bar; text: accountRow.confirming ? "Confirm disconnect" : "Disconnect"; implicitHeight: 30; implicitWidth: 140; enabled: !root.backend.busy; onClicked: { if (accountRow.confirming) root.backend.perform({action: "disconnect", account: accountRow.modelData.account}); else accountRow.confirming = true; } }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: root.backend && root.backend.snapshot.lastSync ? "Synced " + Qt.formatDateTime(new Date(root.backend.snapshot.lastSync), "d MMM, HH:mm") : "Not synced yet"; color: theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
                        Velunori.Button { bar: root.bar; text: "Sync"; implicitWidth: 70; implicitHeight: 30; enabled: root.backend && !root.backend.busy; onClicked: root.backend.perform({action: "sync"}) }
                    }
                    Text { visible: root.backend && !!root.backend.snapshot.syncError; text: root.backend ? root.backend.snapshot.syncError || "" : ""; color: "#eaa7bb"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
                ColumnLayout {
                    visible: root.sourcePage === "new"; Layout.fillWidth: true; spacing: 12
                    Text { text: "New local calendar"; color: theme.text; font.pixelSize: 14 }
                    Field { bar: root.bar; id: calendarName; Layout.fillWidth: true; placeholderText: "Calendar name"; color: theme.text }
                    RowLayout {
                        id: colors
                        property string selected: "#c4aff1"
                        Repeater {
                            model: ["#c4aff1", "#a0ddbf", "#e8bf8a", "#91baf0", "#eaa7bb"]
                            AbstractButton {
                                id: colorButton
                                required property string modelData
                                implicitWidth: 28; implicitHeight: 28
                                Accessible.name: "Calendar color " + modelData
                                onClicked: colors.selected = modelData
                                background: Rectangle { radius: 14; color: colorButton.modelData; border.width: colors.selected === colorButton.modelData ? 3 : 0; border.color: theme.text }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Velunori.Button { bar: root.bar; text: "Create"; implicitWidth: 80; enabled: calendarName.text.trim() !== "" && root.backend && !root.backend.busy; onClicked: root.backend.perform({action: "addCalendar", name: calendarName.text, color: colors.selected}) }
                    }
                }
                ColumnLayout {
                    visible: root.sourcePage === "connect"; Layout.fillWidth: true; spacing: 12
                    Text { text: "Connect an account"; color: theme.text; font.pixelSize: 16; font.weight: Font.Medium }
                    RowLayout {
                        Layout.fillWidth: true
                        Velunori.Button { bar: root.bar; text: "Google"; primary: connection.provider === "google"; onClicked: connection.provider = "google" }
                        Velunori.Button { bar: root.bar; text: "iCloud"; primary: connection.provider === "icloud"; onClicked: connection.provider = "icloud" }
                    }
                    ColumnLayout {
                        id: connection
                        objectName: "accountConnection"
                        property string provider: "google"
                        Layout.fillWidth: true; spacing: 10
                        Text { text: connection.provider === "google" ? "Connect Google Calendar" : "Set up iCloud Calendar"; color: theme.text; font.pixelSize: 14; font.weight: Font.Medium; Layout.fillWidth: true }
                        Text { text: connection.provider === "google" ? "Sign in with Google in your browser and approve calendar access. Your calendars will sync in both directions." : "You need an Apple Account with two-factor authentication and an app-specific password."; textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        Text {
                            objectName: "googleSignInUnavailable"
                            visible: connection.provider === "google" && root.backend && !root.backend.snapshot.googleSignInReady
                            text: "Google sign-in is not available in this build. Velunori's Google application registration still needs to be configured."
                            textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                        ColumnLayout {
                            visible: connection.provider === "icloud"
                            Layout.fillWidth: true; spacing: 10
                            Text { text: "1. Open your Apple Account → Sign-In and Security → App-Specific Passwords. Choose Generate an app-specific password and name it Velunori Calendar.\n\n2. Enter your Apple Account email and the generated password below, then press Connect iCloud."; textFormat: Text.PlainText; color: theme.text; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            Velunori.Button { objectName: "icloudSetup"; bar: root.bar; text: "Open Apple Account ↗"; Layout.fillWidth: true; onClicked: Qt.openUrlExternally("https://account.apple.com/") }
                        }
                        Field { id: appleId; bar: root.bar; visible: connection.provider === "icloud"; Layout.fillWidth: true; placeholderText: "Apple Account email" }
                        Field { id: applePassword; bar: root.bar; visible: connection.provider === "icloud"; Layout.fillWidth: true; placeholderText: "App-specific password"; echoMode: TextInput.Password }
                        Text { text: "Account credentials are stored privately on this computer. Disconnect removes the local account and cache; remote events stay in your account."; color: theme.muted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                    }
                }

            }
            ColumnLayout {
                id: content; width: parent.width - 10; visible: !root.editing && !root.sourcesOpen; spacing: 12
                Text { Layout.fillWidth: true; text: Qt.formatDate(root.today, "dddd, d MMMM"); color: theme.text; font.family: theme.fontFamily; font.pixelSize: 22; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: Qt.formatDate(root.viewDate, "MMMM yyyy"); color: theme.text; font.pixelSize: 16; font.weight: Font.Medium }
                    Velunori.Button { bar: root.bar; text: "Today"; implicitWidth: 62; implicitHeight: 30; onClicked: root.resetToday() }
                    Velunori.Button { bar: root.bar; text: "‹"; implicitWidth: 30; implicitHeight: 30; Accessible.name: "Previous month"; onClicked: root.step(-1) }
                    Velunori.Button { bar: root.bar; text: "›"; implicitWidth: 30; implicitHeight: 30; Accessible.name: "Next month"; onClicked: root.step(1) }
                }
                Grid {
                    id: calendarGrid; Layout.fillWidth: true; columns: 7; spacing: 4
                    readonly property real cellWidth: (width - spacing * 6) / 7
                    Repeater {
                        model: 7
                        Text { required property int index; width: calendarGrid.cellWidth; height: 22; text: Qt.locale().dayName((root.weekStart + index) % 7 || 7, Locale.ShortFormat); color: theme.muted; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    Repeater {
                        model: root.cells
                        AbstractButton {
                            id: dayButton
                            required property var modelData
                            readonly property string day: Calendar.isoDay(Calendar.cellDate(modelData))
                            width: calendarGrid.cellWidth; height: 36; hoverEnabled: true
                            Accessible.name: Qt.formatDate(Calendar.cellDate(modelData), "dddd, d MMMM yyyy") + ", " + Calendar.eventsForDay(root.events, day, root.filterCalendar).length + " events"
                            onClicked: root.selectCell(modelData)
                            background: Rectangle { radius: 9; color: dayButton.modelData.selected ? theme.accent : dayButton.hovered ? theme.surface : "transparent"; border.color: dayButton.modelData.isToday || dayButton.activeFocus ? theme.accent : "transparent" }
                            contentItem: Item {
                                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 2; text: dayButton.modelData.day; color: dayButton.modelData.selected ? theme.background : theme.text; opacity: dayButton.modelData.inMonth ? 1 : .45; font.pixelSize: 13 }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3; spacing: 3
                                    Repeater { model: Calendar.dayColors(root.events, dayButton.day, root.filterCalendar); Rectangle { required property string modelData; width: 4; height: 4; radius: 2; color: dayButton.modelData.selected ? theme.background : modelData } }
                                }
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: Qt.formatDate(root.selectedDate, "dddd, d MMM"); color: theme.text; font.pixelSize: 14; font.weight: Font.Medium }
                    Select { bar: root.bar;
                        id: filter; Layout.preferredWidth: 132; textRole: "name"
                        model: [{id: "", name: "All calendars"}].concat(root.backend ? root.backend.snapshot.calendars.filter(function(row) { return !!row.enabled; }) : [])
                        onModelChanged: {
                            var index = model.findIndex(function(row) { return row.id === root.filterCalendar; });
                            currentIndex = Math.max(0, index);
                            if (index < 0) root.filterCalendar = "";
                        }
                        onActivated: root.filterCalendar = model[currentIndex].id
                        Accessible.name: "Filter agenda by calendar"
                    }
                }
                Text { visible: root.agenda.length === 0; text: "No events planned"; color: theme.muted; font.pixelSize: 13; Layout.topMargin: 8; Layout.bottomMargin: 12 }
                Repeater {
                    model: root.agenda
                    ColumnLayout {
                        id: eventRow
                        required property var modelData
                        objectName: "agendaEvent"
                        Layout.fillWidth: true; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            Rectangle { width: 3; Layout.fillHeight: true; radius: 1; color: eventRow.modelData.color }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Text { text: eventRow.modelData.allDay ? "All day" : eventRow.modelData.startDay !== eventRow.modelData.endDay ? Qt.formatDateTime(new Date(eventRow.modelData.start), "d MMM HH:mm") + " – " + Qt.formatDateTime(new Date(eventRow.modelData.end), "d MMM HH:mm") : Qt.formatTime(new Date(eventRow.modelData.start), "HH:mm") + " – " + Qt.formatTime(new Date(eventRow.modelData.end), "HH:mm"); color: theme.muted; font.pixelSize: 11 }
                                Text { text: eventRow.modelData.title; color: theme.text; font.pixelSize: 14; font.weight: Font.Medium; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                Text { text: eventRow.modelData.calendarName + (eventRow.modelData.location ? " · " + eventRow.modelData.location : ""); color: theme.muted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            Velunori.Button { bar: root.bar; text: "Edit"; implicitWidth: 52; implicitHeight: 30; visible: !eventRow.modelData.readonly; onClicked: root.editEvent(eventRow.modelData) }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
                    }
                }
            }
        }
        Text { visible: root.backend && root.backend.errorText !== "" && !(root.sourcesOpen && root.sourcePage === "overview" && root.backend.errorText === root.backend.snapshot.syncError); text: root.backend ? root.backend.errorText : ""; color: "#eaa7bb"; wrapMode: Text.WordWrap; font.pixelSize: 12; Layout.fillWidth: true }
        RowLayout {
            visible: root.sourcesOpen && !root.editing && root.sourcePage === "overview"
            Layout.fillWidth: true; spacing: 10
            Velunori.Button { objectName: "newCalendar"; bar: root.bar; text: "New calendar"; Layout.fillWidth: true; implicitHeight: 38; onClicked: root.sourcePage = "new" }
            Velunori.Button { objectName: "addAccount"; bar: root.bar; text: "Add account"; primary: true; Layout.fillWidth: true; implicitHeight: 38; onClicked: root.sourcePage = "connect" }
        }
        ColumnLayout {
            visible: root.sourcesOpen && !root.editing && root.sourcePage === "connect"
            Layout.fillWidth: true; spacing: 12
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
            Velunori.Button {
                objectName: "connectAccount"
                Layout.fillWidth: true; Layout.minimumHeight: 38; implicitHeight: 38
                bar: root.bar; text: root.backend && root.backend.busy ? "Connecting / syncing…" : connection.provider === "icloud" ? "Connect iCloud" : "Connect Google"; primary: true
                enabled: root.backend && !root.backend.busy && (connection.provider === "google" ? !!root.backend.snapshot.googleSignInReady : appleId.text.trim() !== "" && applePassword.text !== "")
                onClicked: {
                    if (connection.provider === "google") root.backend.perform({action: "connectGoogle"});
                    else { root.backend.perform({action: "connectIcloud", username: appleId.text, password: applePassword.text}); applePassword.clear(); }
                }
            }
        }
        RowLayout {
            visible: !root.editing && !root.sourcesOpen; Layout.fillWidth: true
            Text { text: root.backend ? root.backend.snapshot.timezone : "Local time"; color: theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
            Velunori.Button { bar: root.bar; text: "Sync"; implicitWidth: 58; implicitHeight: 34; enabled: root.backend && !root.backend.busy; onClicked: root.backend.perform({action: "sync"}) }
            Velunori.Button { objectName: "newEvent"; bar: root.bar; text: "+ New event"; primary: true; implicitHeight: 34; enabled: root.backend && !root.backend.busy; onClicked: root.editEvent(null) }
        }
    }
}
