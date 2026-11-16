//@ pragma OmarchyLoadPatch
import Quickshell
import QtQuick
import "velunori.clock"
import "lib/kit" as Velunori

ShellRoot {
    id: tests
    property string failure: ""
    property bool rpcDone: false
    property bool uiDone: false
    property int phase: 0
    property string eventId: ""
    function finish() {
        if (!rpcDone || !uiDone) return;
        console.log(failure ? "CALENDAR_TEST_FAILED: " + failure : "CALENDAR_TEST_PASSED");
        var path = Quickshell.env("VELUNORI_PREVIEW_PATH");
        if (path) {
            var state = Quickshell.env("VELUNORI_PREVIEW_STATE");
            if (state === "editor") calendar.editEvent(fake.snapshot.events[0]);
            else if (state === "sources" || state === "sources-icloud") {
                calendar.sourcesOpen = true;
                findItem(calendar, "accountConnection").provider = state === "sources-icloud" ? "icloud" : "google";
            }
            Qt.callLater(function() { surface.grabToImage(function(result) { result.saveToFile(path); Qt.quit(); }); });
        }
        else Qt.quit();
    }
    Backend {
        id: transport
        active: true; start: "2026-11-01"; end: "2026-11-30"
        onCompleted: function(request, response) {
            tests.check(response.ok, "backend mutation " + request.action);
            if (request.action === "save") { tests.eventId = response.data.id; tests.phase = 1; }
            else if (request.action === "delete") tests.phase = 2;
        }
        onSnapshotChanged: {
            if (tests.phase === 1 && snapshot.events.length) {
                tests.check(snapshot.events[0].title === "Transport test", "QML transport reads persisted event");
                tests.phase = 3; perform({action: "delete", id: tests.eventId});
            } else if (tests.phase === 2 && snapshot.events.length === 0) { tests.rpcDone = true; tests.finish(); }
        }
    }
    Timer { interval: 100; running: true; onTriggered: transport.perform({action: "save", calendarId: "local", event: {title: "Transport test", start: "2026-11-12", end: "2026-11-13", allDay: true}}) }
    QtObject {
        id: fake
        property bool busy: false
        property string errorText: ""
        property var lastRequest: ({})
        property var snapshot: ({timezone: "Europe/Berlin", calendars: [{id: "local", name: "Personal", color: "#c4aff1", provider: "local", readonly: false, enabled: true}], events: [
            {id: "sample", calendar_id: "local", title: "Design review", start: "2026-11-12T10:00:00+01:00", end: "2026-11-12T11:00:00+01:00", startDay: "2026-11-12", endDay: "2026-11-12", color: "#c4aff1", calendarName: "Personal", provider: "local", location: "Studio", description: "Review the new calendar", allDay: false, readonly: false}
        ]})
        signal completed(var request, var response)
        function perform(request) { lastRequest = request; }
    }
    Timer { interval: 6000; running: true; onTriggered: { console.log("RPC_TIMEOUT", tests.phase, tests.uiDone, transport.busy, transport.errorText, JSON.stringify(transport.snapshot)); Qt.quit(); } }
    function findItem(parent, name) {
        if (parent.objectName === name) return parent;
        for (var child of (parent.children || [])) { var found = findItem(child, name); if (found) return found; }
        return null;
    }
    function check(value, message) { if (!value) failure += message + "; "; }
    QtObject {
        id: host
        property var velunori: ({apiVersion: 1, accentName: "mint", motion: false})
    }
    Velunori.Theme { id: theme; bar: host }
    FloatingWindow {
        visible: true
        implicitWidth: 420
        implicitHeight: Quickshell.env("VELUNORI_PREVIEW_HEIGHT") ? Number(Quickshell.env("VELUNORI_PREVIEW_HEIGHT")) : calendar.implicitHeight + 40
        color: "#202026"
        Rectangle {
            id: surface
            anchors.fill: parent
            color: "#202026"
            CalendarContent {
                id: calendar
                x: 20; y: 20; width: parent.width - 40; height: parent.height - 40
                backend: fake
                today: new Date(2026, 10, 12, 12)
                bar: host
            }
        }
    }
    Timer {
        id: footerTest
        interval: 80
        onTriggered: {
            var button = findItem(calendar, "connectAccount");
            var point = button.mapToItem(calendar, 0, 0);
            check(button.visible && point.y >= 0 && point.y + button.height <= calendar.height + 1, "account connect action stays fully visible");
            check(button.height >= 38, "account connect action is not compressed");
            var scroll = findItem(calendar, "calendarScroll");
            scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
            check(Math.abs(button.mapToItem(calendar, 0, 0).y - point.y) < 1, "scrolling settings leaves account action pinned");
            calendar.sourcesOpen = false;
            uiDone = true; finish();
        }
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            check(theme.accent.toString() === "#a0ddbf" && !theme.motion, "initial inherited theme");
            host.velunori = {apiVersion: 1, style: "orbit", accentName: "lavender", motion: true};
            check(theme.accent.toString() === "#c4aff1" && theme.motion && theme.layoutStyle === "orbit", "live theme change");
            calendar.viewYear = 2026; calendar.viewMonth = 11;
            calendar.step(1);
            check(calendar.viewYear === 2027 && calendar.viewMonth === 0, "next year navigation");
            calendar.selectCell({year: 2026, month: 9, day: 31});
            check(calendar.selectedDate.getDate() === 31 && calendar.viewMonth === 9, "adjacent month selection");
            calendar.resetToday();
            check(calendar.viewMonth === 10 && calendar.selectedDate.getDate() === 12, "today action");
            check(calendar.implicitHeight > 300, "calendar has usable layout");
            check(calendar.agenda.length === 1 && calendar.agenda[0].title === "Design review", "today agenda");
            calendar.editEvent(null);
            check(calendar.editing, "new event opens inline editor");
            check(calendar.back() && !calendar.editing, "back returns to month view");
            calendar.editEvent(fake.snapshot.events[0]);
            findItem(calendar, "eventTitle").text = "Edited";
            findItem(calendar, "saveEvent").clicked();
            check(fake.lastRequest.action === "save" && fake.lastRequest.event.title === "Edited" && fake.lastRequest.event.start === fake.snapshot.events[0].start, "editor preserves offset when changing only title");
            calendar.back();
            var newAction = findItem(calendar, "newEvent");
            var actionPoint = newAction.mapToItem(calendar, 0, 0);
            check(actionPoint.y >= 0 && actionPoint.y + newAction.height <= calendar.height + 1, "new event action stays visible in a short panel");
            calendar.sourcesOpen = true;
            footerTest.start();
        }
    }
}
