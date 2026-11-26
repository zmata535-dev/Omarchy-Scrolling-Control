import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// Hot corners for the Omarchy shell. Pushing the pointer into a configured
// screen corner runs an action — showing the desktop, or any command you like.
//
// The trigger is an invisible layer-shell window a few pixels square, pinned to
// each corner of each screen, with a HoverHandler on it. The compositor tells us
// when the pointer arrives, so nothing polls the cursor position and nothing
// runs between visits to a corner.
//
// Settings live in ~/.config/omarchy/hot-corners.json so they survive
// `omarchy plugin update`, and are re-read the moment that file changes.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  // The helper ships alongside this file, so it resolves wherever the plugin is
  // installed. Qt.resolvedUrl gives a file:// URL; exec needs a plain path.
  readonly property string showDesktopScript: {
    var u = Qt.resolvedUrl("show-desktop").toString()
    return u.indexOf("file://") === 0 ? u.substring(7) : u
  }

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/hot-corners.json"
  readonly property var cornerKeys: ["top-left", "top-right", "bottom-left", "bottom-right"]

  readonly property int defaultSize: 8
  readonly property int defaultDelayMs: 120
  property bool cornerMenuOpen: false
  property bool cornerMenuPointerInside: false
  property string cornerMenuFocusAddress: ""
  function defaultCorners() {
    return {
      "top-left": { action: "open-column-control" },
      "top-right": { action: "open-column-control-menu" },
      "bottom-left": { action: "focus-left" },
      "bottom-right": { action: "focus-right" }
    }
  }

  property int cornerSize: defaultSize
  property int triggerDelayMs: defaultDelayMs
  property var corners: defaultCorners()
  property var hotzoneWindows: []

  function registerHotzone(window) {
    if (!window || hotzoneWindows.indexOf(window) >= 0) return
    hotzoneWindows = hotzoneWindows.concat([window])
  }
  function unregisterHotzone(window) {
    hotzoneWindows = hotzoneWindows.filter(function(candidate) { return candidate !== window })
  }

  function applyConfig(raw) {
    var parsed = null
    if (raw && String(raw).trim() !== "") {
      try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
    }
    if (!parsed || typeof parsed !== "object") {
      root.cornerSize = root.defaultSize
      root.triggerDelayMs = root.defaultDelayMs
      root.corners = root.defaultCorners()
      return
    }
    root.cornerSize = (typeof parsed.size === "number" && parsed.size > 0)
      ? Math.round(parsed.size) : root.defaultSize
    root.triggerDelayMs = (typeof parsed.delayMs === "number" && parsed.delayMs >= 0)
      ? Math.round(parsed.delayMs) : root.defaultDelayMs
    root.corners = (parsed.corners && typeof parsed.corners === "object")
      ? parsed.corners : {}
  }

  // A corner may be given as a bare action string or as an object.
  function entryFor(key) {
    var e = root.corners ? root.corners[key] : null
    if (!e) return null
    if (typeof e === "string") return { action: e }
    if (typeof e === "object") return e
    return null
  }

  function trigger(key) {
    var e = root.entryFor(key)
    if (!e) return
    if (e.action === "open-column-control") {
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", "zm.column-control"])
    } else if (e.action === "open-column-control-menu") {
      root.cornerMenuOpen = !root.cornerMenuOpen
      if (root.cornerMenuOpen) {
        var focused = root.currentTarget()
        root.cornerMenuFocusAddress = focused && focused.address ? String(focused.address) : ""
      } else {
        root.cornerMenuFocusAddress = ""
        root.cornerMenuPointerInside = false
        cornerMenuAutohide.stop()
      }
    } else if (e.action === "focus-left") {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ direction = 'l' })"])
    } else if (e.action === "focus-right") {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ direction = 'r' })"])
    } else if (e.action === "center-focused") {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.layout('center')"])
    } else if (e.action === "close-focused") {
      if (Hyprland.activeToplevel)
        Quickshell.execDetached(["hyprctl", "dispatch", "closewindow", "active"])
    } else if (e.action === "show-desktop") {
      Quickshell.execDetached([root.showDesktopScript])
    } else if (e.action === "command" && Array.isArray(e.command) && e.command.length > 0) {
      // An argument list, never a shell string: nothing is word-split or globbed.
      Quickshell.execDetached(e.command)
    }
  }

  function currentTarget() {
    var waylandActive = ToplevelManager.activeToplevel
    var toplevels = Hyprland.toplevels.values
    if (waylandActive) {
      for (var i = 0; i < toplevels.length; i++) {
        if (toplevels[i].wayland === waylandActive) return toplevels[i]
      }
      return null
    }
    return Hyprland.activeToplevel
  }

  function focusedNormalTarget() {
    var target = currentTarget()
    var workspace = Hyprland.focusedWorkspace
    if (!target || !target.address || !workspace || !target.workspace
        || String(target.workspace.id) !== String(workspace.id)) return null
    var ipc = target.lastIpcObject
    var floating = ipc ? ipc.floating : undefined
    if (!(floating === false || floating === 0 || floating === "0" || floating === "false")) return null
    return target
  }

  function centerFocusedColumn() {
    if (!focusedNormalTarget()) return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.layout('center')"])
  }

  function closeFocusedApp() {
    var target = focusedNormalTarget()
    if (!target || !target.wayland || typeof target.wayland.close !== "function") return
    target.wayland.close()
    root.cornerMenuOpen = false
    root.cornerMenuPointerInside = false
    cornerMenuAutohide.stop()
  }

  function runCornerMenuAction(action) {
    if (action === "close") closeFocusedApp()
    else if (action === "apps") {
      Quickshell.execDetached(["omarchy-shell", "zm.column-control", "openApps"])
      root.cornerMenuOpen = false
      root.cornerMenuPointerInside = false
      cornerMenuAutohide.stop()
    } else if (action === "more") {
      Quickshell.execDetached(["omarchy-shell", "zm.column-control", "openMoreOptions"])
      root.cornerMenuOpen = false
      root.cornerMenuPointerInside = false
      cornerMenuAutohide.stop()
    } else if (action === "qnote") {
      Quickshell.execDetached(["omarchy-shell", "zm.column-control", "openQNote"])
      root.cornerMenuOpen = false
      root.cornerMenuPointerInside = false
      cornerMenuAutohide.stop()
    } else if (action === "power") {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "omarchy.menu", "{\"menu\":\"system\"}"])
      root.cornerMenuOpen = false
      root.cornerMenuPointerInside = false
      cornerMenuAutohide.stop()
    }
  }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
  }

  // The first read can race shell startup, leaving defaults in place until the
  // next write. One delayed reload self-corrects and is a no-op if it was fine.
  Timer {
    interval: 1500
    running: true
    onTriggered: root.configFile.reload()
  }

  Timer {
    id: cornerMenuAutohide
    interval: 3000
    onTriggered: {
      if (root.cornerMenuOpen && !root.cornerMenuPointerInside) root.cornerMenuOpen = false
    }
  }

  Timer {
    interval: 100
    repeat: true
    running: root.cornerMenuOpen && !!root.cornerMenuFocusAddress
    onTriggered: {
      if (root.cornerMenuPointerInside) return
      var focused = root.currentTarget()
      var address = focused && focused.address ? String(focused.address) : ""
      if (address && address !== root.cornerMenuFocusAddress) {
        root.cornerMenuOpen = false
        root.cornerMenuFocusAddress = ""
        root.cornerMenuPointerInside = false
        cornerMenuAutohide.stop()
      }
    }
  }

  Variants {
    model: Quickshell.screens

    Scope {
      id: screenScope
      required property var modelData

      Instantiator {
        model: root.cornerKeys

        delegate: Scope {
          id: cornerScope
          required property var modelData

          readonly property string key: cornerScope.modelData
          readonly property bool enabled: !!root.entryFor(cornerScope.key)

          Timer {
            id: armTimer
            interval: root.triggerDelayMs
            onTriggered: root.trigger(cornerScope.key)
          }

          PanelWindow {
            id: cornerSensorWindow
            screen: screenScope.modelData
            visible: cornerScope.enabled
            color: "transparent"
            implicitWidth: root.cornerSize
            implicitHeight: root.cornerSize
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // Keep the tiny trigger surfaces above open popup surfaces so a
            // card cannot consume pointer entry before the corner sees it.
            WlrLayershell.aboveWindows: true
            WlrLayershell.namespace: "omarchy-hot-corner"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Component.onCompleted: root.registerHotzone(cornerSensorWindow)
            Component.onDestruction: root.unregisterHotzone(cornerSensorWindow)

            anchors {
              left: cornerScope.key.indexOf("left") >= 0
              right: cornerScope.key.indexOf("right") >= 0
              top: cornerScope.key.indexOf("top") >= 0
              bottom: cornerScope.key.indexOf("bottom") >= 0
            }

            Item {
              anchors.fill: parent

              HoverHandler {
                // Arm on arrival, disarm on leave: one fire per visit to the
                // corner, and nothing at all while the pointer is elsewhere.
                onHoveredChanged: {
                  if (cornerScope.key === "top-right") {
                    root.cornerMenuPointerInside = hovered
                    if (hovered) cornerMenuAutohide.stop()
                    else if (root.cornerMenuOpen) cornerMenuAutohide.restart()
                  }
                  if (hovered) armTimer.restart()
                  else armTimer.stop()
                }
              }
            }
          }
        }
      }

      PanelWindow {
        id: cornerMenuWindow
        screen: screenScope.modelData
        visible: root.cornerMenuOpen
          && Hyprland.monitorFor(screenScope.modelData) === Hyprland.focusedMonitor
        color: "transparent"
        implicitWidth: Style.space(72)
        implicitHeight: Style.space(220)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.aboveWindows: true
        WlrLayershell.namespace: "column-control-corner-menu"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; right: true }
        margins { top: root.cornerSize + Style.space(10); right: Style.space(10) }

        Rectangle {
          id: cornerMenuCard
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Commons.Color.popups.background
          border.width: 1
          border.color: Commons.Color.popups.border

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            HoverHandler {
              onHoveredChanged: {
                root.cornerMenuPointerInside = hovered
                if (hovered) cornerMenuAutohide.stop()
                else if (root.cornerMenuOpen)
                  cornerMenuAutohide.restart()
              }
            }

            Ui.Button {
              id: appsButton
              width: parent.width
              height: Style.space(44)
              scale: 0.7
              iconText: "󰀻"
              iconSize: Style.space(26)
              foreground: Commons.Color.popups.text
              bordered: true
              onClicked: root.runCornerMenuAction("apps")

              HoverHandler { id: appsHover }
            }
            Ui.Button {
              id: moreButton
              width: parent.width
              height: Style.space(44)
              scale: 0.7
              iconText: "󰒓"
              iconSize: Style.space(26)
              foreground: Commons.Color.popups.text
              bordered: true
              onClicked: root.runCornerMenuAction("more")

              HoverHandler { id: moreHover }
            }
            Ui.Button {
              id: qnoteButton
              width: parent.width
              height: Style.space(44)
              scale: 0.7
              iconText: "󰈙"
              iconSize: Style.space(26)
              foreground: Commons.Color.popups.text
              bordered: true
              onClicked: root.runCornerMenuAction("qnote")

              HoverHandler { id: qnoteHover }
            }
            Ui.Button {
              id: powerButton
              width: parent.width
              height: Style.space(44)
              scale: 0.7
              iconText: ""
              iconSize: Style.space(26)
              foreground: Commons.Color.popups.text
              bordered: true
              onClicked: root.runCornerMenuAction("power")

              HoverHandler { id: powerHover }
            }
          }
        }

        PopupWindow {
          id: appsTooltipWindow
          visible: cornerMenuWindow.visible && appsHover.hovered
          color: "transparent"
          implicitWidth: appsTooltipBubble.implicitWidth
          implicitHeight: appsTooltipBubble.implicitHeight
          anchor {
            id: appsTooltipAnchor
            window: cornerMenuWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
              var point = cornerMenuWindow.contentItem.mapFromItem(appsButton, 0, 0)
              appsTooltipAnchor.rect.x = Math.round(point.x - appsTooltipWindow.implicitWidth - Style.space(12))
              appsTooltipAnchor.rect.y = Math.round(point.y + (appsButton.height - appsTooltipWindow.implicitHeight) / 2)
            }
          }
          Ui.BorderSurface {
            id: appsTooltipBubble
            anchors.fill: parent
            implicitWidth: appsTooltipLabel.implicitWidth + Style.space(16)
            implicitHeight: appsTooltipLabel.implicitHeight + Style.space(10)
            color: Commons.Color.tooltip.background
            borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Commons.Color.tooltip.border,
              Commons.Color.tooltip.border, Style.normalBorderWidth)
            radius: Style.cornerRadius
            Text {
              id: appsTooltipLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "App menu"
              color: Commons.Color.tooltip.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PopupWindow {
          id: moreTooltipWindow
          visible: cornerMenuWindow.visible && moreHover.hovered
          color: "transparent"
          implicitWidth: moreTooltipBubble.implicitWidth
          implicitHeight: moreTooltipBubble.implicitHeight
          anchor {
            id: moreTooltipAnchor
            window: cornerMenuWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
              var point = cornerMenuWindow.contentItem.mapFromItem(moreButton, 0, 0)
              moreTooltipAnchor.rect.x = Math.round(point.x - moreTooltipWindow.implicitWidth - Style.space(12))
              moreTooltipAnchor.rect.y = Math.round(point.y + (moreButton.height - moreTooltipWindow.implicitHeight) / 2)
            }
          }
          Ui.BorderSurface {
            id: moreTooltipBubble
            anchors.fill: parent
            implicitWidth: moreTooltipLabel.implicitWidth + Style.space(16)
            implicitHeight: moreTooltipLabel.implicitHeight + Style.space(10)
            color: Commons.Color.tooltip.background
            borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Commons.Color.tooltip.border,
              Commons.Color.tooltip.border, Style.normalBorderWidth)
            radius: Style.cornerRadius
            Text {
              id: moreTooltipLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "More options"
              color: Commons.Color.tooltip.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PopupWindow {
          id: qnoteTooltipWindow
          visible: cornerMenuWindow.visible && qnoteHover.hovered
          color: "transparent"
          implicitWidth: qnoteTooltipBubble.implicitWidth
          implicitHeight: qnoteTooltipBubble.implicitHeight
          anchor {
            id: qnoteTooltipAnchor
            window: cornerMenuWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
              var point = cornerMenuWindow.contentItem.mapFromItem(qnoteButton, 0, 0)
              qnoteTooltipAnchor.rect.x = Math.round(point.x - qnoteTooltipWindow.implicitWidth - Style.space(12))
              qnoteTooltipAnchor.rect.y = Math.round(point.y + (qnoteButton.height - qnoteTooltipWindow.implicitHeight) / 2)
            }
          }
          Ui.BorderSurface {
            id: qnoteTooltipBubble
            anchors.fill: parent
            implicitWidth: qnoteTooltipLabel.implicitWidth + Style.space(16)
            implicitHeight: qnoteTooltipLabel.implicitHeight + Style.space(10)
            color: Commons.Color.tooltip.background
            borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Commons.Color.tooltip.border,
              Commons.Color.tooltip.border, Style.normalBorderWidth)
            radius: Style.cornerRadius
            Text {
              id: qnoteTooltipLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "QNote"
              color: Commons.Color.tooltip.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PopupWindow {
          id: powerTooltipWindow
          visible: cornerMenuWindow.visible && powerHover.hovered
          color: "transparent"
          implicitWidth: powerTooltipBubble.implicitWidth
          implicitHeight: powerTooltipBubble.implicitHeight
          anchor {
            id: powerTooltipAnchor
            window: cornerMenuWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
              var point = cornerMenuWindow.contentItem.mapFromItem(powerButton, 0, 0)
              powerTooltipAnchor.rect.x = Math.round(point.x - powerTooltipWindow.implicitWidth - Style.space(12))
              powerTooltipAnchor.rect.y = Math.round(point.y + (powerButton.height - powerTooltipWindow.implicitHeight) / 2)
            }
          }
          Ui.BorderSurface {
            id: powerTooltipBubble
            anchors.fill: parent
            implicitWidth: powerTooltipLabel.implicitWidth + Style.space(16)
            implicitHeight: powerTooltipLabel.implicitHeight + Style.space(10)
            color: Commons.Color.tooltip.background
            borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Commons.Color.tooltip.border,
              Commons.Color.tooltip.border, Style.normalBorderWidth)
            radius: Style.cornerRadius
            Text {
              id: powerTooltipLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "Power / session"
              color: Commons.Color.tooltip.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }

      PanelWindow {
        id: bottomEdgeWindow
        screen: screenScope.modelData
        color: "transparent"
        implicitWidth: screenScope.modelData.width / 2
        implicitHeight: 1
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.aboveWindows: true
        WlrLayershell.namespace: "column-control-bottom-edge"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Component.onCompleted: root.registerHotzone(bottomEdgeWindow)
        Component.onDestruction: root.unregisterHotzone(bottomEdgeWindow)
        anchors { bottom: true; left: true }
        margins { left: screenScope.modelData.width / 4 }

        Item {
          anchors.fill: parent
          HoverHandler {
            onHoveredChanged: {
              if (hovered) bottomEdgeTimer.restart()
              else bottomEdgeTimer.stop()
            }
          }
        }

        Timer {
          id: bottomEdgeTimer
          interval: root.triggerDelayMs
          onTriggered: root.centerFocusedColumn()
        }
      }
    }
  }
}
