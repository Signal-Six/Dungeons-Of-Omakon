#!/usr/bin/env node
// test_poison.js — Poison.js lifecycle, Panel wiring invariants.
var P = require("./Poison.js");
var Save = require("./Save.js");

var failures = 0;
function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + " " + name);
  if (!ok) failures++;
}

// 1. State shape from start().
var s = P.start(4);
check("start: dmg 4, movesLeft 5 (= DURATION)",
  s.dmg === 4 && s.movesLeft === 5 && P.DURATION === 5);

// 2. Five ticks, flat damage each, then auto-clear.
var st = P.start(5);
var total = 0, r = null;
for (var i = 0; i < 5; i++) { r = P.tick(st); st = r.state; total += r.damage; }
check("5 ticks of 5 = 25 damage", total === 25);
check("state clears after the 5th tick", st === null);
check("done flag only on the 5th tick", r.done === true);

// 3. Null state ticks clean (no damage, no crash).
var n = P.tick(null);
check("unpoisoned tick: 0 damage", n.damage === 0 && n.state === null);

// 4. 4th tick is not done yet (checks the boundary).
var st2 = P.start(3);
var r4;
for (var j = 0; j < 4; j++) { r4 = P.tick(st2); st2 = r4.state; }
check("4th tick: state still live, done=false", st2 !== null && r4.done === false);

// 5. Immunity prose sniffing (Lucid Crystal).
check("Lucid Crystal prose is immune",
  P.isImmune("In addition to providing a modicum of defense, this amulet prevents the user from being poisoned."));
check("ordinary amulet is not immune", !P.isImmune("A plain silver chain."));
check("null/missing description is not immune", !P.isImmune(null) && !P.isImmune(""));

// 6. Poison rides the save (v6 field).
var saved = JSON.parse(Save.serializeRun({
  name: "x", started: "", hp: 1, hpMax: 1, mp: 1, mpMax: 1, level: 1, xp: 0,
  stats: null, leftHand: null, rightHand: null, worn: null,
  pack: new Array(12).fill(null), spells: [], effects: [],
  poison: { dmg: 3, movesLeft: 4 },
  floorNum: 1, seed: 1, pos: null, explored: {}
}));
check("save version is 7", saved.version === 7);
check("poison survives the JSON round-trip",
  saved.poison && saved.poison.dmg === 3 && saved.poison.movesLeft === 4);
check("v7 parses", Save.parseRun(JSON.stringify(saved)) !== null);
check("v5 still parses", Save.parseRun(
  '{"version":5,"name":"x","pack":[],"explored":{}}') !== null);

process.exit(failures ? 1 : 0);
