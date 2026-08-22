#!/usr/bin/env node
// Debug harness: for every node + facing in a generate()d floor, print an
// ASCII minimap of the view + the vista flags, so we can hand-check that the
// renderer's inputs agree with the maze's actual walls.
const D = require("./Dungeon.js")
const f = D.generate(42)

function renderLocal(pos) {
  // 5x5 local window centered on the player, with facing 'N' rotated up.
  const out = []
  for (let dr = -2; dr <= 2; dr++) {
    let line = ""
    for (let dc = -2; dc <= 2; dc++) {
      // rotate so facing direction is "up" on the page
      let rr = pos.row, cc = pos.col
      const rel = relative(dr, dc, pos.facing)
      rr += rel.drow; cc += rel.dcol
      if (rr < 0 || rr >= 6 || cc < 0 || cc >= 7) { line += "####"; continue }
      const n = f.nodes[rr][cc]
      // cell marker + north/east/south/west walls as micro-glyphs
      line += (n.n ? "-" : " ") + (n.w ? "|" : " ")
      line += (rr === pos.row && cc === pos.col ? "@" : " ")
      line += (n.e ? "|" : " ")
    }
    out.push(line)
  }
  return out
}
function relative(dr, dc, facing) {
  // facing 0=N: up-page = -row. 1=E: up-page = +col. 2=S: +row. 3=W: -col.
  switch (facing) {
    case 0: return { drow: dr, dcol: dc }
    case 1: return { drow: -dc, dcol: -dr }
    case 2: return { drow: -dr, dcol: -dc }
    case 3: return { drow: dc, dcol: dr }
  }
}

// Print the vista flags for each cell + facing where anything interesting
// happens (corridor corners), then eyeball.
const pos = { row: 4, col: 2, facing: 0 }
console.log("Local map (facing N):")
renderLocal(pos).forEach(l => console.log("  " + l))
const v = D.vista(f, pos)
console.log("vista:", JSON.stringify(v, null, 1))
console.log("wallAt(0 fwd):", D.hasWall(f, pos.row, pos.col, 0))
