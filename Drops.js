// Drops.js — per-kill loot rolls for Dungeons of Omakon. Pure logic, no
// QML imports; node-testable like Dungeon.js / Monsters.js.
//
// Formula (agreed 2026-08-24):
//   1. P(any drop) = 0.25 + floor * 0.005       (25.5% F1 … 50% F50)
//   2. Type roll: Weapon 30%, Shield 15%, Item 55%
//   3. Within type: weight = 1 / Rank^1.5, uniform-normalized pick
//   4. Floor gate: only items with Rank <= ceil(floor/5) + 2 can drop —
//      progression pacing so a floor-2 run can never see a Sapien Cannon.
//   5. Entries carrying FixedDrop (The Omatrix) are never in the pool —
//      they are scriptedly placed, not rolled.
//
// If the gated type pool is empty (can happen on very early floors for a
// type with no low-rank entries), fall back to the full gated pool across
// all types so a successful drop roll never fizzles silently.
//
// Enchantments (2026-08-24): when a Weapon, Shield, Helmet or Armor drops,
// flat 25% chance it's enchanted; on success roll 1d6 → instance carries
// Enchant = 1..6. Amulets and Items never receive the roll.
//   weapon: effective Accuracy/Damage = base + Enchant
//   shield/helmet/armor: effective Defense = base + Enchant
//     (shield Accuracy penalty unchanged)
// Instances are returned as { Name, Enchant } — the pack stores instances
// and resolves stats against equipment.json by Name; display renders as
// "+N Sword". Enchant is absent (not 0) on unenchanted drops.
//
// TODO (Effects.js phase): item-on-item use. Scroll of Enchantment will
// apply Enchant+1 to a chosen weapon/shield instance in the pack via an
// Effects.js registry keyed by item name; pack UI needs a target-pick mode.

var TYPE_WEIGHTS = { Weapon: 0.30, Shield: 0.15, Armor: 0.10,
                     Helmet: 0.08, Amulet: 0.07, Item: 0.30 }
var ENCHANT_CHANCE = 0.25

function dropChance(floor) { return 0.25 + floor * 0.005 }
function rankGate(floor) { return Math.ceil(floor / 5) + 2 }
function rankWeight(rank) { return 1 / Math.pow(rank, 1.5) }

// equipment: parsed equipment.json array. floor: 1..50. rng: 0..1 PRNG.
// Returns an instance { Name, Enchant? } or null.
function rollDrop(equipment, floor, rng) {
  rng = rng || Math.random
  if (rng() >= dropChance(floor)) return null

  var gate = rankGate(floor)
  var pool = []
  for (var i = 0; i < equipment.length; i++) {
    var e = equipment[i]
    if (e.FixedDrop) continue
    if (e.Rank > gate) continue
    pool.push(e)
  }
  if (pool.length === 0) return null

  // Type roll with fallback to the whole gated pool when empty.
  var tr = rng()
  var acc = 0, wantType = "Item"
  for (var t in TYPE_WEIGHTS) { acc += TYPE_WEIGHTS[t]; if (tr < acc) { wantType = t; break } }
  var typed = pool.filter(function (e) { return e.Type === wantType })
  var candidates = typed.length > 0 ? typed : pool

  // Weighted pick by inverse rank.
  var total = 0
  for (i = 0; i < candidates.length; i++) total += rankWeight(candidates[i].Rank)
  var pick = rng() * total
  var chosen = candidates[candidates.length - 1]
  for (i = 0; i < candidates.length; i++) {
    pick -= rankWeight(candidates[i].Rank)
    if (pick <= 0) { chosen = candidates[i]; break }
  }

  var instance = { Name: chosen.Name }
  var enchantable = (chosen.Type === "Weapon" || chosen.Type === "Shield"
                  || chosen.Type === "Helmet" || chosen.Type === "Armor")
  if (enchantable && rng() < ENCHANT_CHANCE) {
    instance.Enchant = 1 + Math.floor(rng() * 6)  // 1d6
  }
  return instance
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    rollDrop: rollDrop, dropChance: dropChance,
    rankGate: rankGate, rankWeight: rankWeight, TYPE_WEIGHTS: TYPE_WEIGHTS,
    ENCHANT_CHANCE: ENCHANT_CHANCE
  }
}
