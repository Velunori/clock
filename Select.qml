pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../lib/kit" as V
ComboBox {
    id: root
    property var bar: null
    V.Theme { id: theme; bar: root.bar }
    implicitHeight: 34; leftPadding: 10; rightPadding: 25
    contentItem: Text { text: root.displayText; color: theme.text; elide: Text.ElideRight; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
    indicator: Text { text: "⌄"; color: theme.muted; x: root.width - 20; anchors.verticalCenter: parent.verticalCenter }
    background: Rectangle { radius: 9; color: theme.surface; border.color: root.activeFocus ? theme.accent : theme.border }
    delegate: ItemDelegate {
        id: choice
        required property int index
        required property var modelData
        width: root.width; implicitHeight: 36
        highlighted: root.highlightedIndex === index
        contentItem: Text { text: choice.modelData[root.textRole]; color: theme.text; elide: Text.ElideRight; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 6; color: choice.highlighted ? theme.border : "transparent" }
    }
    popup: Popup {
        y: root.height + 4; width: root.width
        padding: 4; implicitHeight: Math.min(220, options.contentHeight + 8)
        contentItem: ListView { id: options; clip: true; implicitHeight: contentHeight; model: root.popup.visible ? root.delegateModel : null; currentIndex: root.highlightedIndex; ScrollIndicator.vertical: ScrollIndicator {} }
        background: Rectangle { radius: 9; color: theme.surface; border.color: theme.border }
    }
}
