import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.mranallo.dropshelf"
  readonly property bool opened: root.bar && root.bar.shell
    ? root.bar.shell.isPluginOpen("io.github.mranallo.dropshelf")
    : false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function payload() {
    var anchorWindow = button.QsWindow.window;
    if (!anchorWindow || !anchorWindow.screen)
      return "{}";
    var point = anchorWindow.contentItem.mapFromItem(button, 0, 0);
    return JSON.stringify({
      screen: String(anchorWindow.screen.name || ""),
      x: Math.round(point.x),
      y: Math.round(point.y),
      width: Math.round(button.width),
      height: Math.round(button.height),
      barWidth: Math.round(anchorWindow.width),
      barHeight: Math.round(anchorWindow.height),
      barPosition: String(root.bar.position || "top")
    });
  }

  function open() {
    if (root.bar && root.bar.shell)
      root.bar.shell.summon("io.github.mranallo.dropshelf", root.payload());
  }

  function close() {
    if (root.bar && root.bar.shell)
      root.bar.shell.hide("io.github.mranallo.dropshelf");
  }

  function toggleShelf() {
    if (root.opened) root.close();
    else root.open();
  }

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: "󰉋"
    tooltipText: "Dropshelf"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton)
        root.toggleShelf();
    }
  }
}
