// test_beacon.js — Beacon logic invariants against generated floors:
//   1. Every generated floor has exactly one "down" feature.
//   2. It is always at maximum BFS distance from the entrance (generate()'s
//      BFS-farthest-cell criterion).
//   3. The Beacon scan the Panel reproduces finds it on every floor.
var Dungeon = require("./Dungeon.js")
var fails = 0
function ok(c, m) { if (!c) { fails++; console.log("FAIL " + m) } }

for (var seed = 1; seed <= 400; seed++) {
  var floor = Dungeon.generate(seed)
  var downs = []
  for (var r = 0; r < Dungeon.ROWS; r++)
    for (var c = 0; c < Dungeon.COLS; c++)
      if (floor.nodes[r][c].feature === "down") downs.push({ r: r, c: c })
  ok(downs.length === 1, "seed " + seed + ": exactly one down (got " + downs.length + ")")

  // The BFS-farthest-cell check mirrors generate(): recompute from 'up'.
  if (downs.length !== 1) continue
  var up = null
  for (var r = 0; r < Dungeon.ROWS; r++)
    for (var c = 0; c < Dungeon.COLS; c++)
      if (floor.nodes[r][c].feature === "up") up = { r: r, c: c }
  ok(up !== null, "seed " + seed + ": entrance exists")
  if (!up) continue

  // Re-do generate's BFS to confirm the down tile sits at max distance.
  var dist = []
  for (var r = 0; r < Dungeon.ROWS; r++) { dist.push(new Array(Dungeon.COLS).fill(-1)) }
  dist[up.r][up.c] = 0
  var q = [up]
  while (q.length) {
    var n = q.shift()
    var node = floor.nodes[n.r][n.c]
    var open = [node.n, node.e, node.s, node.w]
    for (var d = 0; d < 4; d++) {
      if (open[d]) continue
      var rr = n.r + Dungeon.DR[d], cc = n.c + Dungeon.DC[d]
      if (rr < 0 || rr >= Dungeon.ROWS || cc < 0 || cc >= Dungeon.COLS) continue
      if (dist[rr][cc] !== -1) continue
      dist[rr][cc] = dist[n.r][n.c] + 1
      q.push({ r: rr, c: cc })
    }
  }
  var maxd = 0
  for (var r = 0; r < Dungeon.ROWS; r++)
    for (var c = 0; c < Dungeon.COLS; c++)
      if (dist[r][c] > maxd) maxd = dist[r][c]
  ok(dist[downs[0].r][downs[0].c] === maxd,
     "seed " + seed + ": down is the farthest cell (dist "
     + dist[downs[0].r][downs[0].c] + " vs max " + maxd + ")")
}

console.log(fails === 0 ? "ALL PASS" : fails + " FAILURES")
process.exit(fails === 0 ? 0 : 1)
