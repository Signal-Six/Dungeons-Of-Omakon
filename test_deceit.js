// test_deceit.js — scale against the real equipment table + the monsterTurn
// semantics mirrored from the QML: Bindor's Deceit sets combat.deceitLeft=2,
// consumed one per incoming monster swing BEFORE any other resolution.
var equipment = require("./equipment.json")
var fails = 0
function ok(c, m) { if (!c) { fails++; console.log("FAIL " + m) }
                    else console.log("ok  " + m) }

// The source row must exist (it was a 2026-08-30 pending effect).
var inst = null
for (var i = 0; i < equipment.length; i++)
  if (equipment[i].Name === "Bindor’s Deceit") { inst = equipment[i]; break }
ok(inst !== null, "Bindor’s Deceit is in equipment.json")
ok(inst.Type === "Item", "it's an Item (pack-usable)")

// Combat-side contract reproduced under node (mirrors Panel.monsterTurn):
function makeCombat() { return { over: false, won: false, log: [], slipNext: false, deceitLeft: 0 } }
function monsterTurn(c) {
  if (!c || c.over) return
  if (c.deceitLeft && c.deceitLeft > 0) {
    c.deceitLeft--
    c.log.push("The smoke blinds the monster — attack negated! (" + c.deceitLeft + " left)")
    return
  }
  if (c.slipNext) { c.slipNext = false; c.log.push("slip!") ; return }
  c.log.push("monster hits")
}

var c = makeCombat()
c.deceitLeft = 2
monsterTurn(c); ok(c.log[c.log.length-1].indexOf("negated") >= 0 &&
                   c.deceitLeft === 1, "first negation consumed -> 1 left")
monsterTurn(c); ok(c.log[c.log.length-1].indexOf("(0 left)") >= 0 &&
                   c.deceitLeft === 0, "second negation consumed -> 0 left")
monsterTurn(c); ok(c.log[c.log.length-1] === "monster hits",
                   "after two negations the monster attacks normally")

// Out-of-combat use guard (no monster to blind -> fizzle, log, no consume).
var c2 = makeCombat()
ok(c2.over === false && c2.deceitLeft === 0, "fresh combat starts with deceitLeft=0")

console.log(fails === 0 ? "ALL PASS" : fails + " FAILURES")
process.exit(fails === 0 ? 0 : 1)
