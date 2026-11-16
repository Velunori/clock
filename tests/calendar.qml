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
            else if (state === "sources" || state === "sources-icloud" || state === "sources-google") {
                calendar.sourcesOpen = true;
                calendar.sourcePage = state === "sources" ? "overview" : "connect";
                findItem(calendar, "accountConnection").provider = state === "sources-icloud" ? "icloud" : "google";
            }
            previewCapture.start();
        }
        else Qt.quit();
    }
    Timer {
        id: previewCapture
        interval: 150
        onTriggered: surface.grabToImage(function(result) { result.saveToFile(Quickshell.env("VELUNORI_PREVIEW_PATH")); Qt.quit(); })
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
        property var snapshot: ({timezone: "Europe/Berlin", googleSignInReady: true, calendars: [{id: "local", name: "Personal", color: "#c4aff1", provider: "local", readonly: false, enabled: true}], events: [
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
            check(!button.visible, "calendar overview does not show a detached connection action");
            var addAccount = findItem(calendar, "addAccount");
            var actionPoint = addAccount.mapToItem(calendar, 0, 0);
            check(addAccount.visible && actionPoint.y + addAccount.height <= calendar.height + 1, "account management stays accessible");
            findItem(calendar, "newCalendar").clicked();
            check(calendar.sourcePage === "new" && calendar.back() && calendar.sourcePage === "overview", "new calendar has its own view and back navigation");
            addAccount.clicked();
            check(calendar.sourcePage === "connect", "add account opens connection view");
            var point = button.mapToItem(calendar, 0, 0);
            check(button.visible && point.y >= 0 && point.y + button.height <= calendar.height + 1, "account connect action stays fully visible");
            check(button.height >= 38, "account connect action is not compressed");
            var scroll = findItem(calendar, "calendarScroll");
            scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
            check(Math.abs(button.mapToItem(calendar, 0, 0).y - point.y) < 1, "scrolling settings leaves account action pinned");
            check(button.enabled, "registered Google client needs no user setup file");
            button.clicked();
            check(fake.lastRequest.action === "connectGoogle" && fake.lastRequest.clientFile === undefined, "Connect Google starts sign-in without a JSON path");
            check(calendar.back() && calendar.sourcePage === "overview" && calendar.sourcesOpen, "back from account connection returns to calendars");
            addAccount.clicked();
            fake.snapshot = Object.assign({}, fake.snapshot, {googleSignInReady: false});
            check(!button.enabled, "unconfigured Google sign-in is unavailable");
            check(findItem(calendar, "googleSignInUnavailable").visible, "unconfigured build explains unavailable Google sign-in");
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
            fake.errorText = "End must be after start";
            calendar.back();
            check(fake.errorText === "", "leaving editor clears stale validation error");
            var newAction = findItem(calendar, "newEvent");
            var actionPoint = newAction.mapToItem(calendar, 0, 0);
            check(actionPoint.y >= 0 && actionPoint.y + newAction.height <= calendar.height + 1, "new event action stays visible in a short panel");
            fake.errorText = "End must be after start";
            calendar.sourcesOpen = true;
            check(fake.errorText === "", "opening account settings clears stale validation error");
            fake.snapshot = Object.assign({}, fake.snapshot, {lastSync: "2026-11-12T12:00:00Z", calendars: [
                {id: "google", name: "personal.calendar.with.a.very.long.name@example.com", color: "#c4aff1", provider: "google", account: "fixture", enabled: true},
                {id: "holidays-de", name: "Holidays in Germany", color: "#a0ddbf", provider: "google", account: "fixture", enabled: false},
                {id: "holidays-pl", name: "Holidays in Poland", color: "#91baf0", provider: "google", account: "fixture", enabled: false},
                fake.snapshot.calendars[0]
            ]});
            footerTest.start();
        }
    }
}
