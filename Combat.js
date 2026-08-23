// Combat.js — damage and accuracy resolution. Pure UI-free.
// Injected by Panel.qml's runtime; formulas per the user's spec:
//
//   ACC = Sum(accuracy bonuses) + DEX
//   hit iff ACC >= monster.DV
//   on hit: DAM = Sum(damage bonuses) + STR + d4   (rolled at runtime)
//
// All sums take the fully-resolved stat contribution from every equipped
// item, activated effect, and intrinsic source — so a sword contributes its
// acc + dmg, a ring contributing +1 ACC contributes only its acc, etc.
// STR and DEX are character stats; Phase 5 will wire them in.

function rollD4(rng) {
  // rng is either undefined (fall back to Math.random) or a function
  // producing [0,1). Keep deterministic test seeds possible.
  var r = rng ? rng() : Math.random();
  return 1 + Math.floor(r * 4);
}

// Sum a single stat key over an array of item/effort sources. Each source
// is either null, a number, or an object with the stat under a recognisable
// key (primary field, "bonus", or "acc"/"dmg" as applicable).
function sumStat(sources, key) {
  var total = 0;
  for (var i = 0; i < sources.length; i++) {
    var s = sources[i];
    if (s === null || s === undefined) continue;
    if (typeof s === "number") { total += s; continue; }
    var v = s[key];
    if (typeof v === "number") total += v;
    else if (v && typeof v.bonus === "number") total += v.bonus;
    else if (v && typeof v[key] === "number") total += v[key];
  }
  return total;
}

// Equipment list the player actually has equipped (hands + worn slots).
// Phase 5 will add worn accessories; for now we take anything passed in.
function equippedSources(state) {
  var out = [];
  if (state.rightHand) out.push(state.rightHand);
  if (state.leftHand) out.push(state.leftHand);
  var worn = state.worn || [];
  for (var i = 0; i < worn.length; i++) if (worn[i]) out.push(worn[i]);
  // Active/status effects (spells, poison, rage, ...) contribute too.
  var buffs = state.effects || [];
  for (var j = 0; j < buffs.length; j++) if (buffs[j]) out.push(buffs[j]);
  return out;
}

function accuracyOf(state) {
  return sumStat(equippedSources(state), "acc") + (state.dex || 0);
}

function baseDamageOf(state) {
  return sumStat(equippedSources(state), "dmg") + (state.str || 0);
}

// Full attack resolution against a monster. rng is optional (tests pass one).
// Returns { hit, accuracy, damage?, d4?, rollBreakdown }
function attack(state, monster, rng) {
  var acc = accuracyOf(state);
  if (acc < (monster.dv || 0)) {
    return { hit: false, accuracy: acc, dv: monster.dv || 0 };
  }
  var base = baseDamageOf(state);
  var d4 = rollD4(rng);
  return {
    hit: true, accuracy: acc, dv: monster.dv || 0,
    baseDamage: base, d4: d4, damage: base + d4
  };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    rollD4: rollD4, sumStat: sumStat, equippedSources: equippedSources,
    accuracyOf: accuracyOf, baseDamageOf: baseDamageOf, attack: attack
  };
}
