import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property bool closingFromHost: false
  property var entries: []
  property string statusText: "Drop files here"

  readonly property string pluginId: "io.github.mranallo.dropshelf"
  readonly property string stateDir: {
    const configured = Quickshell.env("XDG_STATE_HOME");
    return configured && configured.length > 0
      ? configured + "/omarchy-dropshelf"
      : Quickshell.env("HOME") + "/.local/state/omarchy-dropshelf";
  }
  readonly property string statePath: root.stateDir + "/shelf.json"
  readonly property color mutedForeground: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
  readonly property color subtleSurface: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
  readonly property color hairline: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)

  function open(payloadJson) {
    closingFromHost = false;
    shelfWindow.visible = true;
  }

  function close() {
    closingFromHost = true;
    shelfWindow.visible = false;
    closingFromHost = false;
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function")
      shell.hide(pluginId);
    else
      shelfWindow.visible = false;
  }

  function loadState(text) {
    entries = Model.parseState(text);
    statusText = entries.length === 0 ? "Drop files here" : entries.length + (entries.length === 1 ? " item" : " items");
  }

  function addDrop(drop) {
    const urls = Model.localUrls(drop.urls || []);
    if (urls.length === 0) {
      statusText = "Only local files are supported";
      return;
    }
    const next = Model.addUrls(entries, urls);
    const added = next.length - entries.length;
    entries = next;
    statusText = added > 0 ? "Added " + added + (added === 1 ? " item" : " items") : "Already on the shelf";
    persist();
  }

  function removeAt(index) {
    entries = Model.removeAt(entries, index);
    statusText = entries.length === 0 ? "Drop files here" : entries.length + (entries.length === 1 ? " item" : " items");
    persist();
  }

  function clearShelf() {
    entries = [];
    statusText = "Shelf cleared";
    persist();
  }

  function persist() {
    writer.command = ["bash", "-c", "umask 077; mkdir -p -- \"$1\" && printf '%s' \"$2\" > \"$3\"", "dropshelf", stateDir, Model.serialize(entries), statePath];
    writer.running = true;
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  Process {
    id: writer
    running: false
    onExited: function(exitCode) {
      if (exitCode === 0)
        stateFile.reload();
      else
        root.statusText = "Could not save shelf";
    }
  }

  FloatingWindow {
    id: shelfWindow

    title: "Dropshelf"
    color: Color.background
    implicitWidth: 420
    implicitHeight: 560
    minimumSize: Qt.size(320, 300)
    visible: false

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.pluginId);
    }

    DropArea {
      id: windowDropArea
      anchors.fill: parent
      keys: ["text/uri-list"]
      onDropped: function(drop) {
        drop.acceptProposedAction();
        root.addDrop(drop);
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(10)
        radius: Style.cornerRadius
        color: windowDropArea.containsDrag ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : "transparent"
        border.width: windowDropArea.containsDrag ? Style.space(2) : 0
        border.color: Color.accent

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(titleColumn.implicitHeight, clearButton.implicitHeight)

            Column {
              id: titleColumn
              anchors.left: parent.left
              anchors.right: clearButton.left
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "Dropshelf"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
                color: Color.foreground
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.statusText
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: root.mutedForeground
                elide: Text.ElideRight
              }
            }

            Button {
              id: clearButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.entries.length > 0
              text: "Clear"
              fontSize: Style.font.bodySmall
              foreground: Color.foreground
              fontFamily: Style.font.family
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.clearShelf()
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.hairline
          }

          Item {
            width: parent.width
            height: parent.height - y

            Column {
              anchors.centerIn: parent
              width: Math.min(parent.width, Style.space(260))
              spacing: Style.space(10)
              visible: root.entries.length === 0

              Text {
                width: parent.width
                text: "󰉋"
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                color: windowDropArea.containsDrag ? Color.accent : root.mutedForeground
              }

              Text {
                width: parent.width
                text: windowDropArea.containsDrag ? "Release to add" : "Drop files or images onto this window"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.foreground
              }

              Text {
                width: parent.width
                text: "Files stay in their original locations. Drag them from here into Slack or another application."
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: root.mutedForeground
              }
            }

            GridView {
              id: shelfGrid
              anchors.fill: parent
              visible: root.entries.length > 0
              clip: true
              model: root.entries
              cellWidth: width / Math.max(1, Math.floor(width / Style.space(112)))
              cellHeight: Style.space(132)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                id: tile
                required property var modelData
                required property int index

                width: shelfGrid.cellWidth
                height: shelfGrid.cellHeight

                readonly property string uri: String(modelData.uri || "")
                readonly property string name: String(modelData.name || "File")
                readonly property bool imageFile: Model.isImage(name)

                Rectangle {
                  id: tileSurface
                  anchors.fill: parent
                  anchors.margins: Style.space(5)
                  radius: Style.cornerRadius
                  color: tileMouse.containsMouse || tile.Drag.active ? root.subtleSurface : "transparent"
                  border.width: Style.spacing.hairline
                  border.color: tile.Drag.active ? Color.accent : root.hairline

                  Image {
                    id: thumbnail
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: Style.space(10)
                    width: Style.space(72)
                    height: Style.space(72)
                    source: tile.imageFile ? tile.uri : ""
                    visible: tile.imageFile && status === Image.Ready
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(width * 2, height * 2)
                  }

                  Text {
                    anchors.centerIn: thumbnail
                    visible: !thumbnail.visible
                    text: "󰈔"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.display
                    color: root.mutedForeground
                  }

                  Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.space(8)
                    text: tile.name
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.foreground
                    elide: Text.ElideMiddle
                  }

                  Rectangle {
                    width: Style.space(22)
                    height: width
                    radius: width / 2
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Style.space(5)
                    visible: tileMouse.containsMouse && !tile.Drag.active
                    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.88)
                    border.width: Style.spacing.hairline
                    border.color: root.hairline

                    Text {
                      anchors.centerIn: parent
                      text: "×"
                      font.pixelSize: Style.font.body
                      color: Color.foreground
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.removeAt(tile.index)
                    }
                  }
                }

                Drag.mimeData: ({ "text/uri-list": tile.uri + "\r\n" })
                Drag.supportedActions: Qt.CopyAction
                Drag.proposedAction: Qt.CopyAction
                Drag.dragType: Drag.Automatic
                Drag.imageSource: tile.imageFile ? tile.uri : ""
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                MouseArea {
                  id: tileMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.OpenHandCursor
                  drag.target: tile
                  onPressed: tile.Drag.active = true
                  onReleased: {
                    tile.Drag.drop();
                    tile.Drag.active = false;
                    tile.x = 0;
                    tile.y = 0;
                  }
                  onCanceled: {
                    tile.Drag.cancel();
                    tile.Drag.active = false;
                    tile.x = 0;
                    tile.y = 0;
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
