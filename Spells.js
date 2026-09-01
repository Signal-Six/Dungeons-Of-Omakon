// Spells.js — spell casting, active-spell durations, and effect dispatch
// for Dungeons of Omakon. Pure logic, node-testable. No QML imports.
//
// Spell data lives in spells.json (built from spells.csv by build_spells.js).
// A learned spell is just the row: {Name, Damage, Duration, Cost, Effect,
// Description, Rank, Icon}.
//
// An ACTIVE spell (post-cast state for duration-bearing casts) is a plain
// object: { name, def: <spell row>, stepsLeft, custom: {...} }.
// Duration semantics (2026-09-01, user-confirmed):
//   * stepsLeft decrements on TILE MOVES out of combat, and on PLAYER
//     ACTIONS (rounds) in combat. Turning never ticks.
//   * Durations lock their value at cast: "INT/2" evaluates with the
//     INT the hero has at cast time, and that value persists.
//   * Flyer Fins' "two tiles per move" still consumes ONE step per
//     move click — the tick is per move action, not per tile.
//
// Damage/Duration expressions in spells.json may reference INT:
//   "1d4+INT", "1d12+(INT/2)", "2d10", "INT/4", ...
// We substitute a bare "INT" term with the hero's current INT and defer
// to Dice for everything else. The "(INT/n)" pattern appears inside
// parens — we evaluate those as integer division.

var Dice = (typeof require !== "undefined") ? require("./Dice.js") : Dice;

// Substitute INT references in a spell expression and roll/eval it.
//   rollFormula("1d4+INT", 8)         -> Dice.roll("1d4+8")
//   rollFormula("1d12+(INT/2)", 8)    -> Dice.roll("1d12+4")
//   rollFormula("INT/4", 8)           -> 2   (pure INT arithmetic, no dice)
// Returns an integer (floor division for the / terms), or Infinity for
// "infinite".
function rollFormula(expr, int, rng) {
  if (expr === null || expr === undefined || expr === "") return 0;
  var s = String(expr);
  if (/^infinite$/i.test(s.trim())) return Infinity;
  // Evaluate (INT/n) occurrences first, as floor division.
  s = s.replace(/\(\s*INT\s*\/\s*(\d+)\s*\)/gi, function (_, n) {
    return String(Math.floor(int / parseInt(n, 10)));
  });
  // Bare INT (not part of a longer identifier) → the stat.
  s = s.replace(/\bINT\b/gi, String(int));
  // Pure arithmetic (post-substitution): e.g. "8/4" left over from
  // INT/4 with no parens. Only if no dice remain.
  //
  // eval() is safe here: the regex immediately above whitelists input to
  // digits, arithmetic operators, parens, and whitespace (no letters, no
  // identifiers). The expression itself comes from our own spells.csv —
  // not runtime user input.
  if (!/\d+d\d+/i.test(s) && /[\/+*-]/.test(s)) {
    if (!/^[0-9+\-*/() \t]+$/.test(s)) throw new Error("bad spell expr: " + expr);
    // eslint-disable-next-line no-eval
    return Math.floor(eval(s));
  }
  // Dice.roll handles final arithmetic after dice resolution; it
  // doesn't do "/", so the only remaining / was substituted above.
  if (/\//.test(s)) {
    if (!/^[0-9+\-*/() \t]+$/.test(s)) throw new Error("bad spell expr: " + expr);
    // eslint-disable-next-line no-eval
    return Math.floor(eval(s));
  }
  return Dice.roll(s, rng);
}

// Classify a spell for cast-time behavior. Purely a read of Effect prose
// + Damage/Duration fields; keep the tags stable for Panel dispatch.
// Returns one of:
//   "damage"   — hits the monster, uses Damage formula (in combat only)
//   "heal"     — heals hero, uses Damage formula as the heal amount
//   "buff"     — pushes an active spell (uses Duration formula)
//   "blink"    — enters targeting mode (Blink special)
//   "special"  — needs bespoke handling (Slip, Imbibe Luck)
function classify(spell) {
  var d = (spell.Effect || "").toLowerCase();
  var dmg = spell.Damage, dur = spell.Duration;
  var name = spell.Name;
  if (name === "Blink") return "blink";
  if (/restore .* health/.test(d)) return "heal";
  // damage spells have a Damage formula and no Duration.
  if (dmg && dmg !== "0" && (!dur || dur === "0")) return "damage";
  // buffs have a Duration.
  if (dur && dur !== "0") return "buff";
  return "special";
}

// Create an active-spell instance at cast time. duration evaluated with
// current INT and locked in.
function activate(spell, int, rng) {
  var dur = spell.Duration;
  var steps = (dur && dur !== "0") ? rollFormula(dur, int, rng) : 0;
  return {
    name: spell.Name,
    def: spell,
    stepsLeft: steps,
    custom: {}
  };
}

// Tick all active spells one unit. Returns { active, expired } where
// `expired` is the array of actives whose duration ran out this tick.
function tickAll(actives) {
  var keep = [], expired = [];
  for (var i = 0; i < actives.length; i++) {
    var a = actives[i];
    if (a.stepsLeft <= 0) { keep.push(a); continue }   // indefinite
    var next = { name: a.name, def: a.def, stepsLeft: a.stepsLeft - 1,
                 custom: a.custom };
    if (next.stepsLeft <= 0) expired.push(next); else keep.push(next);
  }
  return { active: keep, expired: expired };
}

// Convenience lookups -------------------------------------------------------

function findByName(spells, name) {
  for (var i = 0; i < spells.length; i++)
    if (spells[i].Name === name) return spells[i];
  return null;
}

// In the save, activeSpells must be serialized (stepsLeft + custom).
function serializeActives(actives) {
  return actives.map(function (a) {
    return { Name: a.name, stepsLeft: a.stepsLeft, custom: a.custom };
  });
}
function reviveActives(saved, spells) {
  var out = [];
  for (var i = 0; i < (saved || []).length; i++) {
    var s = saved[i];
    var def = findByName(spells, s.Name);
    if (!def) continue;
    out.push({ name: s.Name, def: def,
               stepsLeft: s.stepsLeft || 0, custom: s.custom || {} });
  }
  return out;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    rollFormula: rollFormula,
    classify: classify,
    activate: activate,
    tickAll: tickAll,
    findByName: findByName,
    serializeActives: serializeActives,
    reviveActives: reviveActives
  };
}
