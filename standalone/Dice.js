// Dice.js — parse and roll the dice expressions used across the game:
// monsters.json ACC/DAMAGE strings ("5+1d10", "2d10+2d6", flat "50") and
// any future player-side dice. Pure logic, node-testable like Dungeon.js.
//
// Grammar (whitespace-insensitive, left-to-right):
//   expr    := term (('+'|'-') term)*
//   term    := [count] 'd' sides | integer
// The string "infinite" is passed through as Infinity — equipment.json
// uses it intentionally (Book of Power accuracy, Sapien Cannon damage).
//
// roll(expr, rng) → integer total, rolling each term left-to-right.
// rollDetail(expr, rng) → { total, rolls: [{n, sides, dice:[..]}] } for
// combat-log flavour text ("4+1d10 = 9").

function isInfinite(expr) {
  return typeof expr === "string" && expr.trim().toLowerCase() === "infinite";
}

// Parse into [{n, sides} | integerTerm]. Throws on garbage — better to
// explode loudly in tests than silently roll 0 in the game.
function parse(expr) {
  if (isInfinite(expr)) return Infinity;
  if (typeof expr === "number") return [{ const: expr }];
  var s = String(expr).replace(/\s+/g, "");
  if (s === "") throw new Error("Dice.parse: empty expression");
  // Tokenize: sign stays attached to its term.
  var parts = s.match(/[+-]?[^+-]+/g);
  if (!parts) throw new Error("Dice.parse: cannot parse '" + expr + "'");
  var terms = [];
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i];
    var m = p.match(/^([+-]?)(\d*)d(\d+)$/i);
    if (m) {
      var sign = m[1] === "-" ? -1 : 1;
      var n = m[2] === "" ? 1 : parseInt(m[2], 10);
      var sides = parseInt(m[3], 10);
      if (n < 1 || sides < 1) throw new Error("Dice.parse: bad term '" + p + "'");
      terms.push({ n: sign * n, sides: sides });
      continue;
    }
    var c = p.match(/^([+-]?\d+)$/);
    if (c) { terms.push({ const: parseInt(c[1], 10) }); continue; }
    throw new Error("Dice.parse: bad term '" + p + "'");
  }
  return terms;
}

function rollDiceTerm(rng, sides) {
  return 1 + Math.floor(rng() * sides);
}

// Roll a parsed-or-string expression. rng optional (Math.random default).
function roll(expr, rng) {
  rng = rng || Math.random;
  if (isInfinite(expr)) return Infinity;
  var terms = (typeof expr === "object" && expr.length !== undefined)
    ? expr : parse(expr);
  var total = 0;
  for (var i = 0; i < terms.length; i++) {
    var t = terms[i];
    if (t.const !== undefined) { total += t.const; continue; }
    var n = t.n, sides = t.sides;
    var sign = n < 0 ? -1 : 1;
    for (var d = 0; d < Math.abs(n); d++) total += sign * rollDiceTerm(rng, sides);
  }
  return total;
}

// Roll with a breakdown for log text. detail.dice[i] = per-die values.
function rollDetail(expr, rng) {
  rng = rng || Math.random;
  var terms = parse(expr);
  if (terms === Infinity) return { total: Infinity, dice: [], expr: "infinite" };
  var total = 0, dice = [];
  for (var i = 0; i < terms.length; i++) {
    var t = terms[i];
    if (t.const !== undefined) { total += t.const; dice.push({ const: t.const }); continue; }
    var rolls = [], sign = t.n < 0 ? -1 : 1;
    for (var d = 0; d < Math.abs(t.n); d++) {
      var r = rollDiceTerm(rng, t.sides);
      rolls.push(r); total += sign * r;
    }
    dice.push({ n: t.n, sides: t.sides, rolls: rolls });
  }
  return { total: total, dice: dice, expr: String(expr) };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { parse: parse, roll: roll, rollDetail: rollDetail,
                     isInfinite: isInfinite };
}
