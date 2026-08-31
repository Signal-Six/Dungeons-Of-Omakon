// Combat.js — damage and accuracy resolution. Pure UI-free.
// Injected by Panel.qml's runtime; formulas per the user's spec:
//
//   ACC = Sum(accuracy bonuses) + DEX
//   hit iff ACC >= monster.DV
//   on hit: DAM = Sum(damage bonuses) + STR + d4   (rolled at runtime)
//
// Player defense (agreed 2026-08-24) mirrors the attack formula:
//   DV  = 10 + DEX + Σ equipped Defense(+Enchant)
//   MDV = 10 + WIL + Σ equipped Defense(+Enchant) — ONLY from enchanted gear
// A monster with isMagic attacks MDV instead of DV. The enchant flag is
// both gate and bonus for MDV: a plain Kite Shield gives MDV nothing;
// a +1 Kite Shield contributes 10+1 = 11.
//
// All sums take the fully-resolved stat contribution from every equipped
// item, activated effect, and intrinsic source — so a sword contributes its
// acc + dmg, a ring contributing +1 ACC contributes only its acc, etc.
// STR and DEX are character stats; Phase 5 will wire them in.
//
// Defense contributions arrive pre-resolved by the caller: a defense source
// is { def: <Defense+Enchant already summed>, enchanted: <bool> } so this
// module stays free of equipment.json lookups.

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
  if (state.leftHand) out.push(state.leftHand);   // shield slot
  if (state.armor) out.push(state.armor);         // body armor
  if (state.helmet) out.push(state.helmet);       // helmet
  if (state.amulet) out.push(state.amulet);       // amulet (never enchanted)
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

// Summed Defense from equipped sources. Each source contributes its `def`
// always toward DV, and toward MDV only when `enchanted` is truthy.
function defenseSums(state) {
  var dv = 0, mdv = 0;
  var srcs = equippedSources(state);
  for (var i = 0; i < srcs.length; i++) {
    var s = srcs[i];
    var d = (s && typeof s.def === "number") ? s.def : 0;
    dv += d;
    if (s && s.enchanted) mdv += d;
  }
  return { dv: dv, mdv: mdv };
}

// Player DV / MDV per the 2026-08-24 formula: 10 + stat + Σ defense.
function playerDefense(state) {
  var sums = defenseSums(state);
  return {
    dv: 10 + (state.dex || 0) + sums.dv,
    mdv: 10 + (state.wil || 0) + sums.mdv
  };
}

// Monster attack against the player. monster = { acc|accuracy, dmg|damage,
// isMagic }. acc/dmg may be numbers (fixed) — dice live on the caller's
// side (the monster table owns its own roll notation). rng optional.
// Returns { hit, target ("DV"|"MDV"), threshold, acc, damage? }
function defend(state, monster, rng) {
  var magic = !!monster.isMagic;
  var pd = playerDefense(state);
  var threshold = magic ? pd.mdv : pd.dv;
  var acc = (typeof monster.acc === "number") ? monster.acc
          : (typeof monster.accuracy === "number") ? monster.accuracy : 0;
  if (acc < threshold) {
    return { hit: false, target: magic ? "MDV" : "DV",
             threshold: threshold, acc: acc };
  }
  var dmg = (typeof monster.dmg === "number") ? monster.dmg
          : (typeof monster.damage === "number") ? monster.damage : 0;
  return { hit: true, target: magic ? "MDV" : "DV",
           threshold: threshold, acc: acc, damage: dmg };
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
    accuracyOf: accuracyOf, baseDamageOf: baseDamageOf, attack: attack,
    defenseSums: defenseSums, playerDefense: playerDefense, defend: defend
  };
}
