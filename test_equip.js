#!/usr/bin/env node
// test_equip.js — equipment slot logic. Mirrors the Panel.qml equip/unequip/
// consumable function bodies (QML can't be run under node here — same
// replication approach as test_encounter.js) against the REAL equipment.json.
// Run: node test_equip.js
const Equipment = require("./equipment.json")
const Combat = require("./Combat.js")

let failures = 0
function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + " " + name)
  if (!ok) failures++
}
function firstCodePoint(s) {
  if (!s.length) return ""
  var c0 = s.charCodeAt(0)
  if (c0 >= 0xD800 && c0 <= 0xDBFF && s.length > 1) {
    var c1 = s.charCodeAt(1)
    if (c1 >= 0xDC00 && c1 <= 0xDFFF) return s.substring(0, 2)
  }
  return s.charAt(0)
}

// Harness: same state shape as the Panel root; the functions below are
// transcribed from Panel.qml — keep them in sync.
function makeHero() {
  var g = {
    equipmentTable: Equipment,
    pack: new Array(12).fill(null),
    leftHand: null,
    // New-game invariant: the starter sword lives in slot 0, equipped.
    rightHand: { Name: "Rusty Sword" },
    worn: { armor: null, helmet: null, amulet: null },
    heroStats: { str: 4, dex: 4, con: 4, int: 4, wil: 4 },
    heroHp: 25, heroHpMax: 25, heroMp: 15, heroMpMax: 15,
    heroEffects: [], saves: 0
  }
  g.saveRun = function () { g.saves++ }
  g.equipmentEntry = function (inst) {
    for (var i = 0; i < g.equipmentTable.length; i++)
      if (g.equipmentTable[i].Name === inst.Name) return g.equipmentTable[i]
    return null
  }
  g.slotForIndex = function (i) {
    var inst = g.pack[i]
    if (!inst) return ""
    var e = g.equipmentEntry(inst)
    if (!e) return ""
    if (e.Type === "Weapon") return "rightHand"
    if (e.Type === "Shield") return "leftHand"
    if (e.Type === "Armor" || e.Type === "Helmet" || e.Type === "Amulet")
      return "worn." + e.Type.toLowerCase()
    return ""
  }
  g.isEquipped = function (i) {
    var s = g.slotForIndex(i)
    if (s === "") return false
    if (s === "rightHand") return g.rightHand === g.pack[i]
    if (s === "leftHand") return g.leftHand === g.pack[i]
    var part = s.substring(5)
    return g.worn[part] === g.pack[i]
  }
  g.packClick = function (i) {
    var inst = g.pack[i]
    if (!inst) return
    var e = g.equipmentEntry(inst)
    if (!e) return
    if (e.Type === "Item") { g.useConsumable(i); return }
    if (g.isEquipped(i)) { g.unequip(i); return }
    g.equip(i)
  }
  g.setWornSlot = function (part, inst) {
    g.worn = { armor: (part === "armor" ? inst : g.worn.armor),
               helmet: (part === "helmet" ? inst : g.worn.helmet),
               amulet: (part === "amulet" ? inst : g.worn.amulet) }
  }
  g.equip = function (i) {
    var s = g.slotForIndex(i)
    if (s === "") return
    if (s === "rightHand") g.rightHand = g.pack[i]
    else if (s === "leftHand") g.leftHand = g.pack[i]
    else g.setWornSlot(s.substring(5), g.pack[i])
    g.saveRun()
  }
  g.unequip = function (i) {
    var s = g.slotForIndex(i)
    if (s === "") return
    if (s === "rightHand") g.rightHand = null
    else if (s === "leftHand") g.leftHand = null
    else g.setWornSlot(s.substring(5), null)
    g.saveRun()
  }
  g.useConsumable = function (i) {
    var inst = g.pack[i]
    var e = g.equipmentEntry(inst)
    var d = (e && e.Description) ? e.Description : ""
    var m = /Restores (\d+) MP/.exec(d)
    if (m) {
      g.heroMp = Math.min(g.heroMpMax, g.heroMp + parseInt(m[1], 10))
      g.consumeAt(i); return
    }
    m = /Restores (\d+) HP/.exec(d)
    if (m) {
      g.heroHp = Math.min(g.heroHpMax, g.heroHp + parseInt(m[1], 10))
      g.consumeAt(i); return
    }
    if (/cures poison/i.test(d)) {
      g.consumeAt(i); return
    }
  }
  g.consumeAt = function (i) {
    var next = g.pack.slice(); next[i] = null; g.pack = next
    g.saveRun()
  }
  g.resolveInstance = function (inst) {
    if (!inst) return null
    var e = g.equipmentEntry(inst)
    if (!e) return null
    var ench = (typeof inst.Enchant === "number") ? inst.Enchant : 0
    function v(x) { return (x === "infinite") ? Infinity : x }
    var name = e.Name
    if (ench > 0) name = "+" + ench + " " + name
    return {
      icon: firstCodePoint(e.Icon || "") || "·",
      name: name,
      acc: (typeof e.Accuracy === "number" || e.Accuracy === "infinite")
           ? v(e.Accuracy) + ench : null,
      dmg: (typeof e.Damage === "number" || e.Damage === "infinite")
           ? v(e.Damage) + ench : null,
      def: (typeof e.Defense === "number") ? e.Defense + ench : null,
      enchanted: ench > 0
    }
  }
  g.combatState = function () {
    var rh = g.resolveInstance(g.rightHand)
    var lh = g.resolveInstance(g.leftHand)
    var wornList = [
      g.resolveInstance(g.worn.armor),
      g.resolveInstance(g.worn.helmet),
      g.resolveInstance(g.worn.amulet)
    ].filter(function (x) { return x !== null })
    return {
      str: g.heroStats.str || 0, dex: g.heroStats.dex || 0,
      int: g.heroStats.int || 0, wil: g.heroStats.wil || 0,
      rightHand: rh, leftHand: lh,
      worn: wornList, effects: g.heroEffects
    }
  }
  g.infoSlot = -1
  g.discardItem = function (i) {
    if (i < 0 || i >= g.pack.length || !g.pack[i]) return
    var s = g.slotForIndex(i)
    if (s === "rightHand") g.rightHand = null
    else if (s === "leftHand") g.leftHand = null
    else if (s !== "") g.setWornSlot(s.substring(5), null)
    var next = g.pack.slice(); next[i] = null; g.pack = next
    g.infoSlot = -1
    g.saveRun()
  }
  // Hand re-pointing on load (Panel.qml handInPack / seedHand).
  g.handInPack = function (inst) {
    if (!inst) return null
    for (var i = 0; i < g.pack.length; i++)
      if (g.pack[i] && g.pack[i].Name === inst.Name
          && (g.pack[i].Enchant || 0) === (inst.Enchant || 0))
        return g.pack[i]
    return null
  }
  g.seedHand = function (inst) {
    var next = g.pack.slice()
    for (var i = 0; i < next.length; i++)
      if (!next[i]) { next[i] = inst; g.pack = next; return inst }
    return null
  }
  // Save conversion (Panel.qml wornAsIndices / wornFromSave).
  g.wornAsIndices = function () {
    function idx(inst) {
      if (!inst) return null
      for (var i = 0; i < g.pack.length; i++)
        if (g.pack[i] === inst) return i
      return null
    }
    return { armor: idx(g.worn.armor),
             helmet: idx(g.worn.helmet),
             amulet: idx(g.worn.amulet) }
  }
  g.wornFromSave = function (w, pack) {
    function ref(i) {
      i = (typeof i === "number" && i >= 0 && i < pack.length) ? i : -1
      return i >= 0 && pack[i] ? pack[i] : null
    }
    return { armor: ref(w && w.armor),
             helmet: ref(w && w.helmet),
             amulet: ref(w && w.amulet) }
  }
  return g
}
function inst(name, ench) {
  var o = { Name: name }
  if (ench) o.Enchant = ench
  return o
}
function byName(name) {
  for (var i = 0; i < Equipment.length; i++)
    if (Equipment[i].Name === name) return Equipment[i]
  throw new Error("no equipment row: " + name)
}

// Pack layout for the session:
//   0 = Rusty Sword (starter, equipped)   4 = Barrier Talisman (amulet)
//   1 = Buckler (shield)                  5 = Short Sword (weapon)
//   2 = Leather Armor (armor)             6 = Potion (consumable)
//   3 = Leather Helm (helmet)
var g = makeHero()
g.pack[0] = g.rightHand            // confirmNewGame seed
check("new game: starter sword in pack slot 0, equipped",
      g.pack[0] !== null && g.isEquipped(0) === true)
var buckler = inst("Buckler")
var armor = inst("Leather Armor")
var helm = inst("Leather Helm")
var amulet = inst("Barrier Talisman")
var sword = inst("Short Sword")
var potion = inst("Potion")
g.pack[1] = buckler
g.pack[2] = armor
g.pack[3] = helm
g.pack[4] = amulet
g.pack[5] = sword
g.pack[6] = potion

// --- slot assignment per class ---------------------------------------------
check("shield -> leftHand", g.slotForIndex(1) === "leftHand")
check("armor -> worn.armor", g.slotForIndex(2) === "worn.armor")
check("helmet -> worn.helmet", g.slotForIndex(3) === "worn.helmet")
check("amulet -> worn.amulet", g.slotForIndex(4) === "worn.amulet")
check("weapon -> rightHand", g.slotForIndex(5) === "rightHand")
check("consumable -> no slot", g.slotForIndex(6) === "")
check("empty slot -> no slot", g.slotForIndex(7) === "")

// --- equip (left-click) ------------------------------------------------------
g.packClick(1)   // buckler
check("equip: shield pointer set", g.leftHand === buckler)
check("equip: item stays in pack", g.pack[1] === buckler)
check("equip: isEquipped true", g.isEquipped(1) === true)
check("equip: saved", g.saves >= 1)

g.packClick(2); g.packClick(3); g.packClick(4)
check("equip: armor pointer", g.worn.armor === armor)
check("equip: helmet pointer", g.worn.helmet === helm)
check("equip: amulet pointer", g.worn.amulet === amulet)

// --- switch weapon: old stays in the pack, unequipped -----------------------
g.packClick(5)   // short sword
check("equip: weapon pointer moved", g.rightHand === sword)
check("equip: starter sword stayed in pack slot 0", g.pack[0] !== null
      && g.pack[0].Name === "Rusty Sword")
check("equip: starter sword NOT equipped", g.isEquipped(0) === false)
// Click it again → back in hand (unequipped gear is re-equipable).
g.packClick(0)
check("equip: starter sword re-equipped", g.rightHand === g.pack[0])
g.packClick(5)   // short sword back
check("equip: short sword re-equipped", g.rightHand === sword)

// --- unequip (left-click again) ---------------------------------------------
g.packClick(1)
check("unequip: shield pointer cleared", g.leftHand === null)
check("unequip: item still in pack", g.pack[1] === buckler)
check("unequip: isEquipped false", g.isEquipped(1) === false)

// --- combat state: only EQUIPPED gear contributes ----------------------------
var st = g.combatState()
var bucklerDef = byName("Buckler").Defense
var armorDef = byName("Leather Armor").Defense
var helmDef = byName("Leather Helm").Defense
var amuletDef = byName("Barrier Talisman").Defense
// worn: armor+helmet+amulet (buckler was unequipped); hands: short sword
check("combatState: 3 worn sources", st.worn.length === 3)
var defTotal = 0
for (var i = 0; i < st.worn.length; i++) if (st.worn[i].def) defTotal += st.worn[i].def
check("combatState: equipped defense only",
      defTotal === armorDef + helmDef + amuletDef)
var dv = Combat.playerDefense(st).dv
check("Combat.playerDefense sees worn gear",
      dv === 10 + 4 + armorDef + helmDef + amuletDef)
check("Combat.playerDefense excludes unequipped shield",
      dv !== 10 + 4 + armorDef + helmDef + amuletDef + bucklerDef)
// re-equip the buckler → defense rises by its def
g.packClick(1)
st = g.combatState()
check("Combat.playerDefense includes re-equipped shield",
      Combat.playerDefense(st).dv === dv + bucklerDef)

// --- consumables -------------------------------------------------------------
g.heroHp = 10
g.packClick(6)   // potion: "Restores 10 HP"
check("consumable: HP restored (10+10)", g.heroHp === 20)
check("consumable: slot emptied", g.pack[6] === null)
g.pack[6] = inst("Mana Essence")   // "Restores 10 MP"
g.heroMp = 3
g.packClick(6)
check("consumable: MP restored", g.heroMp === 13)
check("consumable: slot emptied (mp)", g.pack[6] === null)

// Non-effect item: NOT consumed (Effects.js phase), logged only.
g.pack[7] = inst("Coin Purse")
g.packClick(7)
check("no-effect item: not consumed", g.pack[7] !== null)

// HP clamps at max.
g.pack[7] = inst("Ex Potion")
g.heroHp = g.heroHpMax - 3
g.packClick(7)
check("consumable: HP clamps at max", g.heroHp === g.heroHpMax)

// --- discard (trash glyph in the item modal) ---------------------------------
g.pack[7] = inst("Rations")
g.infoSlot = 7
g.discardItem(7)
check("discard: item removed from pack", g.pack[7] === null)
check("discard: modal closed", g.infoSlot === -1)
g.discardItem(7)   // empty slot: no-op, no throw
check("discard: empty slot is a no-op", true)
// Discard an equipped weapon → slot cleared in the same pass.
g.infoSlot = 5
g.discardItem(5)
check("discard: equipped weapon removed + slot cleared",
      g.pack[5] === null && g.rightHand === null)
// Discard equipped worn gear (armor at slot 2).
g.infoSlot = 2
g.discardItem(2)
check("discard: equipped armor removed + slot cleared",
      g.pack[2] === null && g.worn.armor === null)
// Discard never touches other slots.
check("discard: other slots untouched",
      g.worn.helmet === helm && g.worn.amulet === amulet && g.leftHand === buckler)
// Restore the armor the round-trip section below expects at slot 2.
g.pack[2] = armor

// --- save round-trip: worn indices + hand copies ----------------------------
g.worn.armor = g.pack[2]
g.worn.helmet = g.pack[3]
g.worn.amulet = g.pack[4]
g.leftHand = g.pack[1]
var saved = g.wornAsIndices()
check("save: worn indices {2,3,4}",
      saved.armor === 2 && saved.helmet === 3 && saved.amulet === 4)
var loaded = g.wornFromSave(saved, g.pack)
check("load: armor round-trips", loaded.armor && loaded.armor.Name === "Leather Armor")
check("load: helmet round-trips", loaded.helmet && loaded.helmet.Name === "Leather Helm")
check("load: amulet round-trips", loaded.amulet && loaded.amulet.Name === "Barrier Talisman")
// v4 save (no worn field) → nothing worn, no crash
check("load: v4 save has no worn",
      g.wornFromSave(undefined, g.pack).armor === null)
// enchanted instance survives the round-trip with its Enchant
g.pack[8] = inst("Katana", 3)
g.rightHand = g.pack[8]
check("load: enchant preserved", g.wornFromSave({ armor: 8 }, g.pack).armor.Enchant === 3)

// Full JSON round-trip: hands are stored as COPIES (deep clone) — on load
// handInPack must re-point the slots at the pack instances so identity holds.
var text = JSON.stringify({
  leftHand: g.leftHand, rightHand: g.rightHand,
  worn: g.wornAsIndices(), pack: g.pack
})
var run = JSON.parse(text)   // fresh objects: run.rightHand !== g.rightHand
var loadedPack = run.pack
var loadedWorn = g.wornFromSave(run.worn, loadedPack)
check("round-trip: worn armor re-pointed",
      loadedWorn.armor === loadedPack[2])
check("round-trip: worn helmet re-pointed",
      loadedWorn.helmet === loadedPack[3])
check("round-trip: worn amulet re-pointed",
      loadedWorn.amulet === loadedPack[4])
check("round-trip: rightHand found in pack (Katana slot 8)",
      (function () {
        for (var i = 0; i < loadedPack.length; i++)
          if (loadedPack[i] && loadedPack[i].Name === "Katana"
              && loadedPack[i].Enchant === 3) return true
        return false
      })())
check("round-trip: leftHand found in pack (Buckler slot 1)",
      loadedPack[1] && loadedPack[1].Name === "Buckler")

// v4 hand not in pack (pre-pack-storage run) → seedHand re-seeds it.
var v4 = JSON.parse('{"version":4,"pack":[' + new Array(12).fill("null").join(",")
      + '],"rightHand":{"Name":"Rusty Sword"},"leftHand":null}')
var v4g = makeHero()
v4g.pack = v4.pack
v4g.rightHand = v4g.handInPack(v4.rightHand) || v4g.seedHand(v4.rightHand)
check("v4 load: missing hand re-seeded into pack",
      v4g.rightHand !== null && v4g.isEquipped(v4g.pack.indexOf(v4g.rightHand)) === true)

// --- every equipment row maps to exactly one slot or none --------------------
var counts = {}
for (i = 0; i < Equipment.length; i++) {
  var t = Equipment[i].Type
  counts[t] = (counts[t] || 0) + 1
}
check("table: six classes present",
      counts.Weapon > 0 && counts.Shield > 0 && counts.Armor > 0 &&
      counts.Helmet > 0 && counts.Amulet > 0 && counts.Item > 0)

process.exit(failures ? 1 : 0)
