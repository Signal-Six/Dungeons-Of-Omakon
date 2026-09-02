// Enchant.js — purify for the Scroll of Enchantment effect. Pure logic, no
// Qt imports; everything the Panel does with it is read-only data shaping.
//
// The scroll's Effect row in equipment.json is authoritative:
//   { type: "enchant", targets: ["Weapon","Shield","Helmet","Armor"], amount: 1 }
// Amount is a flat addition to the instance's Enchant flag (undefined == 0;
// Enchant lives on the pack INSTANCE, not the equipment row). The scroll's
// own +N stacks: re-enchanting an already Enchanted item bumps it further.
//
// Target eligibility is by the equipment row's Type field, matched exactly
// (case-sensitive; the curated table uses these exact tokens).

function targetsFor(effectRow) {
  if (!effectRow || !effectRow.Effect) return []
  return effectRow.Effect.targets || []
}

// Is the given equipment row a legal enchantee under the effect?
function isEligible(effectRow, equipRow) {
  if (!effectRow || !equipRow) return false
  var wants = targetsFor(effectRow)
  for (var i = 0; i < wants.length; i++)
    if (equipRow.Type === wants[i]) return true
  return false
}

// Apply the enchant increment to a pack instance (mutates a copy).
// Instance shape: { Name, Enchant? }. Current Enchant udef -> 0.
function apply(nstance, effectRow) {
  var next = {}
  for (var k in nstance) next[k] = nstance[k]
  next.Enchant = (next.Enchant || 0) + (effectRow.Effect.amount || 1)
  return next
}

// Build the pick list over a pack (filter nulls, keep pack indices).
function candidates(pack, equipTable, effectRow) {
  var out = []
  for (var i = 0; i < pack.length; i++) {
    var inst = pack[i]
    if (!inst) continue
    var row = null
    for (var j = 0; j < equipTable.length; j++)
      if (equipTable[j].Name === inst.Name) { row = equipTable[j]; break }
    if (!row) continue
    if (!isEligible(effectRow, row)) continue
    out.push({ index: i, name: inst.Name, currentEnchant: inst.Enchant || 0 })
  }
  return out
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    targetsFor: targetsFor,
    isEligible: isEligible,
    apply: apply,
    candidates: candidates
  }
}
