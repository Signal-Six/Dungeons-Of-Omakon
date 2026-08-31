// test_encounter.js — Monte Carlo balance report for the combat loop.
//
// Simulates full encounters: player loadout (weapon + shield, resolved
// against equipment.json) vs a monster drawn from the real spawn pool
// (Depth==F or F+k, uniform — same rule as Monsters.rollSpawn, minus the
// spawn chance gate). Player: level 1, 25 HP, fresh stats (4 all).
// No poison ticks, no flee (per design).
//
// Run: node test_encounter.js [N]   (default N = 20000 per cell)

var CL = require("./CombatLoop.js");
var Monsters = require("./Monsters.js");
var Drops = require("./Drops.js");
var Combat = require("./Combat.js");
var monsters = require("./monsters.json");
var equipment = require("./equipment.json");

var N = parseInt(process.argv[2] || "20000", 10);

function findEq(name) {
  for (var i = 0; i < equipment.length; i++)
    if (equipment[i].Name === name) return equipment[i];
  throw new Error("equipment lookup failed: " + name);
}
// Resolve an equipment entry to Combat.js source shape (Infinity handled).
function src(entry, ench) {
  function v(x) { return x === "infinite" ? Infinity : x; }
  var s = {};
  if (entry.Accuracy !== null) s.acc = v(entry.Accuracy) + (ench || 0);
  if (entry.Damage !== null) s.dmg = v(entry.Damage) + (ench || 0);
  if (entry.Defense !== null) s.def = entry.Defense + (ench || 0);
  s.enchanted = !!ench;
  return s;
}
function makeState(weaponName, shieldName) {
  var state = { str: 4, dex: 4, wil: 4, int: 4, worn: [], effects: [] };
  if (weaponName) {
    var w = findEq(weaponName);
    state.rightHand = src(w, 0);
  }
  if (shieldName) {
    var s = findEq(shieldName);
    state.leftHand = src(s, 0);
  }
  return state;
}
// Spawn-pool pick without the chance gate (encounter has already happened).
function pickMonster(floor, rng) {
  var k = Math.floor(rng() * 3);
  var target = floor + k;
  var pool = monsters.filter(function (m) { return m.Depth === floor || m.Depth === target; });
  return pool[Math.floor(rng() * pool.length)];
}

var LOADOUTS = [
  { label: "F1  bare (Rusty Sword)",            weapon: "Rusty Sword", shield: null,          floors: [1, 5] },
  { label: "F5  (Katana + Kite Shield)",        weapon: "Katana",      shield: "Kite Shield", floors: [5, 10] },
  { label: "F15 (Rifle + Kite Shield)",         weapon: "Rifle",       shield: "Kite Shield", floors: [15, 25] },
  { label: "F30 (Mana Manifold + Tower Shield)",weapon: "Mana Manifold", shield: "Tower Shield", floors: [30, 40] },
  { label: "F50 (Book of Power + Hyper Shield)",weapon: "Book of Power", shield: "Hyper Shield", floors: [50] }
];

function sim(state, floor, rng) {
  var row = pickMonster(floor, rng);
  var loop = CL.newEncounter(row);
  var hp = 25, rounds = 0, dmgTaken = 0;
  while (!loop.over) {
    CL.playerStrike(loop, state, "w");
    if (!loop.over) {
      CL.monsterStrike(loop, state, rng);
      if (loop.lastMonsterDamage > 0) hp -= loop.lastMonsterDamage;
    }
    rounds++;
    if (loop.lastMonsterDamage) dmgTaken += loop.lastMonsterDamage;
    if (hp <= 0) { loop.over = true; loop.won = false; break; }
    if (rounds > 200) break;   // safety valve (should be unreachable)
  }
  return { won: loop.won, rounds: rounds, dmg: dmgTaken, monster: row.Name, depth: row.Depth };
}

console.log("Encounter Monte Carlo — N=" + N + " per cell, level-1 hero (25 HP, 4/4/4/4)\n");
var header = "loadout".padEnd(34) + "floor  win%    avgRounds  avgDmgTaken  deaths".padStart(50);
console.log(header);
console.log("-".repeat(header.length));

for (var li = 0; li < LOADOUTS.length; li++) {
  var lo = LOADOUTS[li];
  var state = makeState(lo.weapon, lo.shield);
  for (var fi = 0; fi < lo.floors.length; fi++) {
    var F = lo.floors[fi];
    var wins = 0, roundsSum = 0, dmgSum = 0, deaths = 0;
    var rng = (function (seed) {
      return function () { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x80000000; };
    })(F * 7919 + lo.li || (F + li));
    // distinct seed per cell
    rng = (function (seed) {
      return function () { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x80000000; };
    })(1000 + F * 7919 + li * 104729);
    var worst = null;
    for (var i = 0; i < N; i++) {
      var r = sim(state, F, rng);
      if (r.won) wins++;
      else deaths++;
      roundsSum += r.rounds;
      dmgSum += r.dmg;
    }
    var winPct = (100 * wins / N).toFixed(1);
    var avgR = (roundsSum / N).toFixed(1);
    var avgD = (dmgSum / N).toFixed(1);
    console.log(
      (lo.label).slice(0, 34).padEnd(34) +
      ("F" + F).padEnd(7) +
      winPct.padEnd(9) + avgR.padEnd(11) + avgD.padEnd(13) + deaths
    );
  }
}

// Drop-rate sanity alongside (same formula the game uses on kill).
console.log("\nDrop table sanity (Drops.rollDrop):");
for (var f2 = 1; f2 <= 50; f2 += 10) {
  var drops = 0, ench = 0;
  var rng2 = (function (seed) {
    return function () { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x80000000; };
  })(f2 * 31);
  for (var j = 0; j < 100000; j++) {
    var d = Drops.rollDrop(equipment, f2, rng2);
    if (d) { drops++; if (d.Enchant) ench++; }
  }
  console.log("  floor " + String(f2).padEnd(3) + " drop rate " + (drops / 1000).toFixed(2) +
              "% (expected " + (100 * Drops.dropChance(f2)).toFixed(1) +
              "%), enchant rate on drops " + (100 * ench / Math.max(1, drops)).toFixed(1) + "%");
}
console.log("\ntest_encounter.js OK");
