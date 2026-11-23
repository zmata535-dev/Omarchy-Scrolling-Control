import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "zm.column-control"

  property bool opened: false
  property bool expanded: false
  property bool pointerVisited: false
  property bool actionTriggered: false
  property int openRetryCount: 0
  property int startupRefreshCount: 0
  property int closeFocusCheckCount: 0
  property string targetAddress: ""
  property string closingTargetAddress: ""
  property int narrowPercent: 50
  property int normalPercent: 69
  property int widePercent: 92
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/column-width.json"
  readonly property string hotCornerConfigPath: Quickshell.env("HOME") + "/.config/omarchy/hot-corners.json"
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color iconForeground: Commons.Color.popups.text
  readonly property var hotCornerService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property bool canOpen: isNormalTarget(currentTarget(), Hyprland.focusedWorkspace)
  readonly property color indicatorForeground: canOpen
    ? (bar ? bar.barForeground : Commons.Color.bar.text)
    : Commons.Color.muted
  property int hotCornerSize: 6
  property int hotCornerDelayMs: 120
  property bool hotCornerConfigLoaded: false
  property var hotCorners: ({ "top-left": { action: "open-column-control" } })

  function clampPercent(value) { return Math.max(25, Math.min(100, Math.round(Number(value) || 50))) }
  function framedGlyphFor(percent) {
    if (percent >= 96) return "rect_fullscreen_framed.png"
    var presets = [30, 39, 50, 70, 90]
    var nearest = presets[0]
    for (var i = 1; i < presets.length; i++) {
      if (Math.abs(presets[i] - percent) < Math.abs(nearest - percent)) nearest = presets[i]
    }
    return "rect_" + nearest + "_framed.png"
  }
  function isFloatingWindow(target) {
    if (!target) return false
    var ipc = target.lastIpcObject
    var floating = ipc ? ipc.floating : target.floating
    return floating === true || floating === 1 || floating === "1" || floating === "true"
  }
  function hasFloatingState(target) {
    var ipc = target ? target.lastIpcObject : null
    var value = ipc ? ipc.floating : undefined
    return typeof value === "boolean" || value === 0 || value === 1
      || value === "0" || value === "1" || value === "true" || value === "false"
  }
  function isNormalTarget(target, workspace) {
    if (!target || !target.address || !workspace || !target.workspace
        || String(target.workspace.id) !== String(workspace.id)
        || !hasFloatingState(target)) return false
    return !isFloatingWindow(target)
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
  function isCurrentTargetNormal() {
    var active = currentTarget()
    return !!targetAddress && !!active && String(active.address) === targetAddress
      && isNormalTarget(active, Hyprland.focusedWorkspace)
  }
  function retryOpen() {
    if (openRetryCount >= 8) {
      close()
      return
    }
    openRetryCount++
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    openRetry.restart()
  }
  function open() {
    var target = currentTarget()
    var workspace = Hyprland.focusedWorkspace
    if (!target || !target.address || !workspace || !target.workspace || !hasFloatingState(target)) {
      retryOpen()
      return
    }
    if (!isNormalTarget(target, workspace)) {
      close()
      return
    }
    openRetryCount = 0
    openRetry.stop()
    targetAddress = target && target.address ? String(target.address) : ""
    pointerVisited = button.tooltipHovered
    expanded = false
    actionTriggered = false
    opened = true
  }
  function openMoreOptions() {
    var target = currentTarget()
    targetAddress = isNormalTarget(target, Hyprland.focusedWorkspace) ? String(target.address) : ""
    openRetry.stop()
    openRetryCount = 0
    pointerVisited = false
    actionTriggered = false
    expanded = true
    opened = true
  }
  function close() {
    openRetry.stop()
    openRetryCount = 0
    closeFocusCheck.stop()
    closeFocusCheckCount = 0
    closingTargetAddress = ""
    opened = false
    expanded = false
    pointerVisited = false
    actionTriggered = false
    targetAddress = ""
  }
  function toggle() { opened || openRetry.running ? close() : open() }

  function loadConfig(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      if (data && typeof data === "object") {
        if (Number.isFinite(Number(data.narrow))) narrowPercent = clampPercent(data.narrow)
        if (Number.isFinite(Number(data.normal))) normalPercent = clampPercent(data.normal)
        if (Number.isFinite(Number(data.wide))) widePercent = clampPercent(data.wide)
      }
    } catch (e) {
      console.warn("Column width settings could not be read:", e)
    }
  }
  function saveConfig() {
    configFile.setText(JSON.stringify({ narrow: narrowPercent, normal: normalPercent, wide: widePercent }, null, 2) + "\n")
  }
  function setPercent(kind, value) {
    var percent = clampPercent(value)
    if (kind === "narrow") narrowPercent = percent
    else if (kind === "normal") normalPercent = percent
    else widePercent = percent
    saveConfig()
  }
  function loadHotCornerConfig(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      if (!data || typeof data !== "object") return
      if (Number.isFinite(Number(data.size)) && Number(data.size) > 0)
        hotCornerSize = Math.max(1, Math.min(64, Math.round(Number(data.size))))
      if (Number.isFinite(Number(data.delayMs)) && Number(data.delayMs) >= 0)
        hotCornerDelayMs = Math.max(0, Math.min(5000, Math.round(Number(data.delayMs))))
      if (data.corners && typeof data.corners === "object") hotCorners = data.corners
    } catch (e) {
      console.warn("Hot corner settings could not be read:", e)
    }
  }
  function saveHotCornerConfig() {
    hotCornerFile.setText(JSON.stringify({
      size: hotCornerSize,
      delayMs: hotCornerDelayMs,
      corners: hotCorners
    }, null, 2) + "\n")
  }
  function hotCornerAction(key) {
    var entry = hotCorners ? hotCorners[key] : null
    if (typeof entry === "string") return entry
    return entry && typeof entry === "object" ? String(entry.action || "") : "disabled"
  }
  function hotCornerActionLabel(key) {
    var action = hotCornerAction(key)
    if (action === "open-column-control") return "Open Column Control"
    if (action === "open-column-control-menu") return "Open Column Control menu"
    if (action === "show-desktop") return "Show desktop"
    if (action === "focus-left") return "Focus Left"
    if (action === "focus-right") return "Focus Right"
    if (action === "center-focused") return "Center Focused"
    if (action === "close-focused") return "Close focused app"
    if (action === "command") return "Custom command"
    return "Disabled"
  }
  function cycleHotCornerAction(key) {
    var order = ["disabled", "open-column-control", "open-column-control-menu", "show-desktop", "focus-left", "focus-right", "center-focused", "close-focused"]
    var current = hotCornerAction(key)
    var next = order[(order.indexOf(current) + 1) % order.length]
    var updated = Object.assign({}, hotCorners || {})
    if (next === "disabled") delete updated[key]
    else updated[key] = { action: next }
    hotCorners = updated
    saveHotCornerConfig()
  }
  function setHotCornerSize(value) {
    hotCornerSize = Math.max(1, Math.min(64, Math.round(Number(value) || 1)))
    saveHotCornerConfig()
  }
  function setHotCornerDelay(value) {
    hotCornerDelayMs = Math.max(0, Math.min(5000, Math.round(Number(value) || 0)))
    saveHotCornerConfig()
  }
  function applyColumn(percent) {
    if (!isCurrentTargetNormal()) return
    actionTriggered = true
    var ratio = (clampPercent(percent) / 100).toFixed(2)
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.layout(\"colresize " + ratio + "\")"])
  }
  function applyFullscreen() {
    if (!isCurrentTargetNormal()) return
    actionTriggered = true
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"set\" })"])
  }
  function applyCenterFocused() {
    if (!isCurrentTargetNormal()) return
    actionTriggered = true
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.layout(\"center\")"])
  }
  function closeFocusedApp() {
    var target = currentTarget()
    if (!isNormalTarget(target, Hyprland.focusedWorkspace) || !target.wayland
        || typeof target.wayland.close !== "function") return
    actionTriggered = true
    closingTargetAddress = String(target.address)
    closeFocusCheckCount = 0
    target.wayland.close()
    closeFocusCheck.restart()
  }
  function checkFocusAfterClose() {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()

    var active = currentTarget()
    if (active && String(active.address) !== closingTargetAddress
        && isNormalTarget(active, Hyprland.focusedWorkspace)) {
      targetAddress = String(active.address)
      closingTargetAddress = ""
      closeFocusCheck.stop()
      return
    }

    var closingWindowStillOpen = false
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      if (String(toplevels[i].address) === closingTargetAddress) {
        closingWindowStillOpen = true
        break
      }
    }
    if (!closingWindowStillOpen) {
      closingTargetAddress = ""
      closeFocusCheck.stop()
      if (isNormalTarget(active, Hyprland.focusedWorkspace))
        targetAddress = String(active.address)
      else
        close()
      return
    }

    closeFocusCheckCount++
    if (closeFocusCheckCount >= 20) {
      closingTargetAddress = ""
      closeFocusCheck.stop()
    }
  }
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onFileChanged: reload()
  }

  FileView {
    id: hotCornerFile
    path: root.hotCornerConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.loadHotCornerConfig(text())
      root.hotCornerConfigLoaded = true
    }
    onLoadFailed: root.hotCornerConfigLoaded = true
    onFileChanged: reload()
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
  }

  Timer {
    id: startupRefresh
    interval: 150
    repeat: true
    running: !root.canOpen && root.startupRefreshCount < 40
    onTriggered: {
      if (root.canOpen) {
        stop()
        return
      }
      root.startupRefreshCount++
      Hyprland.refreshToplevels()
      Hyprland.refreshWorkspaces()
    }
  }

  Timer {
    interval: 150
    repeat: true
    running: root.opened
    onTriggered: {
      if (!root.actionTriggered && root.targetAddress && !root.isCurrentTargetNormal()) root.close()
    }
  }

  Timer {
    id: openRetry
    interval: 125
    repeat: false
    onTriggered: root.open()
  }

  Timer {
    id: closeFocusCheck
    interval: 100
    repeat: true
    onTriggered: root.checkFocusAfterClose()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: Image {
      width: 512
      height: 512
      source: Qt.resolvedUrl("assets/column_white.png")
      fillMode: Image.PreserveAspectFit
      smooth: true
      layer.enabled: true
      layer.effect: MultiEffect {
        colorization: 1.0
        colorizationColor: root.indicatorForeground
      }
    }
    interactive: root.canOpen
    dimmed: !root.canOpen
    active: root.opened
    onTooltipHoveredChanged: if (tooltipHovered) root.pointerVisited = true
    onPressed: root.toggle()
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.open() }
    function openMoreOptions(): void { root.openMoreOptions() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Ui.PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    triggerMode: "hover"
    centerOnBar: false
    padding: root.expanded ? Style.spacing.popupPadding : 0
    contentWidth: popup.fittedContentWidth(root.expanded ? Style.space(225) : Style.space(136))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)
    onContainsMouseChanged: if (containsMouse) root.pointerVisited = true

    Column {
      id: content
      width: parent.width
      spacing: Style.space(12)

      Rectangle {
        visible: !root.expanded
        width: popup.fittedContentWidth(Style.space(136))
        anchors.horizontalCenter: parent.horizontalCenter
        implicitHeight: compactActions.height + Style.space(6)
        radius: Style.cornerRadius
        color: Commons.Color.popups.background
        border.width: 1
        border.color: Commons.Color.popups.border

        Grid {
          id: compactActions
          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Style.space(3)
          }
          height: Style.space(99)
          columns: 3
          columnSpacing: Style.space(3)
          rowSpacing: Style.space(3)

          Repeater {
          model: [
            { label: "Narrow " + root.narrowPercent + "%", kind: "narrow", percent: root.narrowPercent, glyph: root.framedGlyphFor(root.narrowPercent) },
            { label: "Normal " + root.normalPercent + "%", kind: "normal", percent: root.normalPercent, glyph: root.framedGlyphFor(root.normalPercent) },
            { label: "Wide " + root.widePercent + "%", kind: "wide", percent: root.widePercent, glyph: root.framedGlyphFor(root.widePercent) },
            { label: "Full width", kind: "fullwidth", percent: 100, glyph: "arrow_horizontal_framed.png" },
            { label: "Fullscreen", kind: "fullscreen", fullscreen: true, glyph: "rect_fullscreen_framed.png" },
            { label: "Center focused", kind: "center", icon: "center" },
            { label: "Close app", kind: "close", icon: "close" }
          ]

          delegate: Rectangle {
            id: actionButton
            required property var modelData
            width: (parent.width - Style.space(3) * 2) / 3
            height: Style.space(31)
            scale: 0.7
            radius: Style.cornerRadius
            color: actionMouse.containsMouse ? Style.hoverFillFor(root.iconForeground, Commons.Color.accent) : "transparent"
            border.width: actionMouse.containsMouse ? 1 : 0
            border.color: Commons.Color.accent
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            Behavior on border.width { NumberAnimation { duration: Style.duration(120) } }

            Image {
              anchors.fill: parent
              visible: modelData.kind === "center"
              source: Qt.resolvedUrl("assets/column_control_frame.png")
              fillMode: Image.Stretch
              smooth: true
              layer.enabled: true
              layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: root.iconForeground
              }
            }

            Canvas {
              id: actionCanvas
              anchors.centerIn: parent
              width: modelData.kind === "center" ? parent.width : Math.min(parent.width, parent.height)
              height: modelData.kind === "center" ? parent.height : width
              visible: !modelData.glyph
              property var action: modelData
              onActionChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.scale(width / 24, height / 24)
                ctx.strokeStyle = root.iconForeground.toString()
                ctx.lineWidth = action.icon === "close" ? 1.1 : 1.7
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                if (action.icon !== "expand" && action.icon !== "close" && action.icon !== "center" && action.icon !== "apps") ctx.strokeRect(1.5, 1.5, 21, 21)

                if (action.icon === "fullscreen") {
                  ctx.beginPath()
                  ctx.moveTo(8, 1.5); ctx.lineTo(1.5, 1.5); ctx.lineTo(1.5, 8)
                  ctx.moveTo(16, 1.5); ctx.lineTo(22.5, 1.5); ctx.lineTo(22.5, 8)
                  ctx.moveTo(1.5, 16); ctx.lineTo(1.5, 22.5); ctx.lineTo(8, 22.5)
                  ctx.moveTo(22.5, 16); ctx.lineTo(22.5, 22.5); ctx.lineTo(16, 22.5)
                  ctx.stroke()
                } else if (action.icon === "expand") {
                  ctx.beginPath()
                  ctx.moveTo(10, 10); ctx.lineTo(3.5, 3.5)
                  ctx.moveTo(3.5, 3.5); ctx.lineTo(8, 3.5)
                  ctx.moveTo(3.5, 3.5); ctx.lineTo(3.5, 8)
                  ctx.moveTo(14, 10); ctx.lineTo(20.5, 3.5)
                  ctx.moveTo(20.5, 3.5); ctx.lineTo(16, 3.5)
                  ctx.moveTo(20.5, 3.5); ctx.lineTo(20.5, 8)
                  ctx.moveTo(10, 14); ctx.lineTo(3.5, 20.5)
                  ctx.moveTo(3.5, 20.5); ctx.lineTo(8, 20.5)
                  ctx.moveTo(3.5, 20.5); ctx.lineTo(3.5, 16)
                  ctx.moveTo(14, 14); ctx.lineTo(20.5, 20.5)
                  ctx.moveTo(20.5, 20.5); ctx.lineTo(16, 20.5)
                  ctx.moveTo(20.5, 20.5); ctx.lineTo(20.5, 16)
                  ctx.stroke()
                } else if (action.icon === "close") {
                  ctx.beginPath()
                  ctx.arc(12, 12, 9, 0, Math.PI * 2)
                  ctx.stroke()
                  ctx.beginPath()
                  ctx.moveTo(8, 8); ctx.lineTo(16, 16)
                  ctx.moveTo(16, 8); ctx.lineTo(8, 16)
                  ctx.stroke()
                } else if (action.icon === "center") {
                  ctx.lineWidth = 1.7
                  ctx.fillStyle = root.iconForeground.toString()
                  ctx.beginPath()
                  ctx.moveTo(4.2, 11.45); ctx.lineTo(9.55, 11.45)
                  ctx.lineTo(9.55, 10.35); ctx.lineTo(12, 12)
                  ctx.lineTo(9.55, 13.65); ctx.lineTo(9.55, 12.55)
                  ctx.lineTo(4.2, 12.55); ctx.closePath()
                  ctx.moveTo(19.8, 11.45); ctx.lineTo(14.45, 11.45)
                  ctx.lineTo(14.45, 10.35); ctx.lineTo(12, 12)
                  ctx.lineTo(14.45, 13.65); ctx.lineTo(14.45, 12.55)
                  ctx.lineTo(19.8, 12.55); ctx.closePath()
                  ctx.fill()
                } else if (action.icon === "apps") {
                  // The Apps glyph is rendered below.
                } else {
                  var ratio = action.kind === "fullwidth" ? 1 : Number(action.percent) / 100
                  if (action.kind === "fullwidth") {
                    ctx.strokeRect(2, 7, 20, 10)
                  } else {
                    var windowWidth = 18 * ratio
                    var x = 3 + (18 - windowWidth) / 2
                    ctx.strokeRect(x, 5, windowWidth, 9)
                    ctx.font = "bold 5px sans-serif"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    ctx.fillStyle = root.iconForeground.toString()
                    ctx.fillText(Math.round(Number(action.percent)) + "%", 12, 19.5)
                  }
                }
              }
            }

            Image {
              anchors.fill: parent
              visible: !!modelData.glyph
              source: modelData.glyph ? Qt.resolvedUrl("assets/" + modelData.glyph) : ""
              fillMode: Image.Stretch
              smooth: true
              layer.enabled: true
              layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: root.iconForeground
              }
            }

            Text {
              anchors.centerIn: parent
              visible: false
              text: "󰀻"
              color: root.iconForeground
              font.family: Style.font.family
              font.pixelSize: Style.space(28)
            }

            MouseArea {
              id: actionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData.kind === "close") root.closeFocusedApp()
                else if (modelData.fullscreen) root.applyFullscreen()
                else if (modelData.kind === "center") root.applyCenterFocused()
                else root.applyColumn(modelData.percent)
              }
            }

          }
        }

        }

      }

      Row {
        visible: root.expanded
        width: parent.width
        spacing: Style.space(8)

        Ui.Button {
          text: "← Back"
          foreground: root.foreground
          onClicked: root.expanded = false
        }
      }

      Text {
        visible: root.expanded
        text: "Hot corners"
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Row {
        visible: root.expanded
        enabled: root.hotCornerConfigLoaded
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: Style.space(112)
          height: Style.space(36)
          text: "Trigger size  " + root.hotCornerSize + " px"
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }

        Ui.PanelSlider {
          width: parent.width - Style.space(120)
          bar: root.bar
          minimum: 1
          maximum: 32
          step: 1
          integer: true
          value: root.hotCornerSize
          onMoved: function(nextValue) { root.setHotCornerSize(nextValue) }
        }
      }

      Row {
        visible: root.expanded
        enabled: root.hotCornerConfigLoaded
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: Style.space(112)
          height: Style.space(36)
          text: "Delay  " + root.hotCornerDelayMs + " ms"
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }

        Ui.PanelSlider {
          width: parent.width - Style.space(120)
          bar: root.bar
          minimum: 0
          maximum: 1000
          step: 10
          integer: true
          value: root.hotCornerDelayMs
          onMoved: function(nextValue) { root.setHotCornerDelay(nextValue) }
        }
      }

      Repeater {
        visible: root.expanded
        enabled: root.hotCornerConfigLoaded
        model: ["top-left", "top-right", "bottom-left", "bottom-right"]

        delegate: Row {
          required property string modelData
          visible: root.expanded
          width: content.width
          spacing: Style.space(8)

          Text {
            width: Style.space(112)
            height: Style.space(36)
            text: modelData.replace("-", " ").replace(/^./, function(c) { return c.toUpperCase() })
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            verticalAlignment: Text.AlignVCenter
          }

          Ui.Button {
            width: parent.width - Style.space(120)
            text: root.hotCornerActionLabel(modelData)
            foreground: root.foreground
            onClicked: root.cycleHotCornerAction(modelData)
          }
        }
      }

      Row {
        visible: root.expanded
        width: parent.width
        spacing: Style.space(8)

        Repeater {
          model: 3

          delegate: Rectangle {
            required property int index
            readonly property string key: ["narrow", "normal", "wide"][index]
            readonly property string label: ["Narrow", "Normal", "Wide"][index]
            readonly property int percent: index === 0 ? root.narrowPercent
              : (index === 1 ? root.normalPercent : root.widePercent)
            width: (content.width - Style.space(16)) / 3
            height: Style.space(112)
            radius: Style.space(8)
            color: Commons.Color.popups.background
            border.width: 1
            border.color: Commons.Color.popups.border

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(4)

              Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(38)
                height: Style.space(38)
                source: Qt.resolvedUrl("assets/" + root.framedGlyphFor(parent.parent.percent))
                fillMode: Image.PreserveAspectFit
                smooth: true
              }

              Ui.Button {
                width: parent.width
                text: parent.parent.label + "  " + parent.parent.percent + "%"
                foreground: root.foreground
                onClicked: root.applyColumn(parent.parent.percent)
              }

              Ui.PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 25
                maximum: 100
                step: 1
                integer: true
                value: parent.parent.percent
                onMoved: function(nextValue) { root.setPercent(parent.parent.key, nextValue) }
              }
            }
          }
        }
      }

    }
  }

  Timer {
    interval: 3000
    running: root.opened && !root.expanded && root.pointerVisited
      && !button.tooltipHovered && !popup.containsMouse
    onTriggered: {
      if (root.opened && !root.expanded && root.pointerVisited
          && !button.tooltipHovered && !popup.containsMouse) root.close()
    }
  }

  Timer {
    interval: 100
    repeat: true
    running: root.opened && !!root.targetAddress
    onTriggered: {
      if (root.targetAddress && !root.isCurrentTargetNormal()) root.close()
    }
  }
}
