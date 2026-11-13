pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: root
    visible: false
    property bool active: false
    property string start: ""
    property string end: ""
    property var snapshot: ({calendars: [], events: [], timezone: ""})
    property string errorText: ""
    property var queue: []
    property int revision: 0
    property string lastSyncWindow: ""
    property real lastSyncAttempt: 0
    readonly property bool busy: action.running || queue.length > 0
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("scripts/calendar-backend.sh").toString().replace(/^(file|qs):\/\//, ""))
    signal completed(var request, var response)
    function refresh() { if (active && start && end && !query.running && !busy) query.running = true; }
    function maybeSync() {
        if (!active || busy || !start || !end || !snapshot.calendars.some(function(row) { return row.provider !== "local" && row.enabled; })) return;
        var window = start + ":" + end;
        if (window === lastSyncWindow && Date.now() - lastSyncAttempt < 600000) return;
        lastSyncWindow = window; lastSyncAttempt = Date.now(); perform({action: "sync"});
    }
    onSnapshotChanged: cloudDebounce.restart()
    function perform(request) {
        if (request.action === "sync" || request.action === "connectGoogle" || request.action === "connectIcloud") { lastSyncWindow = start + ":" + end; lastSyncAttempt = Date.now(); }
        request.start = start; request.end = end; revision++; errorText = ""; queue = queue.concat([request]); drain(); }
    function drain() {
        if (action.running || !queue.length) return;
        action.request = queue[0]; queue = queue.slice(1); action.running = true;
    }
    onActiveChanged: { refresh(); if (active) cloudDebounce.restart(); }
    onStartChanged: { debounce.restart(); cloudDebounce.restart(); }
    onEndChanged: { debounce.restart(); cloudDebounce.restart(); }
    Timer { id: cloudDebounce; interval: 700; onTriggered: root.maybeSync() }
    Timer { interval: 600000; running: root.active; repeat: true; onTriggered: root.maybeSync() }
    Timer { id: debounce; interval: 80; onTriggered: root.refresh() }
    Timer { interval: 15000; running: root.active; repeat: true; onTriggered: root.refresh() }
    Process {
        id: query
        property int revision: 0
        property string windowStart: ""
        property string windowEnd: ""
        command: ["bash", root.helper]
        stdinEnabled: true
        onStarted: {
            revision = root.revision; windowStart = root.start; windowEnd = root.end;
            write(JSON.stringify({action: "snapshot", start: windowStart, end: windowEnd}) + "\n");
        }
        onExited: { stdinEnabled = true; if (revision !== root.revision || windowStart !== root.start || windowEnd !== root.end) debounce.restart(); }
        stdout: StdioCollector {
            onStreamFinished: {
                if (query.revision !== root.revision || query.windowStart !== root.start || query.windowEnd !== root.end) return;
                try { var reply = JSON.parse(text); if (!reply.ok) throw new Error(reply.error); root.snapshot = reply.data; }
                catch (error) { root.errorText = "Could not load calendar data."; }
            }
        }
    }
    Process {
        id: action
        property var request: ({})
        property string result: ""
        command: ["bash", root.helper]
        stdinEnabled: true
        onStarted: { result = ""; write(JSON.stringify(request) + "\n"); }
        stdout: StdioCollector { onStreamFinished: action.result = text; }
        onExited: function(exitCode) {
            stdinEnabled = true;
            var reply;
            try { reply = JSON.parse(result); } catch (error) { reply = {ok: false, error: "Calendar action failed."}; }
            if (exitCode !== 0 || !reply.ok) root.errorText = reply.error || "Calendar action failed.";
            if (reply.ok && request.action === "visibility" && request.enabled) root.lastSyncWindow = "";
            if (reply.ok && reply.data && reply.data.warning) root.errorText = reply.data.warning;
            root.completed(request, reply); request = ({}); Qt.callLater(function() { root.drain(); root.refresh(); });
        }
    }
}
