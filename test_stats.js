#!/usr/bin/env node
// test_stats.js — stat block progression rules.
const S = require("./Stats.js")

let failures = 0
function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + " " + name)
  if (!ok) failures++
}

check("fresh stats all 4", JSON.stringify(S.freshStats()) ===
  JSON.stringify({ str: 4, dex: 4, con: 4, int: 4, wil: 4, unspent: 0 }))

// Level thresholds
check("xp 0 → level 1", S.levelFromXp(0) === 1)
check("xp 99 → level 1", S.levelFromXp(99) === 1)
check("xp 100 → level 2", S.levelFromXp(100) === 2)
check("xp 199 → level 2", S.levelFromXp(199) === 2)
check("xp 200 → level 3", S.levelFromXp(200) === 3)
check("xp 1,000,000 → capped at LEVEL_CAP", S.levelFromXp(1000000) === S.LEVEL_CAP)

// addXp with unspent-point accounting
let r = S.addXp(S.freshStats(), { level: 1, xp: 0 }, 50)
check("+50 xp stays level 1, no unspent", r.level === 1 && r.stats.unspent === 0)
r = S.addXp(S.freshStats(), { level: 1, xp: 0 }, 100)   // level 2
check("level 2 grants 1 unspent point", r.level === 2 && r.stats.unspent === 1)
r = S.addXp(S.freshStats(), { level: 4, xp: 350 }, 75)  // 425 → level 5 (+1 level after L4 -> L5: no midpoint bonus)
check("level 5 from 4 gets no bonus point", r.level === 5 && r.stats.unspent === 0)
r = S.addXp(S.freshStats(), { level: 1, xp: 0 }, 250)   // level 3: +2 levels
check("level 3 from 1 gets 1 bonus point (only L2 threshold)", r.level === 3 && r.stats.unspent === 1)
r = S.addXp(S.freshStats(), { level: 1, xp: 0 }, 400)   // level 5: +4 levels -> points on L2 & L4 = 2 total
check("level 5 from 1 grants 2 bonus points (L2 and L4 thresholds)", r.level === 5 && r.stats.unspent === 2)

// assignPoint guards
let s = S.freshStats(); s.unspent = 0
let orig = JSON.stringify(s)
s = S.assignPoint(s, "str")
check("no points available = no change", JSON.stringify(s) === orig)
s.unspent = 2
s = S.assignPoint(s, "int"); s = S.assignPoint(s, "int")
check("assign points works then depletes", s.int === 6 && s.unspent === 0)
check("bogus stat ignored", JSON.stringify(S.assignPoint({ str: 1, unspent: 1 }, "strx")) ===
  JSON.stringify({ str: 1, unspent: 1 }))

// primary/derived surfaces exist
const p = S.primaryStats({ str: 12, dex: 9, con: 10, int: 8, wil: 6 })
check("primaryStats passes str/dex/int/wil through",
  p.str === 12 && p.dex === 9 && p.int === 8 && p.wil === 6)
check("con not in primaryStats (offense/defense separated)",
  p.con === undefined)

// D2 curves (2026-09-03): maxHP = 25 + 5L + floor(CON*L/2); maxMP = 10+INT+L.
check("hpMax L1 fresh CON4 → 32", S.hpMax(S.freshStats(), 1) === 32)
check("hpMax mpMax L1 → 15", S.mpMax(S.freshStats(), 1) === 15)
check("hpMax L10 noCON → 95", S.hpMax({con:4}, 10) === 95)
check("hpMax L10 fullCON (CON 9) → 120", S.hpMax({con:9}, 10) === 120)
check("hpMax L50 noCON → 375", S.hpMax({con:4}, 50) === 375)
check("hpMax L50 fullCON (CON 29) → 1000", S.hpMax({con:29}, 50) === 1000)
check("hpMax floors odd CON*L products (CON5, L3 → 25+15+7=47)",
  S.hpMax({con:5}, 3) === 47)

process.exit(failures ? 1 : 0)
