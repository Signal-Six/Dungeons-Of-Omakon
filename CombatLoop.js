// CombatLoop.js — encounter lifecycle for Dungeons of Omakon. Pure logic,
// node-testable like Dungeon.js / Combat.js. UI-free: the Panel drives it
// one click at a time and reads `log` for display.
//
// Rules (design decisions 2026-08-31):
//   * Player acts first every round; the monster retaliates ONLY if it
//     survives the hit (no simultaneous exchange).
//   * No fleeing — every encounter runs to a resolution.
//   * Player strike = Combat.attack(combatState, monster): ACC =
//     Σacc + DEX vs monster DV; damage = Σdmg + STR + 1d4. The d4 is
//     already inside Combat; rng is passed through for determinism.
//   * Equipment with "infinite" Accuracy (Book of Power) never misses;
//     "infinite" Damage (Sapien Cannon) is handled by seesawing through
//     Combat.attack's Infinity comparisons — both fields ride as numbers
//     here (JSON parse turns them into null! so the Panel must convert
//     the string "infinite" to Infinity when resolving instances. See
//     resolveInstance below — it owns that conversion.)
//   * Monster retaliation = roll(ACC string) vs DV or MDV (isMagic),
//     damage = roll(DAMAGE string) on hit. Poison: isPoison hit appends a
//     log note; damage ticks live in the later movement-tick system.
//
// A loop is a plain object so the save system (if it ever snapshots it)
// can JSON-serialize it directly:
//   { monster: { ...tableRow, hp, hpMax, acc, damage },
//     round, log: [strings], over, won, killedBy }
// acc/damage on the loop monster are the RAW strings, rolled each round.

var Combat = (typeof require !== "undefined") ? require("./Combat.js") : Combat;
var Dice   = (typeof require !== "undefined") ? require("./Dice.js")   : Dice;

function newEncounter(row) {
  // row = a monsters.json entry (HP, DV, EXP, DAMAGE, ACC as strings, ...)
  return {
    monster: {
      name: row.Name, icon: row.Icon, color: row.Color,
      dv: row.DV, xp: row.EXP,
      accExpr: row.ACC, damageExpr: row.DAMAGE,
      isMagic: !!row.isMagic, isPoison: !!row.isPoison,
      poisonDamage: row.PoisonDamage || 0,
      hp: row.HP, hpMax: row.HP
    },
    round: 0,
    log: ["You encounter a " + row.Name + "!"],
    over: false, won: false,
    poisoned: false,           // poison was suffered at least once
    killedBy: null             // monster name when the player dies
  };
}

// Player strike. state = Combat.combatState() shape. rng optional.
// Mutates loop (new log entries, hp) and returns it for chaining UI.
function playerStrike(loop, state, weaponLabel, rng) {
  if (loop.over) return loop;
  loop.round++;
  var m = loop.monster;
  var res = Combat.attack(state, m, rng);
  var wlabel = weaponLabel || "your fists";
  if (!res.hit) {
    loop.log.push("You strike at the " + m.name + " with " + wlabel
      + " — miss. (ACC " + res.accuracy + "+2d6=" + res.accRoll + " vs DV " + res.dv + ")");
    return loop;
  }
  var dmg = res.damage;
  // Infinity damage (Sapien Cannon): prints as "∞" in the log.
  var dmgText = (dmg === Infinity) ? "∞" : String(dmg);
  var rollText = (res.d4 !== undefined && dmg !== Infinity)
    ? " (" + res.baseDamage + "+" + res.d4 + ")" : "";
  loop.log.push("You strike the " + m.name + " with " + wlabel + " for "
    + dmgText + " damage" + rollText + "!");
  m.hp = (dmg === Infinity) ? -Infinity : m.hp - dmg;
  if (m.hp <= 0) {
    loop.log.push("The " + m.name + " dies!");
    loop.over = true;
    loop.won = true;
  }
  return loop;
}

// Monster retaliation — call after playerStrike when !loop.over.
function monsterStrike(loop, state, rng) {
  if (loop.over) return loop;
  // Reset per-strike outputs so a miss never re-applies last round's damage.
  loop.lastMonsterDamage = 0;
  loop.lastMonsterTarget = null;
  var m = loop.monster;
  var accRoll = Dice.roll(m.accExpr, rng);
  // Combat.defend wants an already-rolled number; reuse its DV/MDV routing.
  var res = Combat.defend(state, {
    acc: accRoll, dmg: 0, isMagic: m.isMagic
  }, rng);
  if (!res.hit) {
    loop.log.push("The " + m.name + " attacks — misses. ("
      + accRoll + " vs " + res.target + " " + res.threshold + ")");
    return loop;
  }
  var dmgDetail = Dice.rollDetail(m.damageExpr, rng);
  loop.log.push("The " + m.name + " hits you for " + dmgDetail.total
    + " damage" + (m.isMagic ? " (magic)" : "") + "!");
  if (m.isPoison && !loop.poisoned) {
    loop.poisoned = true;
    loop.log.push("You feel poison coursing through your veins!");
  }
  loop.lastMonsterDamage = dmgDetail.total;   // Panel applies to heroHp
  loop.lastMonsterTarget = res.target;        // "DV" | "MDV"
  return loop;
}

// Full round helper: player strikes; if kill, done; else monster answers.
// Returns loop. Panel generally wants the two phases as separate clicks so
// the log animates — this is for tests and scripted runs.
function round(loop, state, weaponLabel, rng) {
  playerStrike(loop, state, weaponLabel, rng);
  if (!loop.over) monsterStrike(loop, state, rng);
  return loop;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    newEncounter: newEncounter,
    playerStrike: playerStrike,
    monsterStrike: monsterStrike,
    round: round
  };
}
