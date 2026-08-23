#!/usr/bin/env node
// test_combat.js — attack math against monsters per the user spec.
const C = require("./Combat.js")
const assert = require("assert")

let failures = 0
function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + " " + name)
  if (!ok) failures++
}

// Deterministic RNG
function mkRng(v) { return () => v }

// sumStat keying: numbers, {acc: n}, {acc: {bonus: n}} all aggregate.
check("sumStat numbers", C.sumStat([1, 2, null, 3], "acc") === 6)
check("sumStat objects", C.sumStat([{ acc: 5 }, { acc: { bonus: 2 } }], "acc") === 7)
check("sumStat mixed ignores other keys", C.sumStat([{ acc: 3, dmg: 9 }], "acc") === 3)

// equippedSources pulls hands + worn + effects
const st = {
  rightHand: { acc: 5, dmg: 8 },
  leftHand: null,
  worn: [ { acc: 1 }, null ],
  effects: [ { dmg: 2 } ],
  str: 3, dex: 2
}
check("ACC = sum(acc) + DEX", C.accuracyOf(st) === 5 + 1 + 2)
check("baseDAM = sum(dmg) + STR", C.baseDamageOf(st) === 8 + 2 + 3)

// attack: miss vs hit at the DV boundary
let r = C.attack({ dex: 2, rightHand: { acc: 4, dmg: 3 } }, { dv: 5 }, mkRng(0.0))
check("ACC 6 < DV 5 → hit", r.hit && r.damage === 3 + 1)   // d4 min
r = C.attack({ dex: 2, rightHand: { acc: 3, dmg: 3 } }, { dv: 5 }, mkRng(0.0))
check("ACC 5 >= DV 5 → hit boundary", r.hit)
r = C.attack({ dex: 2, rightHand: { acc: 2, dmg: 3 } }, { dv: 5 }, mkRng(0.0))
check("ACC 4 < DV 5 → miss", !r.hit && r.damage === undefined)

// d4 extremes via rng: result spans base+1 .. base+4
const state2 = { str: 0, dex: 0, rightHand: { acc: 0, dmg: 4 } }
let out = []
for (let i = 0; i < 4; i++) out.push(C.attack(state2, { dv: 0 }, mkRng(i / 4 + 0.001)).damage)
check("d4 range covers full 1..4", JSON.stringify(out) === JSON.stringify([5, 6, 7, 8]))

process.exit(failures ? 1 : 0)
