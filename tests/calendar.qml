//@ pragma OmarchyLoadPatch
import Quickshell
import QtQuick
import "velunori.clock"
import "velunori.core/kit" as Velunori

ShellRoot {
    property string failure: ""
    function check(value, message) { if (!value) failure += message + "; "; }
    QtObject {
        id: host
        property var velunori: ({apiVersion: 1, accentName: "mint", motion: false})
    }
    Velunori.Theme { id: theme; bar: host }
    FloatingWindow {
        visible: true
        implicitWidth: 376
        implicitHeight: calendar.implicitHeight + 40
        color: "#202026"
        Rectangle {
            id: surface
            anchors.fill: parent
            color: "#202026"
            CalendarContent {
                id: calendar
                x: 20; y: 20; width: parent.width - 40
                today: new Date(2026, 10, 12, 12)
                bar: host
            }
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
            console.log(failure ? "CALENDAR_TEST_FAILED: " + failure : "CALENDAR_TEST_PASSED");
            var path = Quickshell.env("VELUNORI_PREVIEW_PATH");
            if (path) surface.grabToImage(function(result) { result.saveToFile(path); Qt.quit(); });
            else Qt.quit();
        }
    }
}
