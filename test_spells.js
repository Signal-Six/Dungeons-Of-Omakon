#!/usr/bin/env node
// test_spells.js — Spells.js + spells.json sanity.
var S = require("./Spells.js");
var spells = require("./spells.json");

var failures = 0;
function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + " " + name);
  if (!ok) failures++;
}
function cycler(vals) { var i = 0; return function () { return vals[(i++) % vals.length]; }; }

// --- classification -------------------------------------------------------
check("20 spells loaded", spells.length === 20);
check("Mana Missile is damage", S.classify(S.findByName(spells, "Mana Missile")) === "damage");
check("Mana Ray is damage", S.classify(S.findByName(spells, "Mana Ray")) === "damage");
check("Lightning Bolt is damage", S.classify(S.findByName(spells, "Lightning Bolt")) === "damage");
check("Lesser Heal is heal", S.classify(S.findByName(spells, "Lesser Heal")) === "heal");
check("Heal is heal", S.classify(S.findByName(spells, "Heal")) === "heal");
check("Greater Heal is heal", S.classify(S.findByName(spells, "Greater Heal")) === "heal");
check("Magic Barrier is buff", S.classify(S.findByName(spells, "Magic Barrier")) === "buff");
check("Revengeance Barrier is buff", S.classify(S.findByName(spells, "Revengeance Barrier")) === "buff");
check("Haste is buff", S.classify(S.findByName(spells, "Haste")) === "buff");
check("Flyer Fins is buff", S.classify(S.findByName(spells, "Flyer Fins")) === "buff");
check("Ice Shield is buff", S.classify(S.findByName(spells, "Ice Shield")) === "buff");
check("Shadow Globe is buff", S.classify(S.findByName(spells, "Shadow Globe")) === "buff");
check("Wind Shield is buff", S.classify(S.findByName(spells, "Wind Shield")) === "buff");
check("Water Shield is buff", S.classify(S.findByName(spells, "Water Shield")) === "buff");
check("Slip is special", S.classify(S.findByName(spells, "Slip")) === "special");
check("Imbibe Luck is special", S.classify(S.findByName(spells, "Imbibe Luck")) === "special");
check("Blink is blink", S.classify(S.findByName(spells, "Blink")) === "blink");
check("Fireball is damage (has additive burn effect)", S.classify(S.findByName(spells, "Fireball")) === "damage");
check("Glacial Shard is damage", S.classify(S.findByName(spells, "Glacial Shard")) === "damage");
check("Blood Wrench is damage", S.classify(S.findByName(spells, "Blood Wrench")) === "damage");

// --- rollFormula ----------------------------------------------------------
check("'1d4+INT' with INT 8 (cycled 0.5 → d4=3) → 11",
  S.rollFormula("1d4+INT", 8, cycler([0.5])) === 11);
check("'1d12+(INT/2)' with INT 8 (cycled 0.5 → d12=7, 8/2=4) → 11",
  S.rollFormula("1d12+(INT/2)", 8, cycler([0.5])) === 11);
check("'INT/4' with INT 8 → 2 (no dice)",
  S.rollFormula("INT/4", 8) === 2);
check("'1+INT/4' with INT 8 → 3",
  S.rollFormula("1+INT/4", 8) === 3);
check("'3d6+(INT/2)' cycled 0.5 → d6=4 thrice, +4 → 16",
  S.rollFormula("3d6+(INT/2)", 8, cycler([0.5, 0.5, 0.5])) === 16);
check("'2d10' rolls only dice → 12 with 0.5 (each d10 → 1+floor(0.5*10)=6)",
  S.rollFormula("2d10", 4, cycler([0.5, 0.5])) === 12);
check("null expr → 0", S.rollFormula(null, 8) === 0);

// --- activate / tickAll ----------------------------------------------------
var magic = S.findByName(spells, "Magic Barrier");   // Duration "INT/2"
var haste = S.findByName(spells, "Haste");           // Duration "2d10"
var a1 = S.activate(magic, 8, cycler([0.5]));   // int/2 = 4 steps
check("Magic Barrier INT/2 at 8 = 4 steps", a1.stepsLeft === 4);
var a2 = S.activate(haste, 8, cycler([0.5, 0.5]));  // 2d10 cycled → 12
check("Haste 2d10 cycled 0.5 = 12 steps", a2.stepsLeft === 12);

var t = S.tickAll([a1, a2]);
check("after one tick: a1 3 left, a2 11 left",
  t.active[0].stepsLeft === 3 && t.active[1].stepsLeft === 11);
check("no expirations yet", t.expired.length === 0);

var ran = 0, cur = [a1, a2];
while (cur.length || ran > 20) {  // burn a1 off
  var r = S.tickAll(cur);
  cur = r.active; ran++;
  if (r.expired.some(function (x) { return x.name === "Magic Barrier"; })) break;
}
check("Magic Barrier expires after 4 ticks", ran === 4);

// --- actives round-trip via serialization --------------------------------
var actives = [S.activate(magic, 8, null)];
actives[0].custom.shieldHp = 14;
var saved = S.serializeActives(actives);
check("actives serialize as plain {Name, stepsLeft, custom}",
  saved[0].Name === "Magic Barrier" && saved[0].stepsLeft === 4
    && saved[0].custom.shieldHp === 14);
var revived = S.reviveActives(saved, spells);
check("revived actives rehydrate defs", revived.length === 1 && revived[0].def.Name === "Magic Barrier");

process.exit(failures ? 1 : 0);
