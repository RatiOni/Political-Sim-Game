import QtQuick
import "." as Ui

Row {
    id: root
    property var forces: []
    spacing: 2
    height: forces.length > 0 ? 6 : 0
    visible: forces.length > 0

    Repeater {
        model: root.forces
        delegate: Rectangle {
            required property var modelData
            width: 10
            height: 4
            radius: 2
            color: {
                var base = modelData.sign === "positive" ? Ui.Theme.good : Ui.Theme.critical;
                switch (modelData.phase) {
                    case "onset": return Ui.Theme.inkFaint;
                    case "ramp":  return Qt.lighter(base, 1.15);
                    case "hold":  return base;
                    case "decay": return Qt.lighter(Ui.Theme.inkFaint, 1.0);
                    default: return Ui.Theme.inkFaint;
                }
            }
            opacity: modelData.phase === "decay" ? 0.6 : 1.0

            Behavior on color { ColorAnimation { duration: Ui.Theme.durationMediumMin } }
            Behavior on opacity { NumberAnimation { duration: Ui.Theme.durationMediumMin } }
        }
    }
}
