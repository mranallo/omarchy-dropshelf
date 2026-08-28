import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property bool closingFromHost: false
  property var entries: []
  property string statusText: "Drop files here"
  property string anchorScreen: ""
  property int anchorX: 0
  property int anchorY: 0
  property int anchorWidth: 0
  property int anchorHeight: 0
  property int barWidth: 0
  property int barHeight: 0
  property string barPosition: "top"
  property var pendingCandidates: []
  property int candidateAttempts: 0
  readonly property int maxCandidateAttempts: 4
  property var lastRemovedEntry: null
  property string activeDragUri: ""
  property bool selfDrop: false

  readonly property string pluginId: "io.github.mranallo.dropshelf"
  readonly property string stateDir: {
    const configured = Quickshell.env("XDG_STATE_HOME");
    return configured && configured.length > 0
      ? configured + "/omarchy-dropshelf"
      : Quickshell.env("HOME") + "/.local/state/omarchy-dropshelf";
  }
  readonly property string statePath: root.stateDir + "/shelf.json"
  readonly property string anchorPath: root.stateDir + "/anchor.json"
  readonly property string dataDir: {
    const configured = Quickshell.env("XDG_DATA_HOME");
    return configured && configured.length > 0
      ? configured + "/omarchy-dropshelf"
      : Quickshell.env("HOME") + "/.local/share/omarchy-dropshelf";
  }
  readonly property color mutedForeground: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
  readonly property color subtleSurface: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
  readonly property color hairline: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
  readonly property var popupBorder: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  function open(payloadJson) {
    closingFromHost = false;
    if (payloadJson) {
      try {
        const payload = JSON.parse(String(payloadJson));
        // A summon without bar geometry (e.g. a keybinding's empty payload)
        // reuses the last remembered anchor instead of resetting it.
        if (payload && payload.screen && Number(payload.width) > 0) {
          applyAnchor(payload);
          saveAnchor(payload);
        }
      } catch (error) { }
    }
    shelfWindow.visible = true;
  }

  function applyAnchor(payload) {
    anchorScreen = String(payload.screen || "");
    anchorX = Number(payload.x) || 0;
    anchorY = Number(payload.y) || 0;
    anchorWidth = Number(payload.width) || 0;
    anchorHeight = Number(payload.height) || 0;
    barWidth = Number(payload.barWidth) || 0;
    barHeight = Number(payload.barHeight) || 0;
    barPosition = String(payload.barPosition || "top");
  }

  function saveAnchor(payload) {
    anchorWriter.command = ["bash", "-c", "umask 077; mkdir -p -- \"$1\" && printf '%s' \"$2\" > \"$3\"", "dropshelf", stateDir, JSON.stringify(payload), anchorPath];
    anchorWriter.running = true;
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
    if (urls.length > 0) {
      if (activeDragUri !== "" && urls.indexOf(activeDragUri) !== -1)
        selfDrop = true;
      const next = Model.addUrls(entries, urls);
      const added = next.length - entries.length;
      entries = next;
      statusText = added > 0 ? "Added " + added + (added === 1 ? " item" : " items") : "Already on the shelf";
      persist();
      return;
    }

    if (downloader.running || imageWriter.running) {
      statusText = "Please wait for the current image";
      return;
    }

    const nativeUrl = firstMimeText(drop, [
      "application/x-moz-file-promise-url",
      "application/x-moz-url",
      "text/x-moz-url",
      "DownloadURL"
    ]) || anyTextMime(drop);
    pendingCandidates = Model.remoteImageCandidates(drop.urls || [], drop.hasText ? drop.text : "", drop.hasHtml ? drop.html : "", nativeUrl);
    candidateAttempts = 0;

    const imageFormat = imageMimeFormat(drop.formats || []);
    if (imageFormat !== "") {
      importBase64Image(imageFormat, Model.base64FromArrayBuffer(drop.getDataAsArrayBuffer(imageFormat)));
      return;
    }
    if (pendingCandidates.length > 0) {
      tryNextCandidate();
      return;
    }
    statusText = "Drop a local file or browser image";
  }

  function tryNextCandidate() {
    if (candidateAttempts >= maxCandidateAttempts || pendingCandidates.length === 0) {
      pendingCandidates = [];
      statusText = "Could not save that image";
      return;
    }
    const next = String(pendingCandidates.shift());
    candidateAttempts++;
    console.log("[dropshelf] import attempt " + candidateAttempts + ": " + next.substring(0, 120));
    const data = Model.parseDataUri(next);
    if (data !== null) {
      importBase64Image(data.mime, data.base64);
      return;
    }
    startDownload(next);
  }

  function importFinished() {
    pendingCandidates = [];
    candidateAttempts = 0;
  }

  function imageMimeFormat(formats) {
    const preferred = ["image/gif", "image/webp", "image/png", "image/jpeg", "image/avif", "image/bmp"];
    for (let i = 0; i < preferred.length; i++)
      if (formats.indexOf(preferred[i]) !== -1) return preferred[i];
    return "";
  }

  function firstMimeText(drop, formats) {
    for (let i = 0; i < formats.length; i++) {
      if ((drop.formats || []).indexOf(formats[i]) === -1) continue;
      const value = String(drop.getDataAsString(formats[i]) || "").trim();
      if (value !== "") return value;
    }
    return "";
  }

  function anyTextMime(drop) {
    const formats = drop.formats || [];
    for (let i = 0; i < formats.length; i++) {
      const format = String(formats[i]);
      if (!/^text\//i.test(format) && format.toLowerCase().indexOf("url") === -1) continue;
      const value = String(drop.getDataAsString(format) || "").trim();
      if (value.indexOf("http://") !== -1 || value.indexOf("https://") !== -1)
        return value;
    }
    return "";
  }

  function importBase64Image(mime, base64) {
    const suffix = String(mime).split("/").pop().replace(/[^a-zA-Z0-9]/g, "") || "img";
    statusText = "Saving image…";
    imageWriter.command = ["bash", "-c", "set -e; umask 077; mkdir -p -- \"$1\"; out=$(mktemp --tmpdir=\"$1\" dropshelf-XXXXXX.\"$2\"); trap 'rm -f -- \"$out\"' EXIT; base64 -d > \"$out\"; file -Lb --mime-type \"$out\" | grep -q '^image/'; trap - EXIT; printf '%s' \"$out\"", "dropshelf", dataDir, suffix];
    imageWriter.stdinEnabled = true;
    imageWriter.running = true;
    imageWriter.write(base64);
    imageWriter.stdinEnabled = false;
  }

  function startDownload(url) {
    statusText = candidateAttempts > 1 ? "Saving image… (trying another source)" : "Saving image…";
    downloader.command = ["bash", "-c",
      "set -e; umask 077; mkdir -p -- \"$1\"; out=$(mktemp --tmpdir=\"$1\" dropshelf-XXXXXX); trap 'rm -f -- \"$out\"' EXIT; curl -fL --max-time 30 --max-filesize 52428800 --proto '=http,https' -A 'Mozilla/5.0' -e \"$3\" -o \"$out\" -- \"$2\"; mime=$(file -Lb --mime-type \"$out\"); case \"$mime\" in image/*) ;; *) exit 65 ;; esac; ext=$(printf '%s' \"${mime#image/}\" | tr -cd 'a-zA-Z0-9'); final=\"${out}.${ext:-img}\"; mv -- \"$out\" \"$final\"; trap - EXIT; printf '%s' \"$final\"",
      "dropshelf", dataDir, url, Model.refererFor(url)];
    downloader.running = true;
  }

  function removeAt(index) {
    entries = Model.removeAt(entries, index);
    statusText = entries.length === 0 ? "Drop files here" : entries.length + (entries.length === 1 ? " item" : " items");
    persist();
  }

  function removeUri(uri) {
    entries = Model.removeUri(entries, uri);
    statusText = entries.length === 0 ? "Drop files here" : entries.length + (entries.length === 1 ? " item" : " items");
    persist();
  }

  // The drop action reported for native drags is unreliable (Electron and
  // browser targets mirror page JS, not actual success), so every drag-out
  // removes the tile and Undo covers the failed-drop case.
  function removeAfterDrag(uri) {
    const matches = entries.filter(function(item) { return item.uri === uri; });
    if (matches.length === 0)
      return;
    lastRemovedEntry = matches[0];
    entries = Model.removeUri(entries, uri);
    statusText = "Dragged out — Undo to restore";
    persist();
  }

  function undoRemove() {
    if (!lastRemovedEntry)
      return;
    entries = Model.addUrls(entries, [lastRemovedEntry.uri]);
    lastRemovedEntry = null;
    statusText = entries.length + (entries.length === 1 ? " item" : " items");
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

  FileView {
    id: anchorFile
    path: root.anchorPath
    onLoaded: {
      try {
        const payload = JSON.parse(String(text()));
        // Only seed from disk if no bar click has anchored the shelf yet.
        if (root.anchorScreen === "" && payload && payload.screen)
          root.applyAnchor(payload);
      } catch (error) { }
    }
    onLoadFailed: { }
  }

  Process {
    id: anchorWriter
    running: false
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

  Process {
    id: downloader
    running: false
    stdout: StdioCollector {
      id: downloadOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      const path = String(downloadOutput.text || "").trim();
      if (exitCode !== 0 || path === "") {
        console.log("[dropshelf] download failed with exit " + exitCode);
        root.tryNextCandidate();
        return;
      }
      root.importFinished();
      const uri = "file://" + encodeURI(path);
      const next = Model.addUrls(root.entries, [uri]);
      root.entries = next;
      root.statusText = "Image added";
      root.persist();
    }
  }

  Process {
    id: imageWriter
    running: false
    stdout: StdioCollector {
      id: imageWriterOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.finishImportedImage(exitCode, imageWriterOutput.text)
    }
  }

  function finishImportedImage(exitCode, output) {
    const path = String(output || "").trim();
    if (exitCode !== 0 || path === "") {
      console.log("[dropshelf] image import failed with exit " + exitCode);
      tryNextCandidate();
      return;
    }
    importFinished();
    const uri = "file://" + encodeURI(path);
    entries = Model.addUrls(entries, [uri]);
    statusText = "Image added";
    persist();
  }

  PanelWindow {
    id: shelfWindow

    color: Color.background
    // Compact 2x2 tile grid: two cells wide plus chrome, two rows tall.
    implicitWidth: Style.space(280)
    implicitHeight: Style.space(392)
    visible: false
    screen: {
      for (let i = 0; i < Quickshell.screens.length; i++)
        if (String(Quickshell.screens[i].name || "") === root.anchorScreen)
          return Quickshell.screens[i];
      return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }
    WlrLayershell.namespace: "omarchy-dropshelf"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0

    anchors {
      top: root.barPosition !== "bottom"
      bottom: root.barPosition === "bottom"
      left: root.barPosition !== "right"
      right: root.barPosition === "right"
    }

    margins {
      top: root.barPosition === "top" ? 0 : Math.max(Style.gapsOut, root.anchorY + root.anchorHeight / 2 - shelfWindow.height / 2)
      bottom: 0
      left: {
        if (root.barPosition === "left") return 0;
        if (root.barPosition === "right") return 0;
        return Math.max(Style.gapsOut, Math.min(root.anchorX + root.anchorWidth / 2 - shelfWindow.width / 2, shelfWindow.screen.width - shelfWindow.width - Style.gapsOut));
      }
      right: 0
    }

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.pluginId);
    }

    BorderSurface {
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: root.popupBorder
      radius: Style.cornerRadius
      clip: true

      DropArea {
        id: windowDropArea
        anchors.fill: parent
        anchors.margins: Math.max(Border.top(root.popupBorder), Border.right(root.popupBorder), Border.bottom(root.popupBorder), Border.left(root.popupBorder))
        onDropped: function(drop) {
          drop.acceptProposedAction();
          root.addDrop(drop);
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          radius: Math.max(0, Style.cornerRadius - Style.space(2))
          color: windowDropArea.containsDrag ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : "transparent"
          border.width: windowDropArea.containsDrag ? Style.space(2) : 0
          border.color: Color.accent

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(16)
            spacing: Style.space(12)

            Item {
              width: parent.width
              implicitHeight: Math.max(titleColumn.implicitHeight, headerButtons.implicitHeight)

              Column {
                id: titleColumn
                anchors.left: parent.left
                anchors.right: headerButtons.left
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: "Drop Shelf"
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

              Row {
                id: headerButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Button {
                  id: undoButton
                  visible: root.lastRemovedEntry !== null
                  text: "Undo"
                  fontSize: Style.font.bodySmall
                  foreground: Color.foreground
                  fontFamily: Style.font.family
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  onClicked: root.undoRemove()
                }

                Button {
                  id: clearButton
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
                text: "Local files stay in their original locations. Browser images are saved privately so they can be dragged into another application."
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
                // Holds the grab result so its image:// URL stays valid for the drag.
                property var grabResult: null

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
                    id: removeButton
                    width: Style.space(22)
                    height: width
                    radius: width / 2
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Style.space(5)
                    visible: tileMouse.containsMouse && !tile.Drag.active
                    z: 2
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
                      z: 3
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.removeAt(tile.index)
                    }
                  }
                }

                // Canonical external-drag pattern: Drag.active follows the
                // MouseArea's threshold-based drag state, and the native drag
                // ends on its own. Calling Drag.drop()/Drag.cancel() on an
                // Automatic drag resets its state mid-flight (the native drag
                // steals the grab, firing onCanceled), which loses the real
                // drop action.
                Drag.active: tileMouse.drag.active
                Drag.mimeData: ({ "text/uri-list": tile.uri + "\r\n" })
                Drag.supportedActions: Qt.CopyAction
                Drag.proposedAction: Qt.CopyAction
                Drag.dragType: Drag.Automatic
                Drag.imageSource: tile.imageFile ? tile.uri : ""
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                Drag.onDragStarted: {
                  root.activeDragUri = tile.uri;
                  root.selfDrop = false;
                }
                Drag.onDragFinished: function(dropAction) {
                  tile.x = 0;
                  tile.y = 0;
                  console.log("[dropshelf] outgoing drag finished with action " + dropAction);
                  const droppedOnShelf = root.selfDrop && root.activeDragUri === tile.uri;
                  root.activeDragUri = "";
                  root.selfDrop = false;
                  if (!droppedOnShelf)
                    root.removeAfterDrag(tile.uri);
                }

                MouseArea {
                  id: tileMouse
                  anchors.fill: parent
                  z: 1
                  hoverEnabled: true
                  cursorShape: Qt.OpenHandCursor
                  drag.target: tile
                  preventStealing: true
                  onPressed: {
                    // Non-image files have no source image to show while
                    // dragging; snapshot the tile before the drag starts.
                    if (!tile.imageFile)
                      tileSurface.grabToImage(function(result) {
                        tile.grabResult = result;
                        tile.Drag.imageSource = result.url;
                      });
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
}
