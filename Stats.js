// Stats.js — character stat progression. Pure logic; Panel.qml feeds
// it events and reads its state.
//
// Spec:
//   * Stats: STR, DEX, CON, INT, WIL — start at 4 each (20-point split).
//   * Every 100 EXP: +1 level. No cap.
//   * Every 2 levels (2, 4, 6, ...) the player gains 1 bonus point to assign
//     via a small popup.
//   * Attack math already lives in Combat.js; Stats exposes it as
//     primaryStats() for persistence + formulas that need them.

var BASE = 4;

function freshStats() {
  return { str: BASE, dex: BASE, con: BASE, int: BASE, wil: BASE, unspent: 0 };
}

// Avoid pathological inflation: cap level at 200 (Level 200 requires
// ~200 * 100 = 20,000 EXP which is plausible across a very long run but
// *any* corruption at higher levels would destroy the save anyway).
var LEVEL_CAP = 200;

// EXP -> level. Level 1 = [0,100), Level 2 = [100,200), ...
// Returns { level, levelsGained } for chaining into allocation.
function levelFromXp(xp) {
  var l = Math.max(1, Math.floor((xp || 0) / 100) + 1);
  return Math.min(l, LEVEL_CAP);
}

// Add EXP, return the new level and whether the player has stat points
// to assign (every 2 levels starting at level 2).
function addXp(stats, current, xp) {
  var xpNext = (current.xp || 0) + xp;
  var level = levelFromXp(xpNext);
  var prev = current.level || 1;
  var levelsGained = Math.max(0, level - prev);
  // Bonus point per *even* level entered (2, 4, 6, ...) per the design.
  var evenCount = Math.floor(level / 2) - Math.floor(prev / 2);
  var unspent = (stats.unspent || 0) + evenCount;
  var next = {};
  for (var k in stats) next[k] = stats[k];
  next.unspent = unspent;
  return {
    xp: xpNext, level: level,
    stats: next,
    levelsGained: levelsGained
  };
}

// Assign a bonus point. stat must be one of the five keys.
function assignPoint(stats, stat) {
  if (stats.unspent <= 0) return stats;
  if (!(stat in stats) || stat === "unspent") return stats;
  var next = {};
  for (var k in stats) next[k] = stats[k];
  next[stat] = (next[stat] || 0) + 1;
  next.unspent--;
  return next;
}

// Derived combat stats against a monster (Combat.js still does the rest).
function primaryStats(stats) {
  return {
    str: stats.str || 0,
    dex: stats.dex || 0,
    int: stats.int || 0,
    wil: stats.wil || 0
  };
}

// Max HP/MP using the simplified linear curves per the design.
//   maxHP = 20 + CON + level   (start: 4 CON, level 1 → 25)
//   maxMP = 10 + INT + level   (start: 4 INT, level 1 → 15)
function hpMax(stats, level) {
  return 20 + (stats.con || 0) + level;
}
function mpMax(stats, level) {
  return 10 + (stats.int || 0) + level;
}
function magicDefense(stats) {
  return (stats.wil || 0) * 2;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    BASE: BASE, LEVEL_CAP: LEVEL_CAP,
    freshStats: freshStats, levelFromXp: levelFromXp,
    addXp: addXp, assignPoint: assignPoint,
    primaryStats: primaryStats,
    hpMax: hpMax, mpMax: mpMax, magicDefense: magicDefense
  };
}
