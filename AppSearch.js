// Ranking and filtering for the app list the dock's panel shows.
//
// The shell has its own copy of this and the dock used to borrow it through
// `shell.appLibrary`. That capability is no longer reachable from a
// third-party plugin, so the dock carries the search it needs. See
// DockAppLibrary.qml in this directory for why.
//
// sortedEntries returns rows, not entries: the panel wants the DesktopEntry,
// but sorting wants a score and a fold-cased key computed once per entry
// rather than once per comparison.

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
}

// `keywords` is a QStringList across the QML boundary, and reading it on an
// entry that has none has been known to throw rather than return empty.
function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function")
      return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

// Everything a query may reasonably match, folded once.
function searchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id]
    .join(" ").toLowerCase()
}

// "LibreOffice Calc" and "org.gnome.Nautilus" both become word runs, so an
// acronym match ("loc", "gn") has something to build on.
function words(value) {
  var split = String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
  var out = []
  for (var i = 0; i < split.length; i++)
    if (split[i]) out.push(split[i])
  return out
}

function acronym(entry) {
  var parts = words([entry && entry.name, entry && entry.genericName,
    keywordText(entry), entry && entry.id].join(" "))
  var out = ""
  for (var i = 0; i < parts.length; i++) out += parts[i].charAt(0)
  return out
}

// Higher is better; below zero means the entry does not match at all. The
// tiers are ordered the way someone typing expects them: what the name starts
// with beats what it merely contains, and both beat a comment or a keyword.
function score(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = searchText(entry)

  var inName = name.indexOf(q)
  if (inName === 0) return 10000 - name.length
  var inId = id.indexOf(q)
  if (inId === 0) return 9500 - id.length
  if (inName > 0) return 8000 - inName * 10 - name.length
  if (inId > 0) return 7600 - inId * 10 - id.length

  var inHaystack = haystack.indexOf(q)
  if (inHaystack >= 0) return 6000 - inHaystack

  // An acronym is only a plausible reading of a short query: "gimp" should
  // not match an app whose initials happen to spell it.
  if (q.length <= 5) {
    var letters = acronym(entry)
    var inAcronym = letters.indexOf(q)
    if (inAcronym === 0) return 5000 - letters.length
    if (inAcronym > 0) return 4600 - inAcronym * 10 - letters.length
  }

  return -1
}

function sortedEntries(values, query, isHidden) {
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    if (isHidden && isHidden(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var value = score(entry, q)
    if (value < 0) continue
    rows.push({ entry: entry, score: value, key: name.toLowerCase() })
  }

  // Alphabetical is the resting state — with no query every score is 0, and
  // the panel opens as a stable A-Z grid rather than in DesktopEntries order.
  rows.sort(function (a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.key < b.key) return -1
    if (a.key > b.key) return 1
    return 0
  })

  return rows
}
