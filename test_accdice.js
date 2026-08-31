// test_accdice.js — swinginess study for the player ACC formula.
//
// Question: does adding dice to the player's ACC (currently flat
// ACC = ΣAccuracy + DEX) give a low-level hero a fighting chance against
// the F1/F2 pool, where a flat 5 vs DV 6-10 is a guaranteed miss?
//
// Each variant rolls a FULL encounter (player-first, retaliate-only, no
// flee) the same way CombatLoop does, but the player ACC formula is
// swappable so we can compare designs without touching Combat.js.
//
// Run: node test_accdice.js [N]   (default N = 20000 per cell)

var D = require("./Dice.js");
var monsters = require("./monsters.json");

var N = parseInt(process.argv[2] || "20000", 10);

// --- Fixed fresh-hero baseline (level 1, 4/4/4/4, Rusty Sword, no shield) ---
// ACC base = weapon Accuracy 1 + DEX 4 = 5
// Damage base = weapon Damage 1 + STR 4 = 5, then +1d4 (Combat.attack)
// Player DV = 10 + DEX 4 = 14 (no shield); HP = 25
var HP = 25;
var PLAYER_DV = 14;
var ACC_BASE = 5;
var DMG_BASE = 5;

// ACC variants: name -> function returning the TOTAL accuracy roll.
var VARIANTS = {
  "flat (current)": function () { return ACC_BASE; },
  "ACC+1d20":       function () { return ACC_BASE + 1 + Math.floor(Math.random() * 20); },
  "ACC+2d6":        function () { return ACC_BASE + (1 + Math.floor(Math.random() * 6)) + (1 + Math.floor(Math.random() * 6)); },
  "ACC+1d10":       function () { return ACC_BASE + 1 + Math.floor(Math.random() * 10); }
};

// One full encounter. mon = a table row. Returns {won, rounds}.
function fight(mon, accRoll) {
  var hp = HP, mhp = mon.HP, rounds = 0;   // table field is HP (uppercase)
  while (rounds++ < 500) {
    // player strike
    var acc = accRoll();
    if (acc >= mon.DV) {
      mhp -= DMG_BASE + 1 + Math.floor(Math.random() * 4);  // base + 1d4
      if (mhp <= 0) return { won: true, rounds: rounds };
    }
    // monster retaliates only if it survived
    if (D.roll(mon.ACC) >= PLAYER_DV) {
      hp -= D.roll(mon.DAMAGE);
      if (hp <= 0) return { won: false, rounds: rounds };
    }
  }
  return { won: false, rounds: rounds, timeout: true };
}

// F1 + F2 pool (what a floor-1 hero actually meets).
var pool = monsters.filter(function (m) { return m.Depth <= 2; });

// Sanity check the harness: flat ACC 5 vs Rat (DV 5) must be ~100% win.
var sanity = 0;
for (var i = 0; i < 2000; i++)
  if (fight(Object.assign({}, pool[0]), VARIANTS["flat (current)"]).won) sanity++;
console.log("Harness sanity: flat vs Rat (DV 5) win rate = " + (100 * sanity / 2000).toFixed(0) + "% (expect ~100%)");
console.log("");

var vnames = Object.keys(VARIANTS);
var COL = 20;
console.log("Fresh hero (25 HP, ACC base 5, dmg 5+1d4, DV 14) vs F1/F2 pool, N=" + N);
console.log("");
var header = "monster".padEnd(18) + "DV".padEnd(4);
vnames.forEach(function (v) { header += v.slice(0, COL - 1).padEnd(COL); });
console.log(header);
console.log("-".repeat(header.length));

pool.forEach(function (mon) {
  var line = mon.Name.padEnd(18) + String(mon.DV).padEnd(4);
  vnames.forEach(function (v) {
    var wins = 0, rsum = 0, to = 0;
    for (var i = 0; i < N; i++) {
      var r = fight(Object.assign({}, mon), VARIANTS[v]);
      if (r.won) { wins++; rsum += r.rounds; }
      if (r.timeout) to++;
    }
    var cell;
    if (wins === 0) cell = "0%";
    else cell = (100 * wins / N).toFixed(0) + "%/" + (rsum / wins).toFixed(1) + "r" + (to ? " *" + to + "*" : "");
    line += cell.padEnd(COL);
  });
  console.log(line);
});
console.log("");
console.log("(win% / avg rounds when the hero wins; *n* = N encounters that hit the 500-round safety valve)");
