import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TasksModel.js" as TasksModel

// Popup for the tasks pill: header + stats, an add/edit row (text + priority)
// with inline "@today"/"@tomorrow"/"@YYYY-MM-DD" due-date shorthand, a
// Today/Inbox/All tab switcher, and the task list itself. Marking a task
// done removes it from view immediately — it stays in tasks.md, just
// filtered out by the current view — so there's no separate "clear
// completed" step to remember.
Panel {
  id: root
  moduleName: "gordeev.tasks"
  ipcTarget: "gordeev.tasks"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var tasks: []

  // Persists across opens/closes on this instance (not reset in open()) so
  // switching to Inbox and reopening the panel later doesn't silently bounce
  // back to All.
  property string activeView: "all"  // "today" | "inbox" | "all"
  property bool helpVisible: false
  property string editingTaskId: ""
  property string priorityBeforeEdit: "medium"
  property string pendingDeleteId: ""

  readonly property var openTasksList: TasksModel.openTasks(root.tasks)
  readonly property var viewTasks: TasksModel.tasksForView(root.tasks, root.activeView, TasksModel.today())
  readonly property int doneTodayCount: TasksModel.doneToday(root.tasks, TasksModel.today())
  readonly property string pillLabel: root.openTasksList.length > 0 ? "󰄵 " + root.openTasksList.length : "󰄵"

  property string newTaskPriority: "medium"

  // Color.qml exposes only foreground/background/accent/urgent/muted — no
  // fourth distinct hue for a 4-tier priority scale. urgent/medium/low ride
  // existing tokens (urgent/accent/plain foreground); "high" is the one tier
  // with no token to borrow, so it's pinned to the same orange the Todoist
  // reference plugin uses for its p2, instead of inventing a new theme color.
  readonly property color highPriorityColor: "#f2b84b"

  function priorityColor(priority) {
    if (priority === "urgent") return Color.urgent
    if (priority === "high") return root.highPriorityColor
    if (priority === "medium") return Color.accent
    return root.bar.foreground
  }

  // Single cursor model over `viewTasks`, same contract as CursorSurface
  // expects everywhere else in the shell: one highlighted row, driven by
  // keyboard and mouse hover alike, never by a row reading its own
  // containsMouse. Starts inactive so opening the panel doesn't highlight a
  // row nobody pointed at yet — the first arrow press (or a hover) turns it on.
  property int selectedIndex: -1
  property bool cursorActive: false

  // Re-locates the cursor onto `taskId` inside the (possibly just resorted)
  // viewTasks — index alone can't survive a resort, since priority/due-date
  // changes reorder the list out from under a plain numeric position. Falls
  // back to clamping near the old index when the task left this view
  // entirely (done/deleted/edited out of it), same as onViewTasksChanged.
  function reselect(taskId) {
    for (var i = 0; i < root.viewTasks.length; i++) {
      if (root.viewTasks[i].id === taskId) {
        root.selectedIndex = i
        taskList.positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
    root.selectedIndex = Math.min(root.selectedIndex, root.viewTasks.length - 1)
  }

  function selectedTask() {
    return root.selectedIndex >= 0 && root.selectedIndex < root.viewTasks.length
      ? root.viewTasks[root.selectedIndex]
      : null
  }

  // First press just reveals the cursor at the current row (mirrors the
  // network/wifi panel's onMoveRequested); only a repeat press actually
  // walks the list. Keeps a stray arrow tap from jumping past the top row.
  function moveSelection(delta) {
    root.pendingDeleteId = ""
    if (root.viewTasks.length === 0) {
      root.cursorActive = false
      root.selectedIndex = -1
      return
    }
    if (!root.cursorActive) {
      root.cursorActive = true
      if (root.selectedIndex < 0) root.selectedIndex = 0
      if (delta >= 0) return
    }
    root.selectedIndex = Math.max(0, Math.min(root.viewTasks.length - 1, root.selectedIndex + delta))
    // ListView doesn't auto-scroll just because selectedIndex changed — the
    // highlight and the viewport are independent unless told otherwise, so
    // j/k past the visible rows would move the cursor off-screen silently.
    taskList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activateSelected() {
    var task = root.selectedTask()
    if (task) root.markDone(task.id)
  }

  // Arm/confirm: the first x (or click) marks a row for deletion, a second
  // one on the same row actually removes it. Anything that moves the cursor,
  // switches view, starts an edit, or closes the panel disarms it — no
  // separate confirm dialog needed for a popup this small.
  function requestDelete(id) {
    if (root.pendingDeleteId === id) {
      root.removeTask(id)
      root.pendingDeleteId = ""
    } else {
      root.pendingDeleteId = id
    }
  }

  function deleteSelected() {
    var task = root.selectedTask()
    if (task) root.requestDelete(task.id)
  }

  // 1/2/3/4 on the highlighted row, matching Todoist's own numbering
  // (1 = most urgent/red, 4 = default/no color) rather than our internal
  // low→urgent array order.
  function setSelectedPriority(priority) {
    var task = root.selectedTask()
    if (!task) return
    root.pendingDeleteId = ""
    root.tasks = root.tasks.map(function(t) {
      return t.id === task.id ? Object.assign({}, t, { priority: priority }) : t
    })
    root.saveTasks()
    root.reselect(task.id)
  }

  // h/l (PanelKeyCatcher's dx) steps the highlighted row by one tier instead
  // of jumping straight there — the relative complement to the 1-4 hotkeys.
  // Clamped, not wrapped: stepping past Urgent or below Low just stops.
  function stepSelectedPriority(delta) {
    var task = root.selectedTask()
    if (!task) return
    var nextRank = Math.max(0, Math.min(
      TasksModel.PRIORITIES.length - 1,
      TasksModel.priorityRank(task.priority) + delta
    ))
    root.setSelectedPriority(TasksModel.PRIORITIES[nextRank])
  }

  // A markDone/removeTask drops a row out of `viewTasks` immediately, so the
  // cursor needs to follow rather than point at whatever slid into its old
  // index — or at nothing once the list empties.
  onViewTasksChanged: {
    if (root.viewTasks.length === 0) {
      root.selectedIndex = -1
      root.cursorActive = false
    } else if (root.selectedIndex >= root.viewTasks.length) {
      root.selectedIndex = root.viewTasks.length - 1
    }
  }

  function setView(view) {
    root.pendingDeleteId = ""
    root.activeView = view
    root.selectedIndex = root.viewTasks.length > 0 ? 0 : -1
    root.cursorActive = false
  }

  // Caps the popup's growth once the list gets long — beyond this the list
  // scrolls in place instead of pushing the panel past the screen edge.
  readonly property int maxListHeight: Style.space(260)

  // Reload from disk and focus the input every time the panel opens, so a
  // task added from another monitor's bar (or hand-edited in the file)
  // shows up without a restart.
  function open() {
    root.controller.show()
    tasksFile.reload()
    root.cursorActive = false
    root.selectedIndex = root.viewTasks.length > 0 ? 0 : -1
    root.helpVisible = false
    root.pendingDeleteId = ""
    root.cancelEdit()
    Qt.callLater(function() { newTaskField.forceActiveFocus() })
  }

  function close() {
    root.controller.hide()
    root.helpVisible = false
    root.pendingDeleteId = ""
    root.cancelEdit()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function loadTasks(raw) {
    root.tasks = TasksModel.parseTasks(raw)
  }

  function saveTasks() {
    tasksFile.setText(TasksModel.serializeTasks(root.tasks))
  }

  // One field, one parser, two destinations: adds when nothing is being
  // edited, otherwise updates the task `editingTaskId` points at. The
  // "@today"/"@tomorrow"/"@YYYY-MM-DD" shorthand is stripped from the text
  // and becomes the due date either way.
  function commitTaskField() {
    var raw = newTaskField.text.trim()
    if (raw === "") return
    var parsed = TasksModel.parseDueToken(raw, TasksModel.today())
    if (parsed.text === "") return

    if (root.editingTaskId !== "") {
      var editedId = root.editingTaskId
      root.updateTaskText(editedId, parsed.text, parsed.dueDate)
      root.reselect(editedId)
    } else {
      // "!1".."!4" in the text wins over the priority picker when present,
      // so a keyboard-only "!1 Buy milk @tomorrow" doesn't need a mouse
      // click on the picker first.
      var withPriority = TasksModel.parsePriorityToken(parsed.text)
      var priority = withPriority.priority || root.newTaskPriority
      root.tasks = root.tasks.concat([TasksModel.newTask(withPriority.text, priority, parsed.dueDate)])
      root.saveTasks()
    }
    root.cancelEdit()
  }

  function updateTaskText(id, text, dueDate) {
    var priority = root.newTaskPriority
    root.tasks = root.tasks.map(function(t) {
      return t.id === id ? Object.assign({}, t, { text: text, dueDate: dueDate, priority: priority }) : t
    })
    root.saveTasks()
  }

  function markDone(id) {
    var closedOn = TasksModel.today()
    root.tasks = root.tasks.map(function(t) {
      return t.id === id ? Object.assign({}, t, { done: true, completedAt: closedOn }) : t
    })
    root.saveTasks()
  }

  function removeTask(id) {
    root.tasks = root.tasks.filter(function(t) { return t.id !== id })
    root.saveTasks()
  }

  function startEditSelected() {
    var task = root.selectedTask()
    if (!task) return
    root.pendingDeleteId = ""
    root.editingTaskId = task.id
    root.priorityBeforeEdit = root.newTaskPriority
    root.newTaskPriority = task.priority
    newTaskField.text = TasksModel.toEditText(task)
    newTaskField.forceActiveFocus()
  }

  function cancelEdit() {
    if (root.editingTaskId !== "") root.newTaskPriority = root.priorityBeforeEdit
    root.editingTaskId = ""
    newTaskField.text = ""
  }

  // Storage lives inside the Obsidian vault as a plain markdown checklist
  // (Tasks-plugin syntax, see TasksModel.js) — not the usual ~/.local/state
  // — by request, so the exact same file is both this panel's backing store
  // and a normal, browsable/editable note in Obsidian.
  FileView {
    id: tasksFile
    path: Quickshell.env("HOME") + "/Documents/obsidian-vault/Tasks/tasks.md"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadTasks(text())
    onLoadFailed: root.loadTasks("")
    onFileChanged: reload()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: newTaskField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The text field owns keys while it has focus (typing "j"/"k"/"h"/"l"/
      // "t"/"e"/etc. must land in the task text, not steer the cursor).
      blocked: newTaskField.activeFocus

      // Escape backs out one layer at a time: help, then an armed delete,
      // then the panel itself. Editing is cancelled from the text field's
      // own Escape handler below, since blocked suppresses this handler
      // entirely while that field has focus.
      onCloseRequested: {
        if (root.helpVisible) { root.helpVisible = false; return }
        if (root.pendingDeleteId !== "") { root.pendingDeleteId = ""; return }
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
        if (dx !== 0) root.stepSelectedPriority(dx)
      }
      onActivateRequested: root.activateSelected()
      onDeleteRequested: root.deleteSelected()
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.setView("today")
        else if (t === "i" || t === "I") root.setView("inbox")
        else if (t === "a" || t === "A") root.setView("all")
        else if (t === "e" || t === "E") root.startEditSelected()
        else if (t === "?") root.helpVisible = !root.helpVisible
        else if (t === "1") root.setSelectedPriority("urgent")
        else if (t === "2") root.setSelectedPriority("high")
        else if (t === "3") root.setSelectedPriority("medium")
        else if (t === "4") root.setSelectedPriority("low")
        // L/H: uppercase only. PanelKeyCatcher intercepts lowercase l/h
        // unconditionally (Keys.onPressed checks event.text === "l"/"h"
        // itself, before this signal even fires) — there's no dx/dy path
        // around that, so lower l/h can never reach onTextKey at all, unlike
        // every other letter here. m/u have no such collision, so both
        // cases work. None of these four touch the highlighted row — they
        // arm the priority chip for the *next* task you type, same as
        // clicking one.
        else if (t === "L") root.newTaskPriority = "low"
        else if (t === "m" || t === "M") root.newTaskPriority = "medium"
        else if (t === "H") root.newTaskPriority = "high"
        else if (t === "u" || t === "U") root.newTaskPriority = "urgent"
        // "dd": PanelKeyCatcher hardwires x/X to deleteRequested already;
        // 'd' isn't claimed anywhere, so it rides the same arm/confirm
        // state — d then d (or x then d, or d then x) both confirm.
        else if (t === "d" || t === "D") root.deleteSelected()
        // Back to typing after L/M/H/U (or any other list-nav key) — those
        // never touch focus themselves, so without this there's no way back
        // into the field short of a mouse click.
        else if (t === "n" || t === "N") {
          root.pendingDeleteId = ""
          newTaskField.forceActiveFocus()
        }
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: "󰄵"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
          }

          Column {
            spacing: Style.space(2)

            Text {
              text: "Tasks"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: "Open " + root.openTasksList.length + " · Done today " + root.doneTodayCount
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: newTaskField
            width: parent.width
            placeholderText: root.editingTaskId !== "" ? "Edit task…" : "New task… (@today/@tomorrow/@date, !1-!4 priority)"
            foreground: root.bar.foreground
            accent: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitTaskField()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                // Explicit handoff rather than relying on the FocusScope
                // fallback — same pattern the wifi panel uses when its
                // inline password prompt closes (network plugin's Panel.qml).
                if (root.editingTaskId !== "") root.cancelEdit()
                focus = false
                Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
                event.accepted = true
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            // Hand-rolled instead of the shared ButtonGroup: that component
            // tints every chip the same foreground/accent pair, no per-option
            // color — and priority is exactly the case where each option
            // needs its own color (same palette as the row's priority dot).
            Row {
              spacing: Style.space(8)

              Repeater {
                model: TasksModel.PRIORITIES

                delegate: Rectangle {
                  id: chip
                  required property string modelData
                  readonly property bool isSelected: root.newTaskPriority === modelData
                  readonly property color tint: root.priorityColor(modelData)

                  width: chipLabel.implicitWidth + Style.space(16)
                  height: chipLabel.implicitHeight + Style.space(8)
                  radius: Style.cornerRadius
                  color: isSelected ? Qt.rgba(tint.r, tint.g, tint.b, 0.18) : "transparent"
                  border.width: Style.normalBorderWidth
                  border.color: tint

                  Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: TasksModel.priorityLabel(chip.modelData)
                    color: chip.tint
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: chip.isSelected
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.newTaskPriority = chip.modelData
                  }
                }
              }
            }

            Text {
              visible: root.editingTaskId !== ""
              anchors.verticalCenter: parent.verticalCenter
              text: "editing — Esc to cancel"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Row {
          width: parent.width
          spacing: Style.space(10)

          ButtonGroup {
            options: [
              { value: "today", label: "Today" },
              { value: "inbox", label: "Inbox" },
              { value: "all", label: "All" }
            ]
            value: root.activeView
            foreground: root.bar.foreground
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function(v) { root.setView(v) }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "? — help"
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.italic: true
          }
        }

        ListView {
          id: taskList
          width: parent.width
          height: Math.min(contentHeight, root.maxListHeight)
          visible: root.viewTasks.length > 0
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.viewTasks
          // Overdue/Today only makes sense to split visually on the Today
          // tab — Inbox/All fall back to a flat list (empty section.property
          // disables grouping outright).
          section.property: root.activeView === "today" ? "section" : ""
          section.criteria: ViewSection.FullString

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          section.delegate: Text {
            text: section
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
          }

          delegate: TaskRow {
            required property var modelData
            required property int index
            width: taskList.width
            task: modelData
            rowIndex: index
          }
        }

        Text {
          visible: root.viewTasks.length === 0
          width: parent.width
          text: root.activeView === "today" ? "Nothing due today."
              : root.activeView === "inbox" ? "Inbox is empty."
              : "No tasks — add one above."
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
          wrapMode: Text.WordWrap
        }
      }

      // Full-panel overlay rather than a separate popup window, for the same
      // reason InlineTip below is hand-rolled: guaranteed to render the same
      // way everywhere without extra Overlay/Window plumbing.
      Item {
        id: helpOverlay
        visible: root.helpVisible
        anchors.fill: parent
        z: 10

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Color.tooltip.background
          opacity: 0.98
          border.width: Style.normalBorderWidth
          border.color: Color.tooltip.border
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: "Keyboard shortcuts"
            font.bold: true
            font.pixelSize: Style.font.title
            color: Color.tooltip.text
            font.family: root.bar.fontFamily
          }

          Repeater {
            model: [
              "↑↓ / j k — move",
              "Space / Enter — mark done",
              "x x / d d — delete (press again to confirm)",
              "e — edit selected",
              "1 2 3 4 — set priority of selected task",
              "h / l — step selected task's priority",
              "L M H U — priority for the next new task",
              "n — jump to the text field to type",
              "!1-!4 in new task text — same, while typing",
              "t / i / a — Today / Inbox / All",
              "Esc — back / close",
              "? — toggle this help"
            ]

            delegate: Text {
              required property string modelData
              text: modelData
              color: Color.tooltip.text
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.helpVisible = false
        }
      }
    }
  }

  // Hand-rolled hover label instead of PanelToolTip/QQC2 Popup — not because
  // Popup is broken here (it isn't; a stale ~/.cache/quickshell/qmlcache
  // entry was the actual cause of an earlier "nothing renders" scare), but
  // because a plain Item needs no Overlay/Window plumbing to show up, so
  // it's the simpler thing that's guaranteed to work the same way anywhere
  // in this panel. Costs one thing: it can clip against the ListView's own
  // `clip: true` for a row right at the viewport edge — acceptable here.
  component InlineTip: Rectangle {
    id: tip
    property string label: ""

    anchors.left: parent.left
    anchors.bottom: parent.top
    anchors.bottomMargin: Style.space(4)
    z: 5
    radius: Style.cornerRadius
    color: Color.tooltip.background
    border.width: Style.normalBorderWidth
    border.color: Color.tooltip.border
    width: tipLabel.implicitWidth + Style.spacing.controlPaddingX * 2
    height: tipLabel.implicitHeight + Style.spacing.controlPaddingY * 2

    Text {
      id: tipLabel
      anchors.centerIn: parent
      text: tip.label
      color: Color.tooltip.text
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // One row: checkbox · priority dot · text (+ due date) · delete. hasCursor
  // follows the single cursor model on root (selectedIndex/cursorActive) —
  // mouse hover just claims that cursor for this row rather than painting
  // its own highlight, per CursorSurface's contract.
  component TaskRow: CursorSurface {
    id: row
    required property var task
    required property int rowIndex
    readonly property bool overdue: TasksModel.isOverdue(row.task, TasksModel.today())
    readonly property bool armedForDelete: root.pendingDeleteId === row.task.id
    implicitHeight: rowContent.implicitHeight + Style.space(10)
    foreground: root.bar.foreground
    accent: Color.accent
    hasCursor: root.cursorActive && root.selectedIndex === row.rowIndex

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      // onPositionChanged, not onContainsMouseChanged: a priority change
      // resorts the list, so rows shift under a pointer that never actually
      // moved — Qt Quick still re-evaluates containsMouse on that relayout,
      // which would silently steal the cursor set a moment earlier by
      // reselect() and hand it to whatever row now sits under the stationary
      // pointer. positionChanged only fires on real motion.
      onPositionChanged: {
        root.cursorActive = true
        root.selectedIndex = row.rowIndex
        if (!row.armedForDelete) root.pendingDeleteId = ""
      }
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      implicitHeight: Math.max(checkbox.height, taskText.implicitHeight, deleteButton.height)

      Rectangle {
        id: checkbox
        width: Style.space(16)
        height: Style.space(16)
        radius: Style.cornerRadius
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"
        border.width: Style.normalBorderWidth
        border.color: row.foreground

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.markDone(row.task.id)
        }
      }

      Rectangle {
        id: priorityDot
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        anchors.left: checkbox.right
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        color: root.priorityColor(row.task.priority)

        InlineTip {
          visible: priorityMouse.containsMouse
          label: TasksModel.priorityLabel(row.task.priority) + " priority"
        }
        MouseArea {
          id: priorityMouse
          anchors.fill: parent
          hoverEnabled: true
        }
      }

      Text {
        id: taskText
        anchors.left: priorityDot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: deleteButton.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        // A ⚠ prefix marks overdue explicitly — color alone isn't enough,
        // since an urgent-priority task already renders in this same red.
        text: (row.overdue ? "⚠ " : "") + (row.task.dueDate ? row.task.text + "  ·  " + row.task.dueDate : row.task.text)
        color: row.overdue ? Color.urgent : root.priorityColor(row.task.priority)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      PanelActionButton {
        id: deleteButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "✕"
        tooltipText: row.armedForDelete ? "Click again to delete" : "Delete task"
        foreground: row.armedForDelete ? Color.urgent : row.foreground
        hoverColor: Color.urgent
        fontFamily: root.bar.fontFamily
        onClicked: root.requestDelete(row.task.id)
      }
    }
  }
}
