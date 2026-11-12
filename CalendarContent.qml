pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../velunori.core/kit" as Velunori
import "CalendarModel.js" as Calendar

Item {
    id: root
    property var bar: null
    property date today: new Date()
    property int weekStart: Qt.locale().firstDayOfWeek % 7
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    property date selectedDate: today
    readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
    readonly property var cells: Calendar.monthCells(viewYear, viewMonth, weekStart, today, selectedDate)
    implicitWidth: 336
    implicitHeight: content.implicitHeight
    Velunori.Theme { id: theme; bar: root.bar }

    function resetToday() {
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
        id: content
        width: parent.width
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            Text { text: "CALENDAR"; color: theme.accent; font.family: theme.fontFamily; font.pixelSize: 11; font.letterSpacing: 2 }
            Item { Layout.fillWidth: true }
            Text { text: "Local time"; color: theme.muted; font.family: theme.fontFamily; font.pixelSize: 12 }
        }
        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(root.today, "dddd, d MMMM")
            color: theme.text; font.family: theme.fontFamily; font.pixelSize: 22; font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Qt.formatDate(root.viewDate, "MMMM yyyy")
                color: theme.text; font.family: theme.fontFamily; font.pixelSize: 16; font.weight: Font.Medium
            }
            Velunori.Button { bar: root.bar; text: "‹"; implicitWidth: 32; implicitHeight: 32; Accessible.name: "Previous month"; onClicked: root.step(-1) }
            Velunori.Button { bar: root.bar; text: "›"; implicitWidth: 32; implicitHeight: 32; Accessible.name: "Next month"; onClicked: root.step(1) }
        }
        Grid {
            id: calendarGrid
            Layout.fillWidth: true
            columns: 7; spacing: 4
            readonly property real cellWidth: (width - spacing * 6) / 7
            Repeater {
                model: 7
                Text {
                    required property int index
                    width: calendarGrid.cellWidth; height: 24
                    text: Qt.locale().dayName((root.weekStart + index) % 7 || 7, Locale.ShortFormat)
                    color: theme.muted; font.family: theme.fontFamily; font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }
            Repeater {
                model: root.cells
                delegate: AbstractButton {
                    id: dayButton
                    required property var modelData
                    width: calendarGrid.cellWidth; height: 34
                    hoverEnabled: true
                    Accessible.name: Qt.formatDate(new Date(modelData.year, modelData.month, modelData.day, 12), "dddd, d MMMM yyyy")
                    onClicked: root.selectCell(modelData)
                    background: Rectangle {
                        radius: 10
                        color: dayButton.modelData.selected ? theme.accent : dayButton.hovered ? theme.surface : "transparent"
                        border.color: dayButton.modelData.isToday || dayButton.activeFocus ? theme.accent : "transparent"
                        border.width: 1
                    }
                    contentItem: Text {
                        text: dayButton.modelData.day
                        color: dayButton.modelData.selected ? theme.background : dayButton.modelData.inMonth ? theme.text : theme.muted
                        opacity: dayButton.modelData.inMonth || dayButton.modelData.selected ? 1 : 0.5
                        font.family: theme.fontFamily; font.pixelSize: 13
                        font.weight: dayButton.modelData.isToday ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Qt.formatDate(root.selectedDate, "d MMMM yyyy")
                color: theme.muted; font.family: theme.fontFamily; font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            Velunori.Button { bar: root.bar; text: "Today"; implicitWidth: 76; implicitHeight: 34; onClicked: root.resetToday() }
        }
    }
}
