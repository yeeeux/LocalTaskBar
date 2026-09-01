// Pure data helpers for the tasks plugin. No Quickshell/QML types here on
// purpose — this file loads standalone under Node for testing and keeps
// Panel.qml limited to wiring.
//
// Storage format: a markdown checklist compatible with the Obsidian Tasks
// plugin (https://publish.obsidian.md/tasks/), so the same file that backs
// this bar widget is a normal, readable note inside the Obsidian vault:
//
//   - [ ] Текст задачи ⏫ 📅 2026-09-03 ➕ 2026-08-27 [id:: 1787837510011]
//   - [x] Текст задачи 🔽 ➕ 2026-08-27 ✅ 2026-08-30 [id:: 1787836479530]
//
// The trailing `[id:: ...]` is our own bookkeeping (Dataview inline-field
// syntax, which Tasks tolerates) — task text alone isn't a stable key since
// two tasks can share the same wording.

// Real Obsidian Tasks plugin priority emoji (minus 🔺's Lowest sibling ⏬,
// which we don't expose — four tiers matches what Todoist shows as p1-p4).
// "urgent" is new; the bottom three keep their original names and emoji, so
// every task written before this tier existed still parses unchanged.
var PRIORITIES = ["low", "medium", "high", "urgent"]

var PRIORITY_EMOJI = { urgent: "🔺", high: "⏫", medium: "🔼", low: "🔽" }
var EMOJI_PRIORITY = { "🔺": "urgent", "⏫": "high", "🔼": "medium", "🔽": "low" }

var TASK_LINE_RE = /^-\s*\[([ xX])\]\s*(.*)$/
var ID_FIELD_RE = /\[id::\s*([^\]]+)\]/
var CREATED_FIELD_RE = /➕\s*(\d{4}-\d{2}-\d{2})/
var DONE_FIELD_RE = /✅\s*(\d{4}-\d{2}-\d{2})/
var DUE_FIELD_RE = /📅\s*(\d{4}-\d{2}-\d{2})/
var PRIORITY_FIELD_RE = /(🔺|⏫|🔼|🔽)/

// Quick-add/edit shorthand: a bare `@today`, `@tomorrow` or `@YYYY-MM-DD`
// token anywhere in the typed text sets the due date and is stripped from
// the stored text. Not a real parser like Todoist's — just enough to keep
// due-date entry inline instead of a separate date-picker widget.
var DUE_TOKEN_RE = /(^|\s)@(today|tomorrow|\d{4}-\d{2}-\d{2})(?=\s|$)/i

// Same idea as the due-date shorthand, for priority at creation time: typing
// "!1".."!4" anywhere sets priority without touching the mouse. Numbering
// matches Todoist's own (1 = most urgent, 4 = default) and the 1-4 list
// hotkeys, not our internal low→urgent array order.
var PRIORITY_TOKEN_RE = /(^|\s)!([1-4])(?=\s|$)/
var PRIORITY_TOKEN_MAP = { "1": "urgent", "2": "high", "3": "medium", "4": "low" }

function isValidTask(value) {
  return !!value && typeof value === "object" && typeof value.text === "string" && value.text.trim() !== ""
}

function normalizeTask(value) {
  return {
    id: String(value.id || ""),
    text: String(value.text),
    priority: PRIORITIES.indexOf(value.priority) !== -1 ? value.priority : "medium",
    done: !!value.done,
    createdAt: typeof value.createdAt === "string" ? value.createdAt : "",
    completedAt: typeof value.completedAt === "string" ? value.completedAt : "",
    dueDate: typeof value.dueDate === "string" ? value.dueDate : ""
  }
}

// Today's date as YYYY-MM-DD (local calendar day), the granularity Tasks'
// own date fields use.
function today() {
  var d = new Date()
  var month = String(d.getMonth() + 1).padStart(2, "0")
  var day = String(d.getDate()).padStart(2, "0")
  return d.getFullYear() + "-" + month + "-" + day
}

function addDays(dateStr, days) {
  var d = new Date(dateStr + "T00:00:00")
  d.setDate(d.getDate() + days)
  var month = String(d.getMonth() + 1).padStart(2, "0")
  var day = String(d.getDate()).padStart(2, "0")
  return d.getFullYear() + "-" + month + "-" + day
}

function parseTaskLine(line) {
  var m = TASK_LINE_RE.exec(line)
  if (!m) return null

  var done = m[1].toLowerCase() === "x"
  var rest = m[2]

  var idMatch = ID_FIELD_RE.exec(rest)
  rest = rest.replace(ID_FIELD_RE, "")

  var dueMatch = DUE_FIELD_RE.exec(rest)
  rest = rest.replace(DUE_FIELD_RE, "")

  var createdMatch = CREATED_FIELD_RE.exec(rest)
  rest = rest.replace(CREATED_FIELD_RE, "")

  var doneMatch = DONE_FIELD_RE.exec(rest)
  rest = rest.replace(DONE_FIELD_RE, "")

  var priorityMatch = PRIORITY_FIELD_RE.exec(rest)
  rest = rest.replace(PRIORITY_FIELD_RE, "")

  return normalizeTask({
    id: idMatch ? idMatch[1].trim() : "",
    text: rest.replace(/\s+/g, " ").trim(),
    priority: priorityMatch ? EMOJI_PRIORITY[priorityMatch[1]] : "medium",
    done: done,
    createdAt: createdMatch ? createdMatch[1] : "",
    completedAt: doneMatch ? doneMatch[1] : "",
    dueDate: dueMatch ? dueMatch[1] : ""
  })
}

// Parses the tasks.md checklist. Anything malformed — missing file, a
// non-checklist line, a line without usable text — is dropped rather than
// surfaced, so a hand-edited file degrades to "some tasks missing" instead
// of an empty panel. Section headings (`## Open`, `## Done`) and blank
// lines are simply not checklist lines, so they're skipped for free.
function parseTasks(raw) {
  var lines = String(raw || "").split("\n")
  var tasks = []
  for (var i = 0; i < lines.length; i++) {
    var task = parseTaskLine(lines[i])
    if (task && isValidTask(task)) tasks.push(task)
  }
  return tasks
}

function formatTaskLine(task) {
  var parts = ["- [" + (task.done ? "x" : " ") + "]", task.text, PRIORITY_EMOJI[task.priority] || PRIORITY_EMOJI.medium]
  if (task.dueDate) parts.push("📅 " + task.dueDate)
  if (task.createdAt) parts.push("➕ " + task.createdAt)
  if (task.done && task.completedAt) parts.push("✅ " + task.completedAt)
  parts.push("[id:: " + task.id + "]")
  return parts.join(" ")
}

// Serializes back to the checklist format, grouped under `## Open` / `## Done`
// so the file reads naturally as a note, not just a flat dump. Done tasks
// sort most-recently-closed first — that's the "history over time" view the
// vault is for. Open tasks keep their existing relative order (stable diffs
// beat a fancy sort nobody asked for).
function serializeTasks(tasks) {
  var open = (tasks || []).filter(function(t) { return !t.done })
  var done = (tasks || []).filter(function(t) { return t.done })
  done.sort(function(a, b) {
    if (a.completedAt === b.completedAt) return 0
    return a.completedAt > b.completedAt ? -1 : 1
  })

  var lines = ["# Tasks", "", "## Open", ""]
  if (open.length === 0) {
    lines.push("*(нет открытых задач)*")
  } else {
    open.forEach(function(t) { lines.push(formatTaskLine(t)) })
  }
  lines.push("", "## Done", "")
  if (done.length === 0) {
    lines.push("*(нет закрытых задач)*")
  } else {
    done.forEach(function(t) { lines.push(formatTaskLine(t)) })
  }
  lines.push("")
  return lines.join("\n")
}

function newTask(text, priority, dueDate) {
  return {
    id: String(Date.now()),
    text: text,
    priority: PRIORITIES.indexOf(priority) !== -1 ? priority : "medium",
    done: false,
    createdAt: today(),
    completedAt: "",
    dueDate: typeof dueDate === "string" ? dueDate : ""
  }
}

function priorityRank(priority) {
  return PRIORITIES.indexOf(priority)
}

function priorityLabel(priority) {
  if (priority === "urgent") return "Urgent"
  if (priority === "high") return "High"
  if (priority === "low") return "Low"
  return "Medium"
}

function byPriorityThenCreated(a, b) {
  var rankDiff = priorityRank(b.priority) - priorityRank(a.priority)
  if (rankDiff !== 0) return rankDiff
  return a.createdAt < b.createdAt ? -1 : (a.createdAt > b.createdAt ? 1 : 0)
}

function openTasks(tasks) {
  return (tasks || []).filter(function(t) { return !t.done })
}

function doneToday(tasks, todayStr) {
  return (tasks || []).filter(function(t) { return t.done && t.completedAt === todayStr }).length
}

function isOverdue(task, todayStr) {
  return !!task.dueDate && task.dueDate < todayStr && !task.done
}

function isDueToday(task, todayStr) {
  return task.dueDate === todayStr && !task.done
}

function withSection(label) {
  return function(t) { return Object.assign({}, t, { section: label }) }
}

// Pending tasks for one of the panel's three tabs, highest priority first
// (ties broken by creation order, so the list doesn't reshuffle itself while
// you're looking at it). "today" carries a `section` field per row
// ("Overdue" / "Today") for the list's section headers; the other two tabs
// return "" so no header renders. Returns fresh objects — never mutates
// `tasks` — so tagging rows with `section` can't corrupt what gets saved.
function tasksForView(tasks, view, todayStr) {
  var open = openTasks(tasks)

  if (view === "today") {
    var overdue = open.filter(function(t) { return isOverdue(t, todayStr) })
    var dueToday = open.filter(function(t) { return isDueToday(t, todayStr) })
    overdue.sort(function(a, b) { return a.dueDate < b.dueDate ? -1 : (a.dueDate > b.dueDate ? 1 : 0) })
    dueToday.sort(byPriorityThenCreated)
    return overdue.map(withSection("Overdue")).concat(dueToday.map(withSection("Today")))
  }

  if (view === "inbox") {
    return open.filter(function(t) { return !t.dueDate }).sort(byPriorityThenCreated).map(withSection(""))
  }

  return open.slice().sort(byPriorityThenCreated).map(withSection(""))
}

// Back-compat/simple case: every open task, sorted, no view filtering.
function visibleTasks(tasks) {
  return openTasks(tasks).sort(byPriorityThenCreated)
}

function parseDueToken(text, todayStr) {
  var m = DUE_TOKEN_RE.exec(text)
  if (!m) return { text: text.trim(), dueDate: "" }

  var token = m[2].toLowerCase()
  var due = token === "today" ? todayStr
    : token === "tomorrow" ? addDays(todayStr, 1)
    : token

  var cleaned = (text.slice(0, m.index) + text.slice(m.index + m[0].length)).replace(/\s+/g, " ").trim()
  return { text: cleaned, dueDate: due }
}

// Returns "" for priority when no token is present, so the caller can fall
// back to whatever the priority picker already has selected instead of
// forcing a default.
function parsePriorityToken(text) {
  var m = PRIORITY_TOKEN_RE.exec(text)
  if (!m) return { text: text.trim(), priority: "" }

  var cleaned = (text.slice(0, m.index) + text.slice(m.index + m[0].length)).replace(/\s+/g, " ").trim()
  return { text: cleaned, priority: PRIORITY_TOKEN_MAP[m[2]] }
}

// Reconstructs the quick-add shorthand for an existing task, so editing goes
// through parseDueToken on save too — one parser for both add and edit.
function toEditText(task) {
  return task.dueDate ? task.text + " @" + task.dueDate : task.text
}

if (typeof module !== "undefined") {
  module.exports = {
    PRIORITIES: PRIORITIES,
    today: today,
    parseTaskLine: parseTaskLine,
    formatTaskLine: formatTaskLine,
    parseTasks: parseTasks,
    serializeTasks: serializeTasks,
    newTask: newTask,
    priorityRank: priorityRank,
    priorityLabel: priorityLabel,
    visibleTasks: visibleTasks,
    openTasks: openTasks,
    doneToday: doneToday,
    isOverdue: isOverdue,
    isDueToday: isDueToday,
    tasksForView: tasksForView,
    parseDueToken: parseDueToken,
    parsePriorityToken: parsePriorityToken,
    toEditText: toEditText
  }
}
