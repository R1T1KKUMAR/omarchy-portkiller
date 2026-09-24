import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Portkiller: local dev-server manager in the bar.
// Bar shows a server glyph + live localhost port count.
// Click opens an anchored panel: filterable list of
// port / process / pid / cwd with Open + Kill per row.
//
// Keys (when filter field is NOT focused):
//   j/k or arrows  move · enter open · x / ctrl+k kill (again = force)
//   r refresh · esc clear filter, then close
// Kill targets the port (all current holders), not the listed PID,
// so stale PIDs and multi-holder ports die reliably.
// When the filter field is focused, typing filters normally.
Panel {
  id: root
  moduleName: "dev.ritik.portkiller"
  ipcTarget: "dev.ritik.portkiller"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string helperPath: Qt.resolvedUrl("list-ports.sh").toString().replace("file://", "")

  property var ports: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool loading: false
  property var pendingKill: null
  property string statusText: ""

  readonly property int portCount: ports.length

  function refresh() {
    if (listProc.running) return
    root.loading = true
    listProc.running = true
  }

  function loadPorts(raw) {
    var parsed = []
    try { parsed = JSON.parse(raw || "[]") } catch (e) { parsed = [] }
    root.ports = parsed
    root.loading = false
    root.rebuildDisplay()
    root.verifyPendingKill()
  }

  function matches(row, needle) {
    if (!needle) return true
    var hay = (row.port + " " + row.process + " " + row.pid + " " + row.cwd).toLowerCase()
    return hay.indexOf(needle) !== -1
  }

  function rebuildDisplay() {
    var needle = root.filterText.toLowerCase()
    displayModel.clear()
    for (var i = 0; i < root.ports.length; i++) {
      var row = root.ports[i]
      if (root.matches(row, needle))
        displayModel.append({ port: row.port, process: row.process, pid: row.pid, cwd: row.cwd })
    }
    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  function setFilter(t) {
    root.filterText = t
    root.selectedIndex = 0
    root.cursorActive = false
    root.rebuildDisplay()
  }

  function moveCursor(dy) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(displayModel.count - 1, root.selectedIndex + dy))
  }

  function selectedRow() {
    if (root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    return displayModel.get(root.selectedIndex)
  }

  function openSelected() {
    var row = root.selectedRow()
    if (!row) return
    Quickshell.execDetached(["xdg-open", "http://localhost:" + row.port])
  }

  // Kill by PORT, not PID: the panel list is a snapshot, so a stored PID
  // may be stale (dev servers restart under HMR) or partial (several
  // holders sharing one port, one row). fuser resolves the current
  // holders at kill time. First press sends SIGTERM; if the port is
  // still listed afterwards, the next press escalates to SIGKILL.
  function killByPort(port) {
    var p = String(port || "")
    if (!/^[0-9]+$/.test(p)) return "bad port"
    var sig = (root.pendingKill && root.pendingKill.port === p) ? "KILL" : "TERM"
    Quickshell.execDetached(["fuser", "-k", "-" + sig, p + "/tcp"])
    root.pendingKill = { port: p, signal: sig }
    root.statusText = sig === "KILL"
      ? ("Sent SIGKILL to port " + p + " holders…")
      : ("Sent SIGTERM to port " + p + " holders…")
    refreshDelay.restart()
    return "ok"
  }

  function verifyPendingKill() {
    if (!root.pendingKill) return
    var p = root.pendingKill.port
    var sig = root.pendingKill.signal
    var still = false
    for (var i = 0; i < root.ports.length; i++) {
      if (String(root.ports[i].port) === p) { still = true; break }
    }
    if (!still) {
      root.statusText = "Port " + p + " freed"
      root.pendingKill = null
    } else if (sig === "KILL") {
      root.statusText = "Port " + p + " still listening after SIGKILL (respawning?)"
    } else {
      root.statusText = "Port " + p + " still listening — Kill again to force"
    }
  }

  function killSelected() {
    var row = root.selectedRow()
    if (!row) return
    root.killByPort(row.port)
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    root.cursorActive = false
    root.selectedIndex = 0
    root.setFilter("")
    if (filterField) filterField.text = ""
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  ListModel { id: displayModel }

  Process {
    id: listProc
    command: ["bash", root.helperPath]
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.loading = false
        return
      }
      root.loadPorts(listOut.text)
    }
  }

  Timer {
    id: refreshDelay
    interval: 400
    onTriggered: root.refresh()
  }

  // Badge refresh every 20s so the bar count stays honest.
  Timer {
    interval: 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // While the panel sits open, re-poll every 5s.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒍"
    tooltipText: root.portCount > 0
      ? root.portCount + " local server" + (root.portCount === 1 ? "" : "s") + " running"
      : "No local servers running"
    onPressed: root.toggle()

    Rectangle {
      visible: root.portCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Style.space(2)
      width: Math.max(height, badgeText.implicitWidth + Style.space(6))
      height: badgeText.implicitHeight + Style.space(2)
      radius: height / 2
      color: root.bar ? root.bar.urgent : Color.urgent

      Text {
        id: badgeText
        anchors.centerIn: parent
        text: root.portCount > 99 ? "99+" : String(root.portCount)
        color: Color.popups.background
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.caption * 0.8)
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: filterField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.openSelected()
      onDeleteRequested: root.killSelected()
      onCloseRequested: {
        if (root.filterText !== "") {
          filterField.text = ""
          root.setFilter("")
        } else {
          root.close()
        }
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "x" || t === "X") root.killSelected()
      }

      // Ctrl+K / Ctrl+R while the catcher has focus.
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
          root.killSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
          root.refresh()
          event.accepted = true
        }
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(titleText.implicitHeight, refreshBtn.implicitHeight)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.portCount > 0
              ? "Local servers (" + root.portCount + ")"
              : "Local servers"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Button {
            id: refreshBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.loading ? "…" : "Refresh"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.refresh()
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: "LISTENING PORTS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        TextField {
          id: filterField
          width: parent.width
          placeholderText: "Filter — e.g. 3000, node, myproject"
          text: root.filterText
          onTextChanged: root.setFilter(text)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (text !== "") {
                text = ""
                event.accepted = true
              } else {
                root.close()
                event.accepted = true
              }
            } else if (event.key === Qt.Key_Down) {
              root.moveCursor(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveCursor(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.openSelected()
              event.accepted = true
            }
          }
        }

        Text {
          visible: root.loading && displayModel.count === 0
          width: parent.width
          text: "scanning localhost…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: !root.loading && displayModel.count === 0
          width: parent.width
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)
          text: root.filterText !== ""
            ? "No ports match \"" + root.filterText + "\""
            : "Nothing is listening on localhost"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        ListView {
          id: resultList
          visible: displayModel.count > 0
          width: parent.width
          height: Math.min(displayModel.count * Style.space(52), Style.space(320))
          model: displayModel
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            id: rowItem
            required property int index
            required property string port
            required property string process
            required property string pid
            required property string cwd

            readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

            width: resultList.width
            height: Style.space(52)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: rowItem.hasCursor || rowMouse.containsMouse
                ? root.selectedBackground : "transparent"
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.spacing.sm

              Text {
                width: Style.space(52)
                anchors.verticalCenter: parent.verticalCenter
                text: rowItem.port
                color: (rowItem.hasCursor || rowMouse.containsMouse) ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Column {
                width: parent.width - Style.space(52) - killBtn.width - openBtn.width - Style.spacing.sm * 3
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  width: parent.width
                  text: rowItem.process + " · " + rowItem.pid
                  color: (rowItem.hasCursor || rowMouse.containsMouse) ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: rowItem.cwd
                  color: (rowItem.hasCursor || rowMouse.containsMouse) ? root.selectedText : root.dim
                  opacity: (rowItem.hasCursor || rowMouse.containsMouse) ? 0.85 : 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              Button {
                id: openBtn
                anchors.verticalCenter: parent.verticalCenter
                text: "Open"
                bordered: true
                foreground: (rowItem.hasCursor || rowMouse.containsMouse) ? root.selectedText : root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: {
                  root.selectedIndex = rowItem.index
                  root.openSelected()
                }
              }

              Button {
                id: killBtn
                anchors.verticalCenter: parent.verticalCenter
                enabled: /^\d+$/.test(rowItem.pid)
                text: "Kill"
                bordered: true
                foreground: (rowItem.hasCursor || rowMouse.containsMouse) ? root.selectedText : root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: {
                  root.selectedIndex = rowItem.index
                  root.killSelected()
                }
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              z: -1
              onContainsMouseChanged: if (containsMouse) {
                root.cursorActive = true
                root.selectedIndex = rowItem.index
              }
              onClicked: {
                root.selectedIndex = rowItem.index
                root.openSelected()
              }
            }
          }
        }

        Text {
          visible: root.statusText !== ""
          width: parent.width
          text: root.statusText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "enter open · x / ctrl+k kill (again = force) · r refresh · esc close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
