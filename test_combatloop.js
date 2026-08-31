// test_combatloop.js — node: CombatLoop lifecycle assertions.
var CL = require("./CombatLoop.js");
var Stats = require("./Stats.js");
var assert = require("assert");

// Fixed rng helper: returns `vals` cyclically. Every rng() call consumes one.
function cycler(vals) {
  var i = 0;
  return function () { return vals[(i++) % vals.length]; };
}

var ratRow = {
  HP: 5, DV: 5, EXP: 10, DAMAGE: "1d4", ACC: "5+1d10",
  isMagic: 0, isPoison: 0, PoisonDamage: null, Name: "Rat"
};
// Fresh-man state: str 4 dex 4, weapon { acc: 1, dmg: 1 } (Rusty Sword).
var state = {
  str: 4, dex: 4,
  rightHand: { acc: 1, dmg: 1 },
  leftHand: null, worn: [], effects: []
};

// 1. Player-first kill: rat has 5hp; sword dmg = 1+4+d4 = 6..9 → one-round kill.
var loop = CL.newEncounter(ratRow);
CL.round(loop, state, "Rusty Sword", cycler([0.9, 0.9]));  // d4=4, d4 unused
assert(loop.over && loop.won, "rat should die in one hit");
assert.strictEqual(loop.monster.hp <= 0, true);
assert(loop.log.some(function (l) { return l.indexOf("dies") >= 0; }));

// 2. Miss when accuracy too low. Cycler zeros → d4=1 min etc. state.acc=5+... DV=20.
var loop2 = CL.newEncounter({
  HP: 50, DV: 99, EXP: 1, DAMAGE: "1d4", ACC: "1+1d4",
  isMagic: 0, isPoison: 0, PoisonDamage: null, Name: "Wall"
});
CL.round(loop2, state, "Rusty Sword", cycler([0.5, 0.5, 0.5, 0.5]));
assert(!loop2.over && !loop2.won, "should not kill the wall");
assert(loop2.log.some(function (l) { return /miss/.test(l); }), "miss logged");

// 3. Monster retaliates only while alive. One-round kill → no retal log.
assert(!loop.log.some(function (l) { return /hits you/.test(l); }),
       "dead rat shouldn't retaliate");

// 4. Retaliation happens when the monster survives.
var loop4 = CL.newEncounter({
  HP: 100, DV: 1, EXP: 1, DAMAGE: "2", ACC: "100",
  isMagic: 0, isPoison: 0, PoisonDamage: null, Name: "Tank"
});
CL.round(loop4, state, "Rusty Sword", cycler([0.5, 0.5, 0.5]));
assert(!loop4.over, "tank survives");
assert(loop4.log.some(function (l) { return /hits you for 2 damage/.test(l); }),
       "tank retaliate logged");
assert.strictEqual(loop4.lastMonsterDamage, 2);

// 5. Magic attack targets MDV.
var loop5 = CL.newEncounter({
  HP: 100, DV: 1, EXP: 1, DAMAGE: "3", ACC: "100",
  isMagic: 1, isPoison: 0, PoisonDamage: null, Name: "Mage"
});
CL.round(loop5, state, "Rusty Sword", cycler([0.5, 0.5, 0.5]));
assert(/magic/.test(loop5.log.join(" ")), "magic note in log");
assert.strictEqual(loop5.lastMonsterTarget, "MDV");

// 6. Poison note fires once.
var loop6 = CL.newEncounter({
  HP: 100, DV: 1, EXP: 1, DAMAGE: "1", ACC: "100",
  isMagic: 0, isPoison: 1, PoisonDamage: 4, Name: "Spitter"
});
state2 = state;
CL.round(loop6, state2, "Rusty Sword", cycler([0.5, 0.5, 0.5]));
CL.round(loop6, state2, "Rusty Sword", cycler([0.5, 0.5, 0.5]));
var poisonNotes = loop6.log.filter(function (l) { return /poison coursing/.test(l); });
assert.strictEqual(poisonNotes.length, 1, "poison note exactly once");

// 7. Infinite-accuracy weapon (Book of Power → acc Infinity) always hits.
var state7 = { str: 0, dex: 0, rightHand: { acc: Infinity, dmg: 1 },
               leftHand: null, worn: [], effects: [] };
var loop7 = CL.newEncounter({
  HP: 2, DV: 9999, EXP: 1, DAMAGE: "0", ACC: "0",
  isMagic: 0, isPoison: 0, PoisonDamage: null, Name: "Shade"
});
CL.round(loop7, state7, "Book of Power", cycler([0.5, 0.5]));
assert(loop7.won, "infinite accuracy always connects");
// Infinite damage (Sapien Cannon): overflow kills.
var state8 = { str: 0, dex: 0, rightHand: { acc: 50, dmg: Infinity },
               leftHand: null, worn: [], effects: [] };
var loop8 = CL.newEncounter({
  HP: 10, DV: 1, EXP: 1, DAMAGE: "0", ACC: "0",
  isMagic: 0, isPoison: 0, PoisonDamage: null, Name: "Blob"
});
CL.round(loop8, state8, "Sapien Cannon", cycler([0.5, 0.5]));
assert(loop8.won, "infinite damage one-shots");
assert(loop8.log.some(function (l) { return l.indexOf("∞") >= 0; }),
       "∞ shows in log");

console.log("test_combatloop.js OK");
