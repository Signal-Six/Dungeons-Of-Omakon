// test_enchant.js — Scroll of Enchantment logic against the real
// equipment.json. Exercises the gate (which Types are legal), the stacking,
// the null-pack filtering, and the identity-independence of Enchant.apply()
// (the pack has object identity, not name identity, so two same-name items
// are enchanted separately).
var Enchant = require("./Enchant.js")
var equipment = require("./equipment.json")

var fails = 0
function ok(c, m) { if (!c) { fails++; console.log("FAIL " + m) }
                    else console.log("ok  " + m) }

// Find the Scroll row.
var scroll = null
for (var i = 0; i < equipment.length; i++)
  if (equipment[i].Name === "Scroll of Enchantment") { scroll = equipment[i]; break }
ok(scroll !== null, "Scroll of Enchantment exists in the table")
ok(scroll && scroll.Effect && scroll.Effect.type === "enchant",
   "scroll carries Effect.type=enchant")
ok(scroll && JSON.stringify(scroll.Effect.targets) ===
   JSON.stringify(["Weapon", "Shield", "Helmet", "Armor"]),
   "scroll targets exactly Weapon/Shield/Helmet/Armor")
ok(scroll && scroll.Effect.amount === 1, "amount is +1")

// Gate behavior.
function byName(name) {
  for (var i = 0; i < equipment.length; i++)
    if (equipment[i].Name === name) return equipment[i]
  return null
}
ok(Enchant.isEligible(scroll, byName("Rusty Sword")),  "Weapon eligible")
ok(Enchant.isEligible(scroll, byName("Buckler") || byName("Wooden Shield")),
   "Shield eligible")
ok(!Enchant.isEligible(scroll, byName("Potion")),      "Item (Potion) not eligible")
ok(!Enchant.isEligible(scroll, byName("Antidote")),    "Item (Antidote) not eligible")
ok(!Enchant.isEligible(scroll, byName("Lucid Crystal")), "Amulet not eligible")
ok(!Enchant.isEligible(scroll, byName("Scroll of Enchantment")),
   "the scroll itself is not eligible")

// Stacking: Enchant.apply() flat-adds; undefined Enchant acts as 0.
var w = { Name: "Rusty Sword" }
var w1 = Enchant.apply(w, scroll)
ok(w1.Enchant === 1 && !("Enchant" in w),
   "first enchant produces Enchant=1, original untouched")
var w5 = Enchant.apply({ Name: "Rusty Sword", Enchant: 4 }, scroll)
ok(w5.Enchant === 5, "already-enchanted gear stacks to +5")

// Candidate enumeration.
var pack = [
  { Name: "Rusty Sword" },              // Weapon     -> eligible
  null,                                 // empty slot
  { Name: "Potion" },                   // Item       -> not
  { Name: "Buckler" },                  // Shield     -> eligible
  { Name: "Cloak" },                    // Armor? check row exists
  { Name: "Scroll of Enchantment" },    // Item       -> not
  { Name: "Cap" },                      // Helmet? check row exists
  { Name: "Lucid Crystal" },            // Amulet     -> not
  { Name: "Ring of Might" }             // Amulet? likely not eligible
]
var cands = Enchant.candidates(pack, equipment, scroll)
var names = cands.map(function (x) { return x.name })
ok(cands.length >= 2, "candidates include the Weapon and Shield at minimum")
ok(names.indexOf("Rusty Sword") >= 0, "Rusty Sword is a candidate")
ok(names.indexOf("Buckler") >= 0, "Buckler is a candidate")
ok(names.indexOf("Potion") < 0, "Items excluded")
ok(names.indexOf("Lucid Crystal") < 0, "Amulet excluded")
ok(names.indexOf("Scroll of Enchantment") < 0, "scroll is not its own target")
ok(cands.every(function (c) { return c.currentEnchant === 0 }),
   "fresh instances start at currentEnchant=0 in the picker")

// Identity: two Rusty Swords enchant independently.
var pack2 = [{ Name: "Rusty Sword" }, { Name: "Rusty Sword" }]
var out = Enchant.candidates(pack2, equipment, scroll)
ok(out.length === 2, "two identical names both listed")
ok(out[0].index !== out[1].index, "each maps to its own pack slot")

// Edge: an empty pack row yields an empty picker.
var empty = Enchant.candidates([null, null, null], equipment, scroll)
ok(empty.length === 0, "empty pack -> empty candidates")

console.log(fails === 0 ? "ALL PASS" : fails + " FAILURES")
process.exit(fails === 0 ? 0 : 1)
