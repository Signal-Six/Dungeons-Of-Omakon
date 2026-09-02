// test_flee.js — flee formula anchor points + clamping.
// Run: node test_flee.js
var CombatLoop = require("./CombatLoop.js");
var assert = require("assert");

function close(a, b, msg) {
  if (Math.abs(a - b) > 1e-9) {
    console.error("FAIL " + msg + ": got " + a + ", want " + b); process.exit(1);
  }
  console.log("ok " + msg);
}

close(CombatLoop.fleeChance(4), 0.25, "DEX 4 -> 25% (anchor)");
close(CombatLoop.fleeChance(8), 0.45, "DEX 8 -> 45%");
close(CombatLoop.fleeChance(12), 0.25 + 0.2 * Math.log2(3), "DEX 12 log2 curve");
close(CombatLoop.fleeChance(16), 0.65, "DEX 16 -> 65%");
close(CombatLoop.fleeChance(32), 0.85, "DEX 32 -> 85%");
assert.strictEqual(CombatLoop.fleeChance(64), 0.999, "DEX 64 clamped at 99.9%");
assert.strictEqual(CombatLoop.fleeChance(0), 0.05, "DEX 0 clamped at 5%");
assert.strictEqual(CombatLoop.fleeChance(100), 0.999, "DEX 100 clamped at 99.9%");
console.log("8/8 flee-chance checks passed");
