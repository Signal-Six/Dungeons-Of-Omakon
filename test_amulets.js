// test_amulets.js — Accuracy / Destruction amulets contribute their flat
// Accuracy/Damage to the player's formulas exactly like weapon rows do: the
// effect follows the equipment slot (worn.amulet), and does nothing when the
// amulet sits in the pack or is unequipped.
var Combat = require("./Combat.js")
var equipment = require("./equipment.json")
var fails = 0
function ok(c, m) { if (!c) { fails++; console.log("FAIL " + m) }
                    else console.log("ok  " + m) }

function byName(name) {
  for (var i = 0; i < equipment.length; i++)
    if (equipment[i].Name === name) return equipment[i]
  return null
}
// Mirror of Panel.resolveInstance()'s shape — nulls for absent stats.
function src(name, ench) {
  var e = byName(name)
  ench = ench || 0
  return {
    name: name,
    acc: (typeof e.Accuracy === "number") ? e.Accuracy + ench : null,
    dmg: (typeof e.Damage   === "number") ? e.Damage   + ench : null,
    def: (typeof e.Defense  === "number") ? e.Defense  + ench : null,
    enchanted: ench > 0
  }
}

var hero = { str: 4, dex: 4, int: 4, wil: 4, worn: [], effects: [] }

// Baseline: naked hands.
var bare = Combat.accuracyOf(hero)     // = dex = 4
ok(bare === 4, "naked ACC = DEX only (got " + bare + ")")
var bareDmg = Combat.baseDamageOf(hero)   // = str = 4
  // baseDamageOf in Combat.js: sumStat(sources, "dmg") + (state.str || 0)
ok(bareDmg === 4, "naked DAM = STR only (got " + bareDmg + ")")

// Wearing the Amulet of Accuracy: +10 ACC.
var withAcc = { str: 4, dex: 4, int: 4, wil: 4,
                worn: [ src("Amulet of Accuracy") ], effects: [] }
ok(Combat.accuracyOf(withAcc) === 14, "Amulet of Accuracy adds +10 ACC (got "
  + Combat.accuracyOf(withAcc) + ")")
ok(Combat.baseDamageOf(withAcc) === 4, "...no damage change when worn")

// Amulet of Destruction: +10 DAM, no ACC.
var withDest = { str: 4, dex: 4, int: 4, wil: 4,
                 worn: [ src("Amulet of Destruction") ], effects: [] }
ok(Combat.baseDamageOf(withDest) === 14, "Amulet of Destruction adds +10 DAM (got "
  + Combat.baseDamageOf(withDest) + ")")
ok(Combat.accuracyOf(withDest) === 4, "...no accuracy change when worn")

// Unequipped (in pack, not in the worn slot) contributes nothing.
var inPack = { str: 4, dex: 4, int: 4, wil: 4, worn: [], effects: [] }
// The pack isn't consulted by Combat — combatState() never passes it.
ok(Combat.accuracyOf(inPack) === 4 && Combat.baseDamageOf(inPack) === 4,
   "amulet in pack contributes nothing (only worn.amulet matters)")

// Both worn together (two amulet slots aren't a thing; here worn is a
// flat list so stacking two amulets would double-count — the same double-
// count already exists for wearing two armors, matching the current worn
// shape). Documenting the behavior, not endorsing a two-amulet build.
var both = { str: 4, dex: 4, int: 4, wil: 4,
             worn: [src("Amulet of Accuracy"), src("Amulet of Destruction")], effects: [] }
ok(Combat.accuracyOf(both) === 14 && Combat.baseDamageOf(both) === 14,
   "both amulets worn contribute both stats (current slot model)")

// Enchant of the amulet itself applies its amount on top of the flat +10
// (same as weapons): +1 Accuracy amulet -> +11.
var ench = { str: 4, dex: 4, int: 4, wil: 4,
             worn: [ src("Amulet of Accuracy", 1) ], effects: [] }
ok(Combat.accuracyOf(ench) === 15, "enchant stacks on top of the flat +10 (got "
  + Combat.accuracyOf(ench) + ")")

// And accuracy still matters end-to-end in attack(): +10 ACC against an
// 11-DV rat flips the outcome without the amulet (needs 7+ on 2d6 ≈ 58%)
// vs always-hits with the amulet (worst 2+ ACC floor is 2+4+10=16 >= 11).
function fixed2d6(a, b) { var seq = [a, b]; var i = 0; return function () {
  // value between 0 and 1 hitting exactly those die faces
  var d = seq[i++ % seq.length]
  return (d - 1) / 6     // rollDie: 1 + floor(r*6) = d when r in [(d-1)/6, d/6)
} }
var monster = { dv: 11 }
var nakedWorst = Combat.attack(hero, monster, fixed2d6(1, 1))
ok(!nakedWorst.hit, "naked hero with ACC 4 whiffs vs DV 11 at worst roll (got acc="
  + nakedWorst.accRoll + ")")
var amuWorst = Combat.attack(withAcc, monster, fixed2d6(1, 1))
ok(amuWorst.hit, "amulet wearer vs DV 11 hits even at worst roll (acc=" + amuWorst.accRoll + ")")

console.log(fails === 0 ? "ALL PASS" : fails + " FAILURES")
process.exit(fails === 0 ? 0 : 1)
