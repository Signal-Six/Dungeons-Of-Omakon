// Monsters.js — spawn tables and (later) monster behavior for Dungeons of
// Omakon. Pure logic, no QML imports; node-testable like Dungeon.js.
//
// Spawn model (per design discussion 2026-08-24):
//   - Every movement action rolls for a spawn.
//   - Chance per move on floor F = F * 0.1%  (floor 1 → 0.001, floor 10 →
//     1%, floor 50 → 5%).
//   - On a hit, roll 1d3-1 (k in {0,1,2}) and build the candidate pool:
//     all monsters whose Depth == F, plus all with Depth == F+k.
//   - Pick uniformly from the pool (equal weight, not per-species share).
//
// Clamping: F+k can exceed the dungeon depth (50). Depths above the last
// authored monster depth simply contribute nothing — a capped table is the
// data sheet's job, not the algorithm's.

// Pick a spawn for floor F. rng is a 0..1 PRNG (Dungeon.rngFromSeed
// output or Math.random). Returns the monster entry or null.
// monsters = [{ Name, Depth, ... }], depth field spelled like the JSON.
// 2026-08-31: user adjusted to flat 15% base rate (was floor*0.1)
function rollSpawn(monsters, floor, rng) {
  rng = rng || Math.random
  if (rng() >= 0.15) return null
  var k = Math.floor(rng() * 3)            // 1d3 - 1
  var target = floor + k
  var pool = []
  for (var i = 0; i < monsters.length; i++) {
    var d = monsters[i].Depth
    if (d === floor || d === target) pool.push(monsters[i])
  }
  if (pool.length === 0) return null
  return pool[Math.floor(rng() * pool.length)]
}

// Convenience: chance for floor F (for tests/UI display).
function spawnChance(floor) { return floor * 0.001 }

if (typeof module !== "undefined" && module.exports) {
  module.exports = { rollSpawn: rollSpawn, spawnChance: spawnChance }
}
