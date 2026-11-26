import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui

Item {
  id: root

  property bool opened: false
  property bool notesLoaded: false
  property var notes: []
  property int currentIndex: 0
  readonly property string storagePath: Quickshell.env("HOME") + "/.config/omarchy/column-control-notes.json"
  readonly property var currentNote: notes.length > 0
    ? notes[Math.max(0, Math.min(currentIndex, notes.length - 1))] : ({ title: "", text: "" })

  function open() {
    opened = true
    if (notesLoaded && notes.length === 0) addNote()
    Qt.callLater(function() { if (root.opened) noteEditor.forceActiveFocus() })
  }
  function close() { opened = false }
  function addNote() {
    notes = (notes || []).concat([{ title: "", text: "" }])
    currentIndex = notes.length - 1
    saveTimer.restart()
  }
  function removeNote(index) {
    var updated = (notes || []).slice()
    if (index < 0 || index >= updated.length) return
    updated.splice(index, 1)
    notes = updated
    currentIndex = Math.max(0, Math.min(index, notes.length - 1))
    if (notes.length === 0) addNote()
    else saveTimer.restart()
  }
  function updateNote(field, value) {
    if (notes.length === 0) return
    var updated = notes.slice()
    var note = Object.assign({}, updated[currentIndex])
    note[field] = value
    updated[currentIndex] = note
    notes = updated
    saveTimer.restart()
  }
  function syncFields() {
    titleField.text = root.currentNote.title
    noteEditor.text = root.currentNote.text
  }
  function save() {
    notesFile.setText(JSON.stringify(notes, null, 2) + "\n")
  }
  function load(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      notes = Array.isArray(parsed) ? parsed.map(function(note) {
        return { title: String(note.title || ""), text: String(note.text || "") }
      }) : []
    } catch (e) {
      console.warn("QNote could not read saved notes:", e)
      notes = []
    }
    currentIndex = Math.max(0, Math.min(currentIndex, notes.length - 1))
  }

  FileView {
    id: notesFile
    path: root.storagePath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.load(text())
      root.notesLoaded = true
      if (root.opened && root.notes.length === 0) root.addNote()
      Qt.callLater(root.syncFields)
    }
    onLoadFailed: {
      root.notes = []
      root.notesLoaded = true
      if (root.opened) root.addNote()
    }
  }

  Timer {
    id: saveTimer
    interval: 250
    onTriggered: root.save()
  }

  PanelWindow {
    id: panel
    screen: root.focusedScreen()
    visible: root.opened
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "column-control-qnote"
    mask: Region { Region { item: card } }

    Ui.BorderSurface {
      id: card
      width: Math.min(Style.space(430), panel.width - Style.space(40))
      height: Math.min(Style.space(560), panel.height - Style.space(40))
      anchors.centerIn: parent
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Style.normalBorderWidth)

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true

          Text {
            Layout.fillWidth: true
            text: "QNote"
            color: Commons.Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Ui.Button {
            text: "+"
            foreground: Commons.Color.menu.text
            onClicked: root.addNote()
          }
          Ui.Button {
            text: "×"
            foreground: Commons.Color.menu.text
            onClicked: root.close()
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)

          ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(34)
            orientation: ListView.Horizontal
            spacing: Style.space(4)
            clip: true
            model: root.notes.length

            delegate: Ui.Button {
              required property int index
              text: root.notes[index].title || ("Note " + (index + 1))
              foreground: Commons.Color.menu.text
              active: index === root.currentIndex
              onClicked: {
                root.currentIndex = index
                Qt.callLater(root.syncFields)
              }
            }
          }

          Ui.Button {
            text: "⌫"
            foreground: Commons.Color.menu.text
            enabled: root.notes.length > 0
            onClicked: root.removeNote(root.currentIndex)
          }
        }

        TextField {
          id: titleField
          Layout.fillWidth: true
          text: root.currentNote.title
          placeholderText: "Title"
          color: Commons.Color.menu.text
          selectedTextColor: Commons.Color.menu.selectedText
          selectionColor: Commons.Color.menu.selectedBackground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          background: Rectangle {
            color: "transparent"
            border.color: Commons.Color.popups.border
            radius: Style.cornerRadius
          }
          onTextEdited: root.updateNote("title", text)
        }

        TextArea {
          id: noteEditor
          Layout.fillWidth: true
          Layout.fillHeight: true
          text: root.currentNote.text
          placeholderText: "Write a note…"
          color: Commons.Color.menu.text
          selectedTextColor: Commons.Color.menu.selectedText
          selectionColor: Commons.Color.menu.selectedBackground
          wrapMode: TextEdit.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          background: Rectangle {
            color: "transparent"
            border.color: Commons.Color.popups.border
            radius: Style.cornerRadius
          }
          onTextChanged: if (activeFocus) root.updateNote("text", text)
          Keys.onEscapePressed: root.close()
        }

        Connections {
          target: root
          function onCurrentIndexChanged() { Qt.callLater(root.syncFields) }
        }
      }
    }
  }

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    if (monitor) {
      for (var i = 0; i < Quickshell.screens.length; i++) {
        if (Quickshell.screens[i].name === monitor.name) return Quickshell.screens[i]
      }
    }
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }
}
