// Poison.js — post-combat poison state for Dungeons of Omakon. Pure logic,
// node-testable like Combat.js / Dungeon.js. No QML imports.
//
// Design (2026-09-01, user-confirmed table semantics):
//   * A poison-capable monster's Fight marks the hero on the first
//     successful hit ("You feel poison coursing through your veins!").
//   * The status takes hold when the fight ends: the Panel hands the
//     monster's PoisonDamage here via start().
//   * Damage ticks on TILE MOVES ONLY — never on turning, never on wall
//     bumps. Ticks run their course over 5 tile moves (skill doc:
//     "lingers 5 tile-moves post-kill, turning doesn't tick").
//   * Each tick deals the flat PoisonDamage from the monster table.
//   * Lucid Crystal (equipped amulet whose Description contains
//     "prevents the user from being poisoned") blocks START only — a
//     poison already coursing keeps coursing if the amulet comes off,
//     matching the prose. Antidote ("cures poison") clears the state.

var DURATION = 5;   // tile-moves the status lasts

// Begin poisoning. dmg = the monster's PoisonDamage (flat per tick).
// Returns the state object the Panel should keep on heroPoison.
function start(dmg) {
  return { dmg: dmg, movesLeft: DURATION };
}

// Advance one tile move. state = { dmg, movesLeft } or null.
// Returns { state, damage, done } — `damage` is the HP to subtract this
// move (0 when not poisoned), `done` true when this tick expired the
// status (last move consumed). Caller applies damage, logs, checks death.
function tick(state) {
  if (!state) return { state: null, damage: 0, done: false };
  var damage = state.dmg;
  var left = state.movesLeft - 1;
  return { state: left > 0 ? { dmg: state.dmg, movesLeft: left } : null,
           damage: damage, done: left <= 0 };
}

// True when an equipped amulet instance's table prose grants poison
// immunity. resolveInstance is Panel-side; this takes the raw Description.
function isImmune(amuletDescription) {
  return !!amuletDescription
    && /prevents the user from being poisoned/i.test(amuletDescription);
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    DURATION: DURATION,
    start: start,
    tick: tick,
    isImmune: isImmune
  };
}
