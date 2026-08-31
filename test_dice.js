// test_dice.js — node test run (no harness, assertion-driven).
var D = require("./Dice.js");
var assert = require("assert");

// Parse shapes
assert.deepStrictEqual(D.parse("50"), [{ const: 50 }]);
assert.deepStrictEqual(D.parse("5+1d10"), [{ const: 5 }, { n: 1, sides: 10 }]);
assert.deepStrictEqual(D.parse("2d10+2d6"), [{ n: 2, sides: 10 }, { n: 2, sides: 6 }]);
assert.deepStrictEqual(D.parse("1d4"), [{ n: 1, sides: 4 }]);
assert.strictEqual(D.parse("infinite"), Infinity);

// Bounds over a fixed rng (deterministic: cycle 0,0.25,0.5,0.75)
var seq = [0, 0.25, 0.5, 0.75], i = 0;
var rng = function () { return seq[(i++) % seq.length]; };
for (var k = 0; k < 1000; k++) {
  var v = D.roll("2d10+2d6", rng);
  assert(v >= 4 && v <= 32, "2d10+2d6 out of range: " + v);
  assert(D.roll("5+1d10", rng) >= 6 && D.roll("5+1d10", rng) <= 15);
}
assert.strictEqual(D.roll("infinite", rng), Infinity);
assert.strictEqual(D.roll(50, rng), 50);

// Distribution sanity on 1d10 with seeded LCG
var seed = 42;
function lcg() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x80000000; }
var counts = [0,0,0,0,0,0,0,0,0,0,0];
for (var t = 0; t < 100000; t++) counts[D.roll("1d10", lcg)]++;
for (var face = 1; face <= 10; face++)
  assert(Math.abs(counts[face] - 10000) < 1000, "1d10 skewed face " + face + ": " + counts[face]);

// Bad input throws (no silent zeros)
assert.throws(function () { D.parse("d"); });
assert.throws(function () { D.parse("1d1d10"); });

console.log("test_dice.js OK");
