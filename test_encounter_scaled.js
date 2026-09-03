// test_encounter_scaled.js — Monte Carlo of the combat loop under the
// D2 HP curve (25+5L+floor(CON*L/2)) vs the old baseline (20+CON+L, L1→25).
// Proxy: level == floor. offense fixed at 4/4/4/4 + loadout so only the
// HP pool varies between scenarios.
var CL = require("./CombatLoop.js");
var monsters = require("./monsters.json");
var equipment = require("./equipment.json");
var N = parseInt(process.argv[2] || "20000", 10);

function findEq(name) {
  for (var i = 0; i < equipment.length; i++)
    if (equipment[i].Name === name) return equipment[i];
  throw new Error(name);
}
function src(entry) {
  function v(x) { return x === "infinite" ? Infinity : x; }
  var s = {};
  if (entry.Accuracy !== null) s.acc = v(entry.Accuracy);
  if (entry.Damage !== null) s.dmg = v(entry.Damage);
  if (entry.Defense !== null) s.def = entry.Defense;
  s.enchanted = false;
  return s;
}
function makeState(weaponName, shieldName) {
  var state = { str: 4, dex: 4, wil: 4, int: 4, worn: [], effects: [] };
  if (weaponName) { state.rightHand = src(findEq(weaponName)); }
  if (shieldName) { state.leftHand = src(findEq(shieldName)); }
  return state;
}
function pickMonster(floor, rng) {
  var k = Math.floor(rng() * 3), target = floor + k;
  var pool = monsters.filter(function (m) { return m.Depth === floor || m.Depth === target; });
  return pool[Math.floor(rng() * pool.length)];
}
function hpD2(L, con) { return 25 + 5 * L + Math.floor(con * L / 2); }

var LOADOUTS = [
  { label: "F1  (Rusty Sword)",              weapon: "Rusty Sword",  shield: null,           floors: [1, 5] },
  { label: "F5  (Katana + Kite Shield)",     weapon: "Katana",       shield: "Kite Shield",  floors: [5, 10] },
  { label: "F15 (Rifle + Kite Shield)",      weapon: "Rifle",        shield: "Kite Shield",  floors: [15, 25] },
  { label: "F30 (Mana Manifold + Tower)",    weapon: "Mana Manifold", shield: "Tower Shield", floors: [30, 40] },
  { label: "F50 (Book of Power + Hyper)",    weapon: "Book of Power", shield: "Hyper Shield", floors: [50] }
];

function sim(state, floor, hp, rng) {
  var row = pickMonster(floor, rng);
  var loop = CL.newEncounter(row);
  var rounds = 0;
  while (!loop.over) {
    CL.playerStrike(loop, state, "w");
    if (!loop.over) {
      CL.monsterStrike(loop, state, rng);
      hp -= loop.lastMonsterDamage;
    }
    rounds++;
    if (hp <= 0) { loop.over = true; loop.won = false; break; }
    if (rounds > 400) break;
  }
  return loop.won;
}

console.log("Encounter win% — N=" + N + "/cell, offense fixed (4/4/4/4 + loadout)");
console.log("Variants: OLD25 (25 HP) | D2-noCON hp=25+5L+2L | D2-fullCON hp=25+5L+(4+L/2)L/2\n");
var hdr = "loadout".padEnd(30) + "floor".padEnd(7) + "D2hp(nofull)".padEnd(14) + "old25%".padStart(8) + "D2noCON%".padStart(10) + "D2fullCON%".padStart(12);
console.log(hdr); console.log("-".repeat(hdr.length));

for (var li = 0; li < LOADOUTS.length; li++) {
  var lo = LOADOUTS[li];
  var state = makeState(lo.weapon, lo.shield);
  for (var fi = 0; fi < lo.floors.length; fi++) {
    var F = lo.floors[fi];
    var hpNo = hpD2(F, 4), hpFull = hpD2(F, 4 + Math.floor(F / 2));
    var wOld = 0, wNo = 0, wFull = 0;
    var mk = function (seed) { return function () { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x80000000; }; };
    var r1 = mk(7000 + F * 7919 + li), r2 = mk(7000 + F * 7919 + li), r3 = mk(7000 + F * 7919 + li);
    for (var i = 0; i < N; i++) {
      if (sim(state, F, 25, r1)) wOld++;
      if (sim(state, F, hpNo, r2)) wNo++;
      if (sim(state, F, hpFull, r3)) wFull++;
    }
    console.log(
      lo.label.slice(0, 30).padEnd(30) + ("F" + F).padEnd(7) +
      (hpNo + "/" + hpFull).padEnd(14) +
      (100 * wOld / N).toFixed(1).padStart(8) +
      (100 * wNo / N).toFixed(1).padStart(10) +
      (100 * wFull / N).toFixed(1).padStart(12)
    );
  }
}
