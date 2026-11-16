import QtQuick
import QtQuick.Controls
import "../lib/kit" as V
TextField {
    id: root
    property var bar: null
    V.Theme { id: theme; bar: root.bar }
    implicitHeight: 38; leftPadding: 12; rightPadding: 12
    color: theme.text; placeholderTextColor: theme.muted; font.pixelSize: 13
    selectionColor: theme.accent; selectedTextColor: theme.background; selectByMouse: true
    background: Rectangle { radius: 10; color: theme.surface; border.color: root.activeFocus ? theme.accent : theme.border }
}
