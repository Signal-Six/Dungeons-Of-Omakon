#!/usr/bin/env node
// Test harness for Dungeon.js — run: node test_dungeon.js
const D = require("./Dungeon.js")

let failures = 0
function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + " " + name)
  if (!ok) failures++
}

// Deterministic seeds produce identical floors
const a = D.generate(1234), b = D.generate(1234), c = D.generate(5678)
check("deterministic per seed", JSON.stringify(a.nodes) === JSON.stringify(b.nodes))
check("different seeds differ", JSON.stringify(a.nodes) !== JSON.stringify(c.nodes))
check("6x7 grid", a.nodes.length === 6 && a.nodes.every(r => r.length === 7))

// Connectivity: BFS from start reaches all 42 nodes (walls only block when
// there's no carved passage, and the maze is perfect).
function reachableCount(f) {
  const seen = new Set(), q = [[f.start.row, f.start.col]]
  seen.add(f.start.row + "," + f.start.col)
  while (q.length) {
    const [r, c2] = q.shift()
    const n = f.nodes[r][c2]
    const open = [n.n, n.e, n.s, n.w].map(w => !w)
    open.forEach((isOpen, d) => {
      if (!isOpen) return
      const nr = r + D.DR[d], nc = c2 + D.DC[d]
      if (nr < 0 || nr >= 6 || nc < 0 || nc >= 7) return
      const k = nr + "," + nc
      if (!seen.has(k)) { seen.add(k); q.push([nr, nc]) }
    })
  }
  return seen.size
}
for (const seed of [1, 2, 3, 42, 999, 31337])
  check("seed " + seed + " fully connected (42 nodes)", reachableCount(D.generate(seed)) === 42)

// Stairs: up at start corner, down exists and isn't the start
const f = D.generate(42)
check("up stairs at start", f.nodes[f.start.row][f.start.col].feature === "up")
let downs = 0, downPos = null
f.nodes.forEach((row, r) => row.forEach((n, c2) => { if (n.feature === "down") { downs++; downPos = { row: r, col: c2 } } }))
check("exactly one downstairs", downs === 1)
check("downstairs not at entrance", !(downPos.row === f.start.row && downPos.col === f.start.col))

// Vista from entrance facing north: depth-1 end wall state matches movement
let pos = { row: f.start.row, col: f.start.col, facing: 0 }
const v = D.vista(f, pos)
check("vista returns 2 depths", v.length === 2)
check("depth1 end == wall ahead", v[0].end === D.hasWall(f, pos.row, pos.col, 0))

// Movement respects walls: try stepping in a direction; result consistent
// with hasWall.
for (let d = 0; d < 4; d++) {
  const moved = D.move(f, pos, d)
  const walled = D.hasWall(f, pos.row, pos.col, (pos.facing + d) % 4)
  check("move dir " + d + (walled ? " blocked" : " free"),
    walled ? (moved.row === pos.row && moved.col === pos.col) : (moved.row !== pos.row || moved.col !== pos.col))
}

// Walk a random path; position never leaves the grid, never crosses walls.
let p = { row: f.start.row, col: f.start.col, facing: 0 }
const rand = D.rngFromSeed(7)
let ok = true
for (let i = 0; i < 500; i++) {
  const dir = Math.floor(rand() * 4)
  if (rand() < 0.3) p = D.turn(p, rand() < 0.5 ? -1 : 1)
  else {
    const before = p
    p = D.move(f, p, dir)
    const d = (before.facing + dir) % 4
    if ((p.row !== before.row || p.col !== before.col) && D.hasWall(f, before.row, before.col, d)) ok = false
  }
  if (p.row < 0 || p.row > 5 || p.col < 0 || p.col > 6) ok = false
}
check("500-step random walk stays legal", ok)

process.exit(failures ? 1 : 0)
