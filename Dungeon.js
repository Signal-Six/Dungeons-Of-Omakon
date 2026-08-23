// Dungeon.js — floor generation and first-person vista computation for
// Dungeons of Omakon. Pure logic, no QML/Qt imports; the module.exports
// guard at the bottom lets shell tests exercise it under Node, matching the
// EmojiSearch.js pattern from the first-party emojis plugin.
//
// Layout contract:
//   - A floor is ROWS x COLS = 6 x 7 nodes (42 max).
//   - Node[r][c] = { n,e,s,w: bool wall, feature: "none"|"up"|"down" }
//   - Player pos = { row, col, facing } with facing 0=N 1=E 2=S 3=W.
//   - vista() returns wall slices for the 2-deep first-person view.

var ROWS = 6
var COLS = 7

var DR = [-1, 0, 1, 0] // N E S W
var DC = [0, 1, 0, -1]

// Small seedable PRNG (mulberry32) so floors are reproducible/debuggable.
function rngFromSeed(seed) {
  var a = seed >>> 0
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0
    var t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function shuffle(arr, rand) {
  for (var i = arr.length - 1; i > 0; i--) {
    var j = Math.floor(rand() * (i + 1))
    var t = arr[i]; arr[i] = arr[j]; arr[j] = t
  }
  return arr
}

// Recursive-backtracker carve over the full 6x7 grid: every node is open,
// maze is perfect (connected, single path between any two nodes).
function generate(seed) {
  var rand = rngFromSeed(seed)
  var nodes = []
  for (var r = 0; r < ROWS; r++) {
    var row = []
    for (var c = 0; c < COLS; c++)
      row.push({ n: true, e: true, s: true, w: true, feature: "none" })
    nodes.push(row)
  }

  var visited = []
  for (r = 0; r < ROWS; r++) visited.push(new Array(COLS).fill(false))

  var stack = [{ r: Math.floor(rand() * ROWS), c: Math.floor(rand() * COLS) }]
  visited[stack[0].r][stack[0].c] = true

  while (stack.length > 0) {
    var cur = stack[stack.length - 1]
    var dirs = shuffle([0, 1, 2, 3].slice(), rand)
    var carved = false
    for (var i = 0; i < 4; i++) {
      var d = dirs[i]
      var nr = cur.r + DR[d], nc = cur.c + DC[d]
      if (nr < 0 || nr >= ROWS || nc < 0 || nc >= COLS) continue
      if (visited[nr][nc]) continue
      // Knock the wall between cur and the neighbor (both sides).
      var a = nodes[cur.r][cur.c], b = nodes[nr][nc]
      if (d === 0) { a.n = false; b.s = false }
      if (d === 1) { a.e = false; b.w = false }
      if (d === 2) { a.s = false; b.n = false }
      if (d === 3) { a.w = false; b.e = false }
      visited[nr][nc] = true
      stack.push({ r: nr, c: nc })
      carved = true
      break
    }
    if (!carved) stack.pop()
  }

  // Entrance: a fixed corner for now (Phase 4+ may randomize edges).
  var start = { r: ROWS - 1, c: 0 }
  nodes[start.r][start.c].feature = "up"

  // BFS from the entrance; the farthest cell becomes the downstairs.
  var dist = []
  for (r = 0; r < ROWS; r++) dist.push(new Array(COLS).fill(-1))
  dist[start.r][start.c] = 0
  var queue = [start]
  while (queue.length > 0) {
    var q = queue.shift()
    var node = nodes[q.r][q.c]
    var open = [node.n, node.e, node.s, node.w]
    for (var d2 = 0; d2 < 4; d2++) {
      if (open[d2]) continue
      var rr = q.r + DR[d2], cc = q.c + DC[d2]
      if (rr < 0 || rr >= ROWS || cc < 0 || cc >= COLS) continue
      if (dist[rr][cc] !== -1) continue
      dist[rr][cc] = dist[q.r][q.c] + 1
      queue.push({ r: rr, c: cc })
    }
  }
  var best = start, bestD = 0
  for (r = 0; r < ROWS; r++)
    for (c = 0; c < COLS; c++)
      if (dist[r][c] > bestD) { bestD = dist[r][c]; best = { r: r, c: c } }
  nodes[best.r][best.c].feature = "down"

  return {
    seed: seed,
    rows: ROWS,
    cols: COLS,
    nodes: nodes,
    start: { row: start.r, col: start.c, facing: 0 }
  }
}

// Wall flag for the node at (r,c) in direction d; out-of-bounds = wall.
function hasWall(floor, r, c, d) {
  if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return true
  var n = floor.nodes[r][c]
  return d === 0 ? n.n : d === 1 ? n.e : d === 2 ? n.s : n.w
}

// Compute the first-person view from pos within floor: VISTA_DEPTH cells
// ahead (index 0 = one step ahead). Each entry carries the middle-cell
// flags plus the off-axis side cells' end-wall and inner-partition flags
// (sorcery-style 3-column tile view):
//   left, right  — middle cell's side edges
//   end          — middle cell's far edge
//   sideL.side   — left cell's edge toward the middle (partition)
//   sideL.end    — left cell's far edge
//   sideL.far    — left cell's outer side edge (hardly needed ahead)
//   (same for sideR)
var VISTA_DEPTH = 4
function vista(floor, pos) {
  var out = []
  var row = pos.row, col = pos.col
  var aheadBlocked = false
  for (var depth = 1; depth <= VISTA_DEPTH; depth++) {
    if (aheadBlocked) {
      out.push({ left: true, right: true, end: true, feature: "none",
                 sideL: null, sideR: null, visible: false })
      continue
    }
    var nr = row + DR[pos.facing] * depth
    var nc = col + DC[pos.facing] * depth
    var leftD = (pos.facing + 3) % 4
    var rightD = (pos.facing + 1) % 4

    var inMaze = nr >= 0 && nr < ROWS && nc >= 0 && nc < COLS
    var slice = {
      left: hasWall(floor, nr, nc, leftD),
      right: hasWall(floor, nr, nc, rightD),
      end: hasWall(floor, nr, nc, pos.facing),
      feature: inMaze ? floor.nodes[nr][nc].feature : "none",
      visible: true,
      sideL: null,
      sideR: null
    }
    // Side cells at this depth (off-axis). Only filled when the middle
    // cell's side is open; the recess walls come from these.
    if (inMaze && !slice.left) {
      var lr = nr + DR[leftD], lc = nc + DC[leftD]
      slice.sideL = {
        side: hasWall(floor, lr, lc, rightD),   // partition back to middle
        end: hasWall(floor, lr, lc, pos.facing) // far face of the passage
      }
    }
    if (inMaze && !slice.right) {
      var rr = nr + DR[rightD], rc = nc + DC[rightD]
      slice.sideR = {
        side: hasWall(floor, rr, rc, leftD),
        end: hasWall(floor, rr, rc, pos.facing)
      }
    }
    out.push(slice)
    if (slice.end) aheadBlocked = true
    else { row = nr; col = nc }
  }
  return out
}

// Attempt to step in `dir` (0 forward, 1 right, 2 back, 3 left) relative to
// facing. Returns new pos (unchanged coordinates when walled).
function move(floor, pos, dir) {
  var d = (pos.facing + dir + 4) % 4
  if (hasWall(floor, pos.row, pos.col, d)) return pos
  return {
    row: pos.row + DR[d],
    col: pos.col + DC[d],
    facing: pos.facing
  }
}

function turn(pos, dir) { // -1 left, +1 right
  return { row: pos.row, col: pos.col, facing: (pos.facing + dir + 4) % 4 }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    ROWS: ROWS, COLS: COLS, DR: DR, DC: DC,
    rngFromSeed: rngFromSeed, generate: generate, VISTA_DEPTH: VISTA_DEPTH,
    hasWall: hasWall, vista: vista, move: move, turn: turn
  }
}
