import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.mranallo.dropshelf"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: "󰉋"
    tooltipText: "Dropshelf"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton && root.bar && root.bar.shell)
        root.bar.shell.toggle("io.github.mranallo.dropshelf", "{}");
    }
  }
}
