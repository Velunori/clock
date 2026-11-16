pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kit" as V
import "CalendarModel.js" as Calendar

ColumnLayout {
    id: root
    required property var backend
    property var bar: null
    property var event: null
    property string day: ""
    property bool confirmDelete: false
    readonly property var calendars: backend.snapshot.calendars.filter(function(row) { return !row.readonly; })
    readonly property bool editing: event !== null
    signal done()
    spacing: 12
    V.Theme { id: theme; bar: root.bar }
    function load() {
        confirmDelete = false;
        title.text = event ? event.title : "";
        allDay.checked = event ? event.allDay : false;
        start.text = event ? (event.allDay ? event.start : Calendar.localTime(event.start).slice(0, 10)) : day;
        end.text = event ? (event.allDay ? Calendar.addDays(event.end, -1) : Calendar.localTime(event.end).slice(0, 10)) : day;
        startTime.text = event && !event.allDay ? Calendar.localTime(event.start).slice(11) : "09:00";
        endTime.text = event && !event.allDay ? Calendar.localTime(event.end).slice(11) : "10:00";
        location.text = event ? event.location : ""; notes.text = event ? event.description : "";
        var index = calendars.findIndex(function(row) { return row.id === (root.event ? root.event.calendar_id : "local"); });
        calendar.currentIndex = Math.max(0, index);
        backend.errorText = "";
        Qt.callLater(function() { title.forceActiveFocus(); });
    }
    function timestamp(day, time, original) {
        var local = day + "T" + time;
        // Retain the original offset for unchanged times in a repeated DST hour.
        return original && local === Calendar.localTime(original) ? original : local;
    }
    function save() {
        if (!calendars.length || backend.busy) return;
        backend.perform({action: "save", id: event ? event.id : null, expectedEtag: event ? event.etag : "", calendarId: calendars[calendar.currentIndex].id,
            event: {title: title.text, start: allDay.checked ? start.text : timestamp(start.text, startTime.text, event && !event.allDay ? event.start : ""), end: allDay.checked ? Calendar.addDays(end.text, 1) : timestamp(end.text, endTime.text, event && !event.allDay ? event.end : ""),
                allDay: allDay.checked, location: location.text, description: notes.text}});
    }
    Connections {
        target: root.backend
        function onCompleted(request, response) { if (response.ok && (request.action === "save" || request.action === "delete")) root.done(); }
    }
    RowLayout {
        Layout.fillWidth: true
        V.Button { bar: root.bar; text: "‹ Back"; implicitHeight: 30; implicitWidth: 76; onClicked: root.done() }
        Item { Layout.fillWidth: true }
        Text { text: root.editing ? "Edit event" : "New event"; color: theme.muted; font.pixelSize: 12 }
    }
    Field { bar: root.bar;
        id: title; objectName: "eventTitle"; Layout.fillWidth: true; placeholderText: "Event title"; color: theme.text; font.pixelSize: 18; selectByMouse: true
        background: Rectangle { radius: 10; color: theme.surface; border.color: title.activeFocus ? theme.accent : theme.border }
    }
    Select { bar: root.bar; id: calendar; Layout.fillWidth: true; model: root.calendars; textRole: "name"; enabled: !root.editing; Accessible.name: "Calendar" }
    RowLayout {
        Text { text: "All day"; color: theme.text; font.pixelSize: 13; Layout.fillWidth: true }
        V.Toggle {
            id: allDay; accent: theme.accent

        }
    }
    Text { visible: root.event && root.event.provider !== "local"; text: "For recurring events, changes affect only this occurrence."; color: theme.muted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    Text { text: allDay.checked ? "End date included · YYYY-MM-DD" : "Local time · " + root.backend.snapshot.timezone; color: theme.muted; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    GridLayout {
        columns: 2; Layout.fillWidth: true
        Text { text: "From"; color: theme.muted; font.pixelSize: 12 }
        RowLayout {
            Layout.fillWidth: true
            Field { bar: root.bar; id: start; objectName: "eventStart"; Layout.fillWidth: true; placeholderText: "YYYY-MM-DD" }
            Field { bar: root.bar; id: startTime; visible: !allDay.checked; Layout.preferredWidth: 82; placeholderText: "HH:mm" }
        }
        Text { text: "To"; color: theme.muted; font.pixelSize: 12 }
        RowLayout {
            Layout.fillWidth: true
            Field { bar: root.bar; id: end; objectName: "eventEnd"; Layout.fillWidth: true; placeholderText: "YYYY-MM-DD" }
            Field { bar: root.bar; id: endTime; visible: !allDay.checked; Layout.preferredWidth: 82; placeholderText: "HH:mm" }
        }
    }
    Field { bar: root.bar; id: location; Layout.fillWidth: true; placeholderText: "Location (optional)"; color: theme.text; selectByMouse: true }
    TextArea { id: notes; Layout.fillWidth: true; Layout.preferredHeight: 80; placeholderText: "Notes (optional)"; color: theme.text; wrapMode: TextEdit.Wrap; selectByMouse: true; background: Rectangle { radius: 10; color: theme.surface; border.color: theme.border } }
    Text { visible: root.confirmDelete; text: "Delete this event?"; color: theme.text; font.pixelSize: 13 }
    RowLayout {
        Layout.fillWidth: true
        V.Button {
            visible: root.editing; bar: root.bar; text: root.confirmDelete ? "Confirm delete" : "Delete"; implicitWidth: 110
            enabled: !root.backend.busy
            onClicked: { if (root.confirmDelete) root.backend.perform({action: "delete", id: root.event.id, expectedEtag: root.event.etag}); else root.confirmDelete = true; }
        }
        Item { Layout.fillWidth: true }
        V.Button { objectName: "saveEvent"; bar: root.bar; text: "Save event"; primary: true; enabled: title.text.trim() !== "" && root.calendars.length > 0 && !root.backend.busy; onClicked: root.save() }
    }
}
