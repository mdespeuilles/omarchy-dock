// Pure model helpers for the dock. Nothing here touches QML or the shell, so
// the merge rules can be read — and tested — on their own.

// Desktop ids reach us from three places that disagree about the suffix: the
// config file, DesktopEntries, and Hyprland app ids. Strip it once here.
function normalizeId(value) {
  var s = String(value || "").trim()
  if (s.length > 8 && s.slice(-8) === ".desktop") s = s.slice(0, -8)
  return s
}

// Grouping key. Hyprland reports "Brave-browser" where the desktop entry says
// "brave-browser", so the key is case-folded even though the id we display is
// not.
function matchKey(value) {
  return normalizeId(value).toLowerCase()
}

// The dock row: every pinned app in the user's order, then every running app
// that is not pinned, alphabetically. `running` is a map of matchKey ->
// { id, name, icon, toplevels }; `entryFor` resolves a pinned id to its
// desktop entry so a pinned app that is not running still has a name and icon.
function buildItems(pinnedIds, running, entryFor) {
  var items = []
  var seen = {}

  for (var i = 0; i < pinnedIds.length; i++) {
    var id = normalizeId(pinnedIds[i])
    if (id.length === 0) continue
    var key = id.toLowerCase()
    if (seen[key] === true) continue
    seen[key] = true

    var group = running[key] || null
    var entry = entryFor ? entryFor(id) : null
    items.push({
      id: id,
      key: key,
      pinned: true,
      name: (entry && entry.name) || (group && group.name) || id,
      icon: (entry && entry.icon) || (group && group.icon) || "",
      toplevels: group ? group.toplevels : []
    })
  }

  var keys = []
  for (var k in running)
    if (seen[k] !== true) keys.push(k)
  keys.sort()

  for (var j = 0; j < keys.length; j++) {
    var g = running[keys[j]]
    items.push({
      id: g.id,
      key: keys[j],
      pinned: false,
      name: g.name,
      icon: g.icon,
      toplevels: g.toplevels
    })
  }

  return items
}

// Index of the first unpinned item, so the dock can draw a separator there.
// -1 when the two groups do not both exist and no separator is wanted.
function separatorIndex(items) {
  for (var i = 0; i < items.length; i++)
    if (items[i].pinned !== true) return i > 0 ? i : -1
  return -1
}

// Left-clicking a running app walks its windows rather than always raising the
// same one: a second click on a two-window app should get you the other window,
// not a no-op on the one already focused.
function nextToplevel(toplevels, active) {
  if (!toplevels || toplevels.length === 0) return null
  if (toplevels.length === 1) return toplevels[0]
  var idx = -1
  for (var i = 0; i < toplevels.length; i++)
    if (toplevels[i] === active) { idx = i; break }
  if (idx === -1) return toplevels[0]
  return toplevels[(idx + 1) % toplevels.length]
}

function withPin(pinned, id) {
  var key = matchKey(id)
  var out = []
  for (var i = 0; i < pinned.length; i++) {
    if (matchKey(pinned[i]) === key) return pinned.slice()
    out.push(pinned[i])
  }
  out.push(normalizeId(id))
  return out
}

function withoutPin(pinned, id) {
  var key = matchKey(id)
  var out = []
  for (var i = 0; i < pinned.length; i++)
    if (matchKey(pinned[i]) !== key) out.push(pinned[i])
  return out
}

function isPinned(pinned, id) {
  var key = matchKey(id)
  for (var i = 0; i < pinned.length; i++)
    if (matchKey(pinned[i]) === key) return true
  return false
}

// The pinned ids in the order they are drawn, which is the order a drag
// manipulates. Rebuilding the list from what is on screen rather than indexing
// into the config keeps a duplicate or an unresolvable entry — both of which
// buildItems drops — from shifting the drop by one.
function pinnedOrder(items) {
  var out = []
  for (var i = 0; i < items.length; i++)
    if (items[i].pinned === true) out.push(items[i].id)
  return out
}

// Move one entry, clamping the destination rather than refusing it: the drag
// hands us wherever the icon was let go.
function moveEntry(list, from, to) {
  var out = list.slice()
  if (from < 0 || from >= out.length) return out
  var moved = out.splice(from, 1)[0]
  out.splice(Math.max(0, Math.min(out.length, to)), 0, moved)
  return out
}

// Parse ~/.config/omarchy/dock.json, tolerating an absent or malformed file:
// a dock that renders empty is recoverable, one that fails to load is not.
function parseConfig(raw, defaults) {
  var out = {
    pinned: defaults.pinned.slice(),
    iconSize: defaults.iconSize,
    showAppsButton: defaults.showAppsButton !== false
  }
  var data = null
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return out
  }
  if (!data || typeof data !== "object") return out

  if (Array.isArray(data.pinned)) {
    var pinned = []
    for (var i = 0; i < data.pinned.length; i++) {
      var id = normalizeId(data.pinned[i])
      if (id.length > 0) pinned.push(id)
    }
    out.pinned = pinned
  }

  var size = Number(data.iconSize)
  if (isFinite(size) && size >= 16 && size <= 96) out.iconSize = Math.round(size)

  if (typeof data.showAppsButton === "boolean") out.showAppsButton = data.showAppsButton

  return out
}
