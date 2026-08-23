#!/usr/bin/env node
// test_save.js — Save.js round-trips and archive rules. Run: node test_save.js
const S = require("./Save.js")

let failures = 0
function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + " " + name)
  if (!ok) failures++
}

const state = {
  name: "Grummsh", started: "2026-08-23T10:00:00Z",
  hp: 14, hpMax: 20, mp: 3, mpMax: 8,
  level: 2, xp: 150,
  leftHand: null, rightHand: { icon: "†", name: "Rusty Sword" },
  pack: new Array(12).fill(null), spells: [],
  floorNum: 3, seed: 424242,
  pos: { row: 2, col: 4, facing: 1 },
  explored: { "5,0": true, "4,0": true }
}
const text = S.serializeRun(state)
const back = S.parseRun(text)
check("run round-trip", JSON.stringify(back) === JSON.stringify(JSON.parse(text)))
check("empty run parses null", S.parseRun("") === null && S.parseRun(null) === null)
check("garbage run parses null", S.parseRun("not json") === null)
check("wrong version parses null", S.parseRun('{"version":3}') === null)

check("empty archive parses []", S.parseArchive("").length === 0)
let a = []
for (let i = 1; i <= 12; i++)
  a = S.appendArchive(a, { name: "h" + i, started: "", floor: i, level: 1, score: i })
check("archive caps at 10", a.length === 10)
check("archive newest first", a[0].name === "h12" && a[9].name === "h3")

check("score formula", S.computeScore({ floorNum: 3, level: 2 }) === 320)

check("store script targets field", S.storeScript("run").indexOf("field run") > -1)
check("load cmd reads field archive", S.loadCmd("archive").indexOf("field archive") > -1)

process.exit(failures ? 1 : 0)
