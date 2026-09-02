import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import Quickshell.Io
import "Dungeon.js" as Dungeon
import "Save.js" as Save
import "Combat.js" as Combat
import "Stats.js" as Stats
import "Monsters.js" as Monsters
import "Drops.js" as Drops
import "Dice.js" as Dice
import "CombatLoop.js" as CombatLoop
import "Poison.js" as Poison
import "Spells.js" as Spells
import "Enchant.js" as Enchant

// Dungeons of Omakon — game window.
// Phase 3: real procedurally generated floors (Dungeon.js) rendered as a
// pseudo-3D first-person view 2 nodes deep, with arrow-driven turn/move,
// stairs overlays, and an explored-masked automap.
Panel {
  id: root
  moduleName: "b.omakon"
  ipcTarget: "b.omakon"
  manageIpc: false   // BarWidget.qml owns the IPC target for this plugin.

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function refresh() {}
  function openFromHotkey() { root.open() }

  // ---- Phase 4: run lifecycle ----------------------------------------------
  // mode: "loading" -> "menu" (no active run) | "game" (run live) | "archive"
  //       | "newgame" (name entry) | "dead" (death screen)
  property string mode: "loading"
  property var archive: []
  property string runName: ""
  property string runStarted: ""
  property int heroLevel: 1
  property var heroStats: ({ str: 4, dex: 4, con: 4, int: 4, wil: 4, unspent: 0 })
  // Active poison status: { dmg, movesLeft } or null. dmg is the monster's
  // PoisonDamage (flat per tick); movesLeft counts tile moves remaining
  // (5 per the design — turning doesn't tick, wall bumps don't tick).
  property var heroPoison: null
  // spellbook: list of {Name} (resolved via Spells.findByName against spells.json).
  // The heal from the panel spellTable is the source of truth.
  property var spellTable: []
  // Active spell effects (buffs with a duration). Each entry is
  // { name, def, stepsLeft, custom }. Ticks on tile moves out of combat,
  // on player actions in combat.
  property var activeSpells: []
  property string lastLevelUpToast: ""
  property var heroEffects: []
  property int heroXp: 0
  property string pendingNewName: ""

  function open() {
    if (mode === "loading") bootLoad()
    root.controller.show()
  }
  function toggle() { opened ? close() : open() }
  // Panel base provides controller; override its open-close path via
  // function shadowing so close saves. The save must never be able to
  // block the hide — a throw here froze X / Super+W on 2026-08-30.
  function close() {
    if (mode === "game") {
      try { saveRun() } catch (e) { console.log("omakon saveRun failed: " + e) }
    }
    root.controller.hide()
  }

  // ---- Character (Phase 4 binds to the save file) -------------------------
  property int heroHp: 20
  property int heroHpMax: 20
  property int heroMp: 8
  property int heroMpMax: 8

  // ---- Equipment / inventory ----------------------------------------------
  // Every item has a class (equipment.json "Type") that assigns it to a slot:
  //   Weapon  → rightHand    Shield  → leftHand
  //   Armor   → worn.armor   Helmet  → worn.helmet   Amulet → worn.amulet
  // Items (consumables) have no slot — left-click uses them in place.
  property var leftHand: null          // shield instance {Name, Enchant?}
  property var rightHand: ({ Name: "Rusty Sword" })   // weapon instance
  property var worn: ({ armor: null, helmet: null, amulet: null })
  readonly property string gold: "#d0b040"
  property var pack: (new Array(12)).fill(null)
  property var spells: []              // discovered spells

  // Slot of a pack index ("" for empty / consumables), resolved against
  // equipment.json. Worn items keep living in their pack slot (the pack is
  // the single storage) — the slot properties hold a pointer into it.
  function slotForIndex(i) {
    var inst = pack[i]
    if (!inst) return ""
    var e = equipmentEntry(inst)
    if (!e) return ""
    if (e.Type === "Weapon") return "rightHand"
    if (e.Type === "Shield") return "leftHand"
    if (e.Type === "Armor" || e.Type === "Helmet" || e.Type === "Amulet")
      return "worn." + e.Type.toLowerCase()
    return ""
  }
  function equipmentEntry(inst) {
    for (var i = 0; i < equipmentTable.length; i++)
      if (equipmentTable[i].Name === inst.Name) return equipmentTable[i]
    return null
  }
  // Poison immunity: the Lucid Crystal amulet (prose says it "prevents the
  // user from being poisoned"). Worn-slot only — carrying it in the pack
  // doesn't help. Checked at the moment the poison would take hold.
  function poisonImmune() {
    if (!worn || !worn.amulet) return false
    var e = equipmentEntry(worn.amulet)
    return !!(e && Poison.isImmune(e.Description))
  }
  function isEquipped(i) {
    var s = slotForIndex(i)
    if (s === "") return false
    if (s === "rightHand") return rightHand === pack[i]
    if (s === "leftHand") return leftHand === pack[i]
    var part = s.substring(5)   // past "worn."
    return worn[part] === pack[i]
  }

  // Left-click on a pack slot: equip/unequip by class, use consumables.
  function packClick(i) {
    var inst = pack[i]
    if (!inst) return
    var e = equipmentEntry(inst)
    if (!e) return
    if (e.Type === "Item") { useConsumable(i); return }
    if (isEquipped(i)) { unequip(i); return }
    equip(i)
  }
  // Worn slot update. QML bindings need NEW object identity to re-evaluate
  // (same-object assignment notifies nothing — the markExplored pattern), so
  // the slots object is rebuilt on every change.
  function setWornSlot(part, inst) {
    worn = { armor: (part === "armor" ? inst : worn.armor),
             helmet: (part === "helmet" ? inst : worn.helmet),
             amulet: (part === "amulet" ? inst : worn.amulet) }
  }
  // Equipping moves the item's slot pointer to this instance; whatever was
  // in the slot before simply goes unpointed (it stays in the pack).
  function equip(i) {
    var s = slotForIndex(i)
    if (s === "") return
    if (s === "rightHand") rightHand = pack[i]
    else if (s === "leftHand") leftHand = pack[i]
    else setWornSlot(s.substring(5), pack[i])
    saveRun()
  }
  function unequip(i) {
    var s = slotForIndex(i)
    if (s === "") return
    if (s === "rightHand") rightHand = null
    else if (s === "leftHand") leftHand = null
    else setWornSlot(s.substring(5), null)
    saveRun()
  }
  // Consumable use. HP/MP restorers and the antidote are live (parsed from
  // the prose Description, so they track the user's table); the rest need
  // the Effects.js phase (targeting, stair generation, ...) and are kept —
  // logged "effect not implemented" — until that lands.
  function useConsumable(i) {
    var inst = pack[i]
    var e = equipmentEntry(inst)
    var d = (e && e.Description) ? e.Description : ""
    var m = /Restores (\d+) MP/.exec(d)
    if (m) {
      heroMp = Math.min(heroMpMax, heroMp + parseInt(m[1], 10))
      consumeAt(i); return
    }
    m = /Restores (\d+) HP/.exec(d)
    if (m) {
      heroHp = Math.min(heroHpMax, heroHp + parseInt(m[1], 10))
      consumeAt(i); return
    }
    if (/cures poison/i.test(d)) {
      if (heroPoison) {
        heroPoison = null
        console.log("omakon poison cured by " + inst.Name)
      }
      consumeAt(i); return
    }
    // Scroll of Enchantment: the Effect row gates which equipment Types are
    // legal targets; the pack is scanned for matches and a picker modal
    // opens. The scroll is consumed only when a target is chosen.
    if (e && e.Effect && e.Effect.type === "enchant") {
      enchantSourceSlot = i
      enchantCandidates = Enchant.candidates(pack, equipmentTable, e)
      if (enchantCandidates.length === 0) {
        console.log("omakon " + inst.Name + ": nothing you carry can be enchanted")
        enchantSourceSlot = -1
        enchantCandidates = []
        return
      }
      infoSlot = -1
      popupMode = "enchant"
      return
    }
    // Bindor's Deceit: combat-out-of-position escape utility. Snap the pod
    // (consumes the item) -> the monster's next 2 swings are negated, giving
    // the player free turns to heal/buff/run once escape exists.
    if (inst.Name === "Bindor’s Deceit") {
      if (!combat || combat.over) {
        console.log("omakon Bindor's Deceit fizzles: no enemy in reach")
        return
      }
      combat.deceitLeft = 2
      combat.log.push("You snap the pod — enchanted smoke floods the arena!")
      consumeAt(i)
      bumpCombatLog()
      return
    }
    // Beacon: one per floor. While lit, the automap draws a gold ring around
    // the downstairs tile. Refuses to re-trigger if one is already lit (the
    // item is NOT consumed).
    if (inst.Name === "Beacon") {
      if (beaconOn) {
        beaconMessage = "A beacon is already lit on this floor."
        popupMode = "beacon"
        return
      }
      var found = false
      for (var rr = 0; rr < Dungeon.ROWS; rr++)
        for (var cc = 0; cc < Dungeon.COLS; cc++)
          if (floor.nodes[rr][cc].feature === "down") { found = true; break }
      if (!found) {
        console.log("omakon Beacon finds no staircase on this floor (bug)")
        return
      }
      beaconOn = true
      beaconFloor = floorNum
      console.log("omakon beacon lit — the staircase calls to you (F" + floorNum + ")")
      consumeAt(i)
      return
    }
    // Behelit: immediate descent, costs 5 max HP. Floor 50 refuses outright
    // (item kept). Below 5 max HP the sacrifice still consumes the egg but
    // the descent doesn't trigger — the hero is "too weak".
    if (inst.Name === "Behelit") {
      if (floorNum === 50) {
        console.log("omakon Behelit fizzles — the dungeon ends here")
        return
      }
      if (heroHpMax <= 5) {
        consumeAt(i)
        console.log("omakon Behelit shatters — you are too weak to sacrifice your life force")
        return
      }
      heroHpMax -= 5
      if (heroHp > heroHpMax) heroHp = heroHpMax
      console.log("omakon Behelit cracks open — you descend (max HP now " + heroHpMax + ")")
      var next = pack.slice(); next[i] = null; pack = next  // consume without the save — completeDescend() saves the full state
      completeDescend()
      return
    }
    console.log("omakon " + inst.Name + " used — effect not implemented")
  }
  // Enchant picker state. enchantSourceSlot is the pack slot holding the
  // scroll (consumed on resolve); enchantCandidates mirrors
  // Enchant.candidates() output for the modal's Repeater.
  property int enchantSourceSlot: -1
  property var enchantCandidates: []
  function applyEnchant(targetPackIndex) {
    if (enchantSourceSlot < 0) return
    var scrollRow = equipmentEntry(pack[enchantSourceSlot])
    if (!scrollRow || !scrollRow.Effect) { cancelEnchant(); return }
    var target = pack[targetPackIndex]
    if (!target) { cancelEnchant(); return }
    var next = Enchant.apply(target, scrollRow)
    var newPack = pack.slice()
    newPack[targetPackIndex] = next
    newPack[enchantSourceSlot] = null      // consume the scroll
    pack = newPack
    console.log("omakon " + next.Name + " enchanted to +" + next.Enchant
      + " via " + scrollRow.Name)
    enchantSourceSlot = -1
    enchantCandidates = []
    popupMode = "none"
    saveRun()
  }
  function cancelEnchant() {
    enchantSourceSlot = -1
    enchantCandidates = []
    popupMode = "none"
  }
  function consumeAt(i) {
    var next = pack.slice(); next[i] = null; pack = next
    saveRun()
  }
  // Discard (trash glyph in the item info modal): removes the item from the
  // pack entirely. If it was equipped, its slot is cleared in the same pass
  // (one save, not unequip+discard's two).
  function discardItem(i) {
    if (i < 0 || i >= pack.length || !pack[i]) return
    var it = pack[i]
    if (it.Name === "The Omatrix") {
      console.log("omakon The Omatrix pulses — it will not leave your hand")
      return
    }
    var s = slotForIndex(i)
    if (s === "rightHand") rightHand = null
    else if (s === "leftHand") leftHand = null
    else if (s !== "") setWornSlot(s.substring(5), null)
    var next = pack.slice(); next[i] = null; pack = next
    infoSlot = -1
    saveRun()
  }

  // ---- Combat state (2026-08-31 design: player-first, retaliate-only,
  // ---- no flee; poison envenoms on first monster hit and starts ticking
  // ---- on tile moves after the fight ends — see Poison.js) --------------
  property var monsterTable: []        // loaded from monsters.json at boot
  property var equipmentTable: []      // loaded from equipment.json at boot
  property var combat: null            // CombatLoop.newEncounter() object, or null
  property bool combatVictory: false   // kill resolved; rewards on screen until next click
  property int combatLogVersion: 0     // bump → combatView recomputes + log scrolls
  // QML can't observe deep JS-object mutation: `combat.log.push(...)` doesn't
  // re-evaluate bindings on `root.combat`. combatView is a fresh snapshot
  // rebuilt on every bumpCombatLog() — the expression references
  // combatLogVersion so that counter is a binding dependency.
  readonly property var combatView: {
    var v = combatLogVersion           // read = binding dependency
    if (!combat) return null
    void v
    var m = combat.monster
    return {
      name: m.name, icon: m.icon, color: m.color,
      hp: Math.max(0, m.hp), hpMax: m.hpMax,
      victory: combatVictory,
      log: combat.log.slice()
    }
  }

  // Resolve a pack/hand instance {Name, Enchant?} against equipment.json:
  // stats become {acc, dmg, def, enchanted}; the "infinite" strings in
  // equipment.json become JS Infinity (Combat's comparisons handle it);
  // Icon (single Nerd Font glyph char) and a display name ("+2 Katana")
  // ride along for the UI.
  function resolveInstance(inst) {
    if (!inst) return null
    var e = null
    for (var i = 0; i < equipmentTable.length; i++)
      if (equipmentTable[i].Name === inst.Name) { e = equipmentTable[i]; break }
    if (!e) return null
    var ench = (typeof inst.Enchant === "number") ? inst.Enchant : 0
    function v(x) { return (x === "infinite") ? Infinity : x }
    var name = e.Name
    if (ench > 0) name = "+" + ench + " " + name
    return {
      // firstCodePoint, not [0]: equipment glyphs are astral PUA and [0]
      // would yield a lone surrogate (tofu).
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
  function weaponLabel(inst) {
    var r = resolveInstance(inst)
    return (r && r.name) ? r.name : "your fists"
  }
  // Flag helpers for the two weapon-specific rules in equipment.json. The
  // Book of Power's "infinite" accuracy is read in the table as the string
  // "infinite" (resolveInstance converts to Infinity); the Sapien Cannon's
  // "infinite" damage marks its kill-on-hit rider.
  function isBookOfPower(inst) { return !!(inst && inst.Name === "Book of Power") }
  function isSapienCannon(inst) { return !!(inst && inst.Name === "Sapien Cannon") }
  // Null-safe glyph accessor for the UI: "" when the table isn't loaded yet
  // or the entry is missing, so Text nodes can fall back to their own glyph.
  function iconOf(inst) {
    var r = resolveInstance(inst)
    return (r && r.icon) ? r.icon : ""
  }
  // Spell glyphs: loadSpells already normalized Icon into IconGlyph.
  function spellGlyph(def) {
    return (def && def.IconGlyph) ? def.IconGlyph : ""
  }

  property string popupMode: "none"    // "none" | "spells" | "inventory" | "stats" | "alloc"
  function togglePopup(mode) {
    popupMode = (popupMode === mode) ? "none" : mode
  }

  // Item info modal (right-click a pack item): name + prose description.
  // Right-clicking the same item again (or Escape) closes it; right-clicking
  // another item swaps the shown item.
  property int infoSlot: -1
  function toggleInfo(i) {
    infoSlot = (infoSlot === i) ? -1 : i
  }
  function infoText() {
    var inst = (infoSlot >= 0 && infoSlot < pack.length) ? pack[infoSlot] : null
    if (!inst) return ""
    var e = equipmentEntry(inst)
    return (e && e.Description) ? e.Description : ""
  }

  // ---- Stats + allocation ---------------------------------------------------
  function openStatsPopup() { popupMode = "stats" }
  function grantXp(xp, sourceLabel) {
    var out = Stats.addXp(heroStats, { level: heroLevel, xp: heroXp }, xp)
    heroXp = out.xp
    heroLevel = out.level
    heroStats = out.stats
    heroHpMax = Stats.hpMax(heroStats, heroLevel)
    heroMpMax = Stats.mpMax(heroStats, heroLevel)
    if (out.levelsGained > 0) {
      heroHp = heroHpMax
      heroMp = heroMpMax
      lastLevelUpToast = "LEVEL UP → " + out.level + " (+" + out.levelsGained + ") — HP/MP restored"
      popupMode = "alloc"
    }
  }
  function assignStat(stat) {
    heroStats = Stats.assignPoint(heroStats, stat)
    heroHpMax = Stats.hpMax(heroStats, heroLevel)
    heroMpMax = Stats.mpMax(heroStats, heroLevel)
    // Level-up full restore: the alloc point may have raised max again,
    // so re-fill here too — the hero always stands back up at 100%.
    heroHp = heroHpMax
    heroMp = heroMpMax
  }
  // Combat hooks read the primary stats via combatState().

  // Build the state object Combat.attack() expects. Equipped gear is the
  // five slots: hands + worn.armor/helmet/amulet (the pack is storage; the
  // slot pointers decide what counts as equipped).
  function combatState() {
    var rh = resolveInstance(rightHand)
    var lh = resolveInstance(leftHand)
    var wornList = [
      resolveInstance(worn.armor),
      resolveInstance(worn.helmet),
      resolveInstance(worn.amulet)
    ].filter(function (x) { return x !== null })
    // Barrier spells contribute +INT to DV and MDV for their duration.
    var spellEffects = heroEffects.slice()
    if (isSpellActive("Magic Barrier") || isSpellActive("Revengeance Barrier")) {
      var n = heroStats.int || 0
      spellEffects = spellEffects.concat([{ def: n, enchanted: true }])
    }
    return {
      str: heroStats.str || 0, dex: heroStats.dex || 0, int: heroStats.int || 0,
      wil: heroStats.wil || 0,
      rightHand: rh, leftHand: lh,
      worn: wornList, effects: spellEffects
    }
  }
  // Attack a monster { dv: int, ... }. Returns Combat.attack's result
  // without applying HP — the combat loop (Phase 5) owns that.
  function attackMonster(monster) { return Combat.attack(combatState(), monster) }

  // ---- Floor state (persisted via Save.js / keyring) -----------------------
  property bool automapOn: true
  property int floorNum: 1
  property int floorSeed: ((Math.random() * 0x7fffffff) | 0)
  property bool descending: false       // true while dissolve anim runs
  property var floor: Dungeon.generate(floorSeed)
  property var pos: ({ row: floor.start.row, col: floor.start.col, facing: 0 })

  // Beacon: consuming one on this floor plants the beacon on the downstairs
  // tile; it stays lit until you descend. beaconFloor guards one-per-floor.
  property bool beaconOn: false
  property int beaconFloor: 0
  property string beaconMessage: ""
  // Omatrix run state. omatrixPos = "r,c" while the Omatrix still sits on
  // its spawn tile on F50, null once picked up (or from floors 1..49).
  // exitsPos = "r,c" for the hidden exit staircase (spawned on pickup,
  // drawn only while hasOmatrix). hasOmatrix = the item is in the pack.
  // Persisted in the save (v8) so quitting mid-F50 restores the state.
  property string omatrixPos: ""
  property string exitsPos: ""
  property bool hasOmatrix: false
  function beginDescend() {
    if (floor.nodes[pos.row][pos.col].feature !== "down" || descending) return
    descending = true               // dissolve layer activates; step resets there
  }

  function completeDescend() {
    floorNum++
    floorSeed = (Math.random() * 0x7fffffff) | 0
    floor = Dungeon.generate(floorSeed)
    pos = ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = ({})
    beaconOn = false             // beacon lights one floor only
    if (floorNum === 50) {
      // The Omatrix sits on a single tile on this floor, chosen uniformly
      // at random. (Stairs tile is fine as a host — its pickup takes
      // priority over the staircase's UI cue; stepping on the tile with an
      // Omatrix sets off the pickup before any DESCEND click.)
      var r1 = Math.floor(Math.random() * Dungeon.ROWS)
      var c1 = Math.floor(Math.random() * Dungeon.COLS)
      omatrixPos = r1 + "," + c1
      exitsPos = ""
      hasOmatrix = false
      console.log("omakon F50: Omatrix at " + omatrixPos)
    } else {
      omatrixPos = ""
      exitsPos = ""
      hasOmatrix = false
    }
    markExplored(pos.row, pos.col)
    descending = false
    saveRun()
  }

  // ---- Keyring I/O -------------------------------------------------------------
  // secret-tool shells via bash; text goes through a temp file in
  // XDG_RUNTIME_DIR (secret-tool reads stdin to EOF).
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  property string ioTempPath: ""
  property string ioField: ""

  function newTempPath() {
    return runtimeDir + "/omakon-"
      + Date.now().toString(36) + "-"
      + Math.floor(Math.random() * 0x100000000).toString(36) + ".json"
  }

  Process {
    id: ioProc
    onExited: function(exitCode) { root.ioFinished(exitCode) }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ioStdout(String(text || ""))
    }
  }

  // Payloads are written straight to the temp file via FileView (blockWrites
  // = synchronous, atomic). No shell, no base64, no Qt string/byte encoding
  // — so there is nothing user-typed for the shell to interpolate. The bash
  // step only reads this fixed path. (Qt.stringToUtf8/base64Encode do not
  // exist in this QML runtime — a 2026-08-30 regression that made every
  // saveRun throw and froze the close path.)
  FileView {
    id: saveFile
    atomicWrites: true
    blockWrites: true
    printErrors: false
  }

  // Static data tables — read once at boot from the plugin source dir.
  // FileView.path wants an absolute path in this shell build; __sourceDir
  // is injected by the plugin registry (same trick Kaomarchy uses).
  readonly property string dataDir:
    (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
    + "/omarchy/plugins/b.omakon"
  // monsters.json icons arrive in mixed notation while the table is being
  // curated: either the raw glyph char ("󰳗") or a "U+hex" reference
  // ("U+f0f02"). Normalize both to the raw char so every consumer (the
  // combat overlay, the automap, future bestiary) can bind Text directly.
  //
  // Deliberately conservative: no String.fromCodePoint, no regex — the
  // surrogate pair is built by hand so this works on any JS engine level.
  function hexVal(c) {
    var lo = "0123456789abcdef"
    var up = "0123456789ABCDEF"
    var i = lo.indexOf(c)
    if (i >= 0) return i
    i = up.indexOf(c)
    if (i >= 0) return i
    return -1
  }
  // "U+f0f02" -> the single-char glyph (surrogate pair when needed).
  // Returns "" if it isn't a well-formed "U+hex" token.
  function codePointToChar(cp) {
    if (cp <= 0xFFFF) return String.fromCharCode(cp)
    cp -= 0x10000
    var hi = 0xD800 + Math.floor(cp / 0x400)
    var lo = 0xDC00 + (cp % 0x400)
    return String.fromCharCode(hi, lo)
  }
  // First FULL codepoint of a string. charAt(0) alone returns only the high
  // surrogate for any glyph above U+FFFF (our md- PUA icons), which is a
  // lone surrogate -> tofu. So rejoin a surrogate pair when present.
  function firstCodePoint(s) {
    if (!s.length) return ""
    var c0 = s.charCodeAt(0)
    if (c0 >= 0xD800 && c0 <= 0xDBFF && s.length > 1) {
      var c1 = s.charCodeAt(1)
      if (c1 >= 0xDC00 && c1 <= 0xDFFF) return s.substring(0, 2)
    }
    return s.charAt(0)
  }
  function normalizeIcon(icon) {
    var s = String(icon == null ? "" : icon)
    // U+hex token? First char 'U', second '+', then 1-6 hex digits.
    if (s.length >= 3 && s.charCodeAt(0) === 0x55 /*U*/ && s.charCodeAt(1) === 0x2b /*+*/) {
      var hexPart = s.substring(2)
      if (hexPart.length >= 1 && hexPart.length <= 6) {
        var allHex = true
        for (var i = 0; i < hexPart.length; i++)
          if (hexVal(hexPart.charAt(i)) < 0) { allHex = false; break }
        if (allHex) return codePointToChar(parseInt(hexPart, 16))
      }
    }
    // Raw glyph (already a character): take the first full codepoint so
    // astral md- icons keep their surrogate pair.
    return firstCodePoint(s)
  }
  function loadMonsters(text) {
    var rows = JSON.parse(text)
    for (var i = 0; i < rows.length; i++)
      rows[i].Icon = normalizeIcon(rows[i].Icon)
    monsterTable = rows
    console.log("omakon loaded " + monsterTable.length + " monsters")
  }
  function loadEquipment(text) {
    equipmentTable = JSON.parse(text)
    console.log("omakon loaded " + equipmentTable.length + " equipment entries")
  }
  function loadSpells(text) {
    var rows = JSON.parse(text)
    for (var i = 0; i < rows.length; i++)
      rows[i].IconGlyph = normalizeIcon(rows[i].Icon)
    spellTable = rows
    console.log("omakon loaded " + spellTable.length + " spells")
  }
  FileView { id: monsterFile; path: root.dataDir + "/monsters.json"; onLoaded: root.loadMonsters(text()) }
  FileView { id: equipFile;   path: root.dataDir + "/equipment.json"; onLoaded: root.loadEquipment(text()) }
  FileView { id: spellFile;   path: root.dataDir + "/spells.json";   onLoaded: root.loadSpells(text()) }

  property string ioStdoutText: ""

  // Jobs wait in ioQueue; one runs at a time. die() fires an archive store
  // AND a run clear back-to-back — with the old fire-and-restart form the
  // second start() killed the first mid-write and the death entry was lost.
  // (Fixed 2026-08-30 alongside the missing-$1 root cause.)
  property var ioQueue: []

  function ioFinished(exitCode) {
    var field = ioField
    var text = ioStdoutText
    ioField = ""
    if (field === "boot_run") {
      var run = Save.parseRun(text)
      if (run) { applyRun(run); mode = "game" }
      else mode = "menu"
    } else if (field === "archive_load") {
      archive = Save.parseArchive(text)
    } else if (field === "run_save" || field === "archive_save" || field === "run_clear") {
      if (exitCode !== 0) console.log("omakon keyring " + field + " failed: exit " + exitCode)
    }
    // store/clear success paths need no handling
    ioPump()
  }

  function ioStdout(t) { ioStdoutText = t }

  function ioPump() {
    if (ioQueue.length === 0) return
    if (ioProc.running) return          // busy; onExited → ioFinished pumps
    ioStartGuarded(ioQueue.shift())
  }

  function ioStart(job) {
    if (job.kind === "boot_run") {
      ioField = "boot_run"
      ioStdoutText = ""
      ioProc.command = ["bash", "-c", Save.loadCmd("run")]
    } else if (job.kind === "archive_load") {
      ioField = "archive_load"
      ioStdoutText = ""
      ioProc.command = ["bash", "-c", Save.loadCmd("archive")]
    } else if (job.kind === "run_clear") {
      ioField = "run_clear"
      ioProc.command = ["bash", "-c", Save.clearScript("run")]
    } else if (job.kind === "store") {
      // FileView writes the payload to the temp file (synchronous — the
      // blockWrites flag makes setText block until flushed), then the
      // shell step just feeds that file to secret-tool. Nothing user-typed
      // reaches the shell: the path is generated by newTempPath() and the
      // text lives only in the file. The path rides as bash's positional
      // $1 — a bare `bash -c '<script>'` has none, which is why saves
      // silently failed since Phase 4 (fixed 2026-08-30).
      ioField = job.field + "_save"
      ioTempPath = job.tempPath
      saveFile.path = ioTempPath
      saveFile.setText(job.text)
      ioProc.command = ["bash", "-c", Save.storeScript(job.field),
        "omakon", ioTempPath]
    }
    ioProc.running = true
  }

  // Wrapper so a bad job can't jam the queue: if starting a job throws,
  // log it and pump the next one (onExited never fires for a job that
  // never started, so the queue would deadlock otherwise).
  function ioStartGuarded(job) {
    try { ioStart(job) }
    catch (e) { console.log("omakon io job failed (" + job.kind + "): " + e); ioPump() }
  }

  function bootLoad() { ioQueue.push({ kind: "boot_run" }); ioPump() }

  function loadArchive() { ioQueue.push({ kind: "archive_load" }); ioPump() }

  function saveRun() {
    if (mode !== "game") return
    ioQueue.push({ kind: "store", field: "run",
                   text: Save.serializeRun(currentState()),
                   tempPath: newTempPath() })
    ioPump()
  }

  function saveArchiveEntry(entry) {
    archive = Save.appendArchive(archive, entry)
    ioQueue.push({ kind: "store", field: "archive",
                   text: JSON.stringify(archive),
                   tempPath: newTempPath() })
    ioPump()
  }

  function clearRun() { ioQueue.push({ kind: "run_clear" }); ioPump() }

  // Worn slots hold live references into the pack (the pack is storage);
  // saves persist them as PACK INDICES — exact even with duplicate items in
  // the pack, which a Name match would resolve ambiguously.
  function wornAsIndices() {
    function idx(inst) {
      if (!inst) return null
      for (var i = 0; i < pack.length; i++)
        if (pack[i] === inst) return i
      return null
    }
    return { armor: idx(worn.armor),
             helmet: idx(worn.helmet),
             amulet: idx(worn.amulet) }
  }
  function currentState() {
    return {
      name: runName, started: runStarted,
      hp: heroHp, hpMax: heroHpMax, mp: heroMp, mpMax: heroMpMax,
      level: heroLevel, xp: heroXp,
      stats: heroStats,
      leftHand: leftHand, rightHand: rightHand,
      worn: wornAsIndices(),
      pack: pack, spells: spells, effects: heroEffects,
      poison: heroPoison,
      activeSpells: Spells.serializeActives(activeSpells),
      floorNum: floorNum, seed: floorSeed,
      omatrixPos: omatrixPos, exitsPos: exitsPos, hasOmatrix: hasOmatrix,
      pos: pos, explored: explored
    }
  }

  // Hands in saves may predate the instance format (old: {icon, name});
  // normalize to {Name} so resolveInstance can always find the entry.
  function handFromSave(h) {
    if (!h) return null
    if (typeof h.Name === "string") return h
    if (typeof h.name === "string") {
      var out = { Name: h.name }
      if (typeof h.Enchant === "number") out.Enchant = h.Enchant
      return out
    }
    return null
  }
  // First pack instance matching Name+Enchant (hands are stored as copies —
  // JSON round-trips make them distinct objects, so the slot must be
  // re-pointed at the pack instance to keep isEquipped identity).
  function handInPack(inst) {
    if (!inst) return null
    for (var i = 0; i < pack.length; i++)
      if (pack[i] && pack[i].Name === inst.Name
          && (pack[i].Enchant || 0) === (inst.Enchant || 0))
        return pack[i]
    return null
  }
  // Put a copy of inst into the first empty pack slot and return it.
  function seedHand(inst) {
    var next = pack.slice()
    for (var i = 0; i < next.length; i++)
      if (!next[i]) { next[i] = inst; pack = next; return inst }
    console.log("omakon seedHand: pack full, " + inst.Name + " lost")
    return null
  }
  function wornFromSave(w, pack) {
    // Slot pointers are pack INDICES (see wornAsIndices). v4 saves predate
    // the worn slots entirely — those runs load with nothing worn, which is
    // exactly how they played.
    function ref(i) {
      i = (typeof i === "number" && i >= 0 && i < pack.length) ? i : -1
      return i >= 0 ? handFromSave(pack[i]) : null
    }
    return { armor: ref(w && w.armor),
             helmet: ref(w && w.helmet),
             amulet: ref(w && w.amulet) }
  }
  function applyRun(run) {
    runName = run.name || "Hero"
    runStarted = run.started || ""
    heroHp = run.hp; heroHpMax = run.hpMax
    heroMp = run.mp; heroMpMax = run.mpMax
    heroLevel = run.level || 1; heroXp = run.xp || 0
    heroStats = run.stats || Stats.freshStats()
    heroEffects = run.effects || []
    heroPoison = run.poison || null
    activeSpells = Spells.reviveActives(run.activeSpells || [], spellTable)
    omatrixPos = run.omatrixPos || ""
    exitsPos = run.exitsPos || ""
    hasOmatrix = !!run.hasOmatrix
    pack = run.pack || (new Array(12)).fill(null)
    // Hands are stored as COPIES; re-point them at the pack instance so
    // isEquipped() identity holds after the JSON round-trip. A hand not in
    // the pack (v4 saves, pre-pack-storage) is re-seeded into slot 0 to
    // keep the invariant "all gear lives in the pack".
    leftHand = handInPack(handFromSave(run.leftHand))
    rightHand = handInPack(handFromSave(run.rightHand))
    if (!leftHand && handFromSave(run.leftHand))
      leftHand = seedHand(handFromSave(run.leftHand))
    if (!rightHand) {
      var rsrc = handFromSave(run.rightHand) || ({ Name: "Rusty Sword" })
      rightHand = handInPack(rsrc) || seedHand(rsrc)
    }
    worn = wornFromSave(run.worn, pack)
    // Worn gear lives in the pack; hands keep their own copies (v4 layout).
    spells = run.spells || []
    floorNum = run.floorNum || 1
    floorSeed = run.seed
    floor = Dungeon.generate(floorSeed)
    pos = run.pos || ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = run.explored || ({})
    markExplored(pos.row, pos.col)
    combat = null    // fights are not persisted
    combatVictory = false
  }

  // ---- Run lifecycle transitions ----------------------------------------------
  function startNewGame() { mode = "newgame"; pendingNewName = "" }

  function confirmNewGame(name) {
    name = ("" + name).trim(); if (name === "") return
    runName = name
    runStarted = Qt.formatDate(new Date(), "yyyy-MM-dd")
    heroHp = 25; heroHpMax = 25; heroMp = 15; heroMpMax = 15
    heroLevel = 1; heroXp = 0
    heroStats = Stats.freshStats()
    heroPoison = null
    activeSpells = []
    leftHand = null
    // All gear lives in the pack; the slot is a pointer into it. The starter
    // sword rides in slot 0 and starts equipped — so it can be swapped out
    // AND re-equipped like any other weapon.
    pack = (new Array(12)).fill(null)
    pack[0] = ({ Name: "Rusty Sword" })
    rightHand = pack[0]
    worn = ({ armor: null, helmet: null, amulet: null })
    combat = null
    combatVictory = false
    spells = []
    floorNum = 1
    floorSeed = (Math.random() * 0x7fffffff) | 0
    floor = Dungeon.generate(floorSeed)
    omatrixPos = ""; exitsPos = ""; hasOmatrix = false
    pos = ({ row: floor.start.row, col: floor.start.col, facing: 0 })
    explored = ({})
    markExplored(pos.row, pos.col)
    mode = "game"
    saveRun()
  }

  function showArchive() { loadArchive(); mode = "archive" }

  function die() {
    // Drop the encounter: the death screen must own the whole viewport
    // (combatView is only nulled on the next combatAct click, which
    // never comes once the run is over).
    combat = null
    combatVictory = false
    omatrixPos = ""; exitsPos = ""; hasOmatrix = false
    // Permadeath: archive the run, clear the active run, bump to menu.
    saveArchiveEntry({
      name: runName, started: runStarted,
      floor: floorNum, level: heroLevel,
      score: Save.computeScore(currentState())
    })
    clearRun()      // queue serializes: archive store, then run clear
    mode = "dead"
  }

  // Stepping on the hidden exit staircase with the Omatrix wins the run.
  // Same archive bookkeeping as die(); a "won" flag marks the entry.
  function winGame() {
    if (!onExitStairs()) return
    combat = null
    combatVictory = false
    saveArchiveEntry({
      name: runName, started: runStarted,
      floor: floorNum, level: heroLevel,
      score: Save.computeScore(currentState()) + 1000000,  // win flag: six zeros
    })
    clearRun()
    omatrixPos = ""; exitsPos = ""; hasOmatrix = false
    mode = "dead"
  }

  // Explored mask for the automap, keyed "r,c".
  property var explored: ({})
  Component.onCompleted: markExplored(pos.row, pos.col)

  function markExplored(r, c) {
    var key = r + "," + c
    if (explored[key]) return
    var next = {}
    for (var k in explored) next[k] = true
    next[key] = true
    explored = next    // new object identity so the automap re-evaluates
  }

  readonly property var view: floor ? Dungeon.vista(floor, pos) : []
  function wallAt(rel) { return Dungeon.hasWall(floor, pos.row, pos.col, (pos.facing + rel + 4) % 4) }

  function move(dir) {
    if (combat) return                  // encounter in progress: movement locked
    var steps = isSpellActive("Flyer Fins") ? 2 : 1
    for (var s = 0; s < steps; s++) {
      var np = Dungeon.move(floor, pos, dir)
      if (np.row === pos.row && np.col === pos.col) break   // wall
      pos = np
      markExplored(np.row, np.col)
      maybePickupOmatrix(np.row, np.col)   // F50 pickup; returns true → handled below
      if (mode !== "game") return          // safety: pickup shouldn't kill, but same guard as poison
      tickPoison()
      if (mode !== "game") return       // poison killed the hero
      // Fires (burn) tick per combat round AND per tile move; burn state
      // lives on combat, so out-of-combat burn has no HOST — skipped here
      // (burn only ticks while its fight is ongoing).
      tickActiveSpells()
      if (!isSpellActive("Shadow Globe")) trySpawnEncounter()
      if (combat) break                 // Flyer Fins second step blocked by fight
    }
    debugVista()
  }

  // ---- Blink targeting --------------------------------------------------------
  // Every cell the player can currently SEE, forward first. Derived from the
  // vista slices: the ahead corridor stops at the first visible end wall; a
  // side passage is listed only when the partition into it is open (the hero
  // could actually step into it from the corridor), and its length is capped
  // by the same ahead-cone distance so you never blink PAST the wall you'd
  // otherwise run into. Pure math on `view` — node-testable logic shape,
  // same guard Dungeon.js uses for in-bounds.
  function computeBlinkTargets() {
    var v = view
    var f = pos.facing
    var leftD = (f + 3) % 4, rightD = (f + 1) % 4
    var targets = []
    var seen = {}                       // a side passage can coincide with
                                        // the next depth's side cell — dedupe
    function push(row, col, dist, label) {
      var k = row + "," + col
      if (seen[k]) return
      seen[k] = true
      targets.push({ row: row, col: col, dist: dist, label: label })
    }
    var featGlyph = function(feat) {
      return feat === "down" ? " \u2193" : feat === "up" ? " \u2191" : ""
    }
    for (var d = 1; d <= v.length; d++) {
      var s = v[d - 1]
      if (!s || !s.visible) break
      var ar = pos.row + Dungeon.DR[f] * d
      var ac = pos.col + Dungeon.DC[f] * d
      if (ar < 0 || ar >= Dungeon.ROWS || ac < 0 || ac >= Dungeon.COLS) break
      push(ar, ac, d, "ahead" + (s.feature === "down" ? " \u2193 stairs down"
        : s.feature === "up" ? " \u2191 stairs up" : ""))
      // open partition into a side passage at this depth: the side cell is
      // visible, and its own end-wall row extends the view one band further
      // right (up to sideL.endDist cells along the side direction). This
      // trace duplicates Dungeon.vista's traceSidePassage math so a side
      // cell beyond a CLOSER ahead end wall is still offered (it genuinely
      // is visible — the side corridor turns inside the vista) but a cell
      // past the side passage's own end wall never is.
      var sides = [
        { open: !s.left,  sideL: s.sideL, dir: leftD,  name: "left"  },
        { open: !s.right, sideL: s.sideR, dir: rightD, name: "right" }
      ]
      for (var k = 0; k < 2; k++) {
        var sd = sides[k]
        if (!sd.open || !sd.sideL || sd.sideL.side) continue   // closed partition
        var span = sd.sideL.endDist === 0 ? 4 : sd.sideL.endDist
        for (var j = 1; j <= span; j++) {
          var sr = ar + Dungeon.DR[sd.dir] * j
          var sc = ac + Dungeon.DC[sd.dir] * j
          if (sr < 0 || sr >= Dungeon.ROWS || sc < 0 || sc >= Dungeon.COLS) break
          var feat = floor.nodes[sr][sc].feature
          push(sr, sc, d + j, sd.name + " passage" + featGlyph(feat))
        }
      }
      if (s.end) break      // end wall terminates the ahead corridor
    }
    return targets
  }

  function doBlinkTo(i) {
    if (i < 0 || i >= blinkTargets.length) return
    var t = blinkTargets[i]
    pos = { row: t.row, col: t.col, facing: pos.facing }
    markExplored(t.row, t.col)
    blinkTargets = []
    popupMode = "none"
    console.log("omakon blinked to " + t.row + "," + t.col)
    // Blink is an out-of-combat spell; tick durations like a tile move,
    // then the arrival tile may spawn an encounter (same as walking in).
    tickActiveSpells()
    if (!isSpellActive("Shadow Globe")) trySpawnEncounter()
    saveRun()
  }

  function cancelBlink() {
    // Spell was already paid: refund so a misclick isn't a 4-MP loss.
    var def = Spells.findByName(spellTable, "Blink")
    if (def) heroMp += def.Cost
    blinkTargets = []
    popupMode = "none"
    console.log("omakon blink cancelled (MP refunded)")
    saveRun()
  }
  // Poison ticks on successful tile changes only (per the design: never on
  // turning, never on wall bumps). Damage is the monster's flat
  // PoisonDamage; ticks run 5 moves then the status clears itself.
  function tickPoison() {
    if (!heroPoison) return
    var r = Poison.tick(heroPoison)
    heroPoison = r.state
    heroHp = Math.max(0, heroHp - r.damage)
    console.log("omakon poison ticks for " + r.damage
      + (r.done ? " (last tick)" : ""))
    if (heroHp <= 0) { die(); return }
    saveRun()
  }

  // ---- Spells ------------------------------------------------------------
  // Duration-bearing spells tick once per tile move out of combat, and once
  // per player action in combat (2026-09-01 user clarification).
  function tickActiveSpells() {
    if (!activeSpells || activeSpells.length === 0) return
    var r = Spells.tickAll(activeSpells)
    activeSpells = r.active
    for (var i = 0; i < r.expired.length; i++)
      console.log("omakon " + r.expired[i].name + " wears off")
  }
  // ---- Omatrix (Floor 50) ------------------------------------------------
  // The Omatrix sits at omatrixPos ("r,c") until the player steps onto the
  // tile. Pickup moves the item into the first empty pack slot, spawns the
  // hidden ascending staircase at exitsPos (chosen with a Chebyshev distance
  // of at least 3 from the pickup so the player must search the floor), and
  // flags hasOmatrix. Only one pickup per floor: the flag clears the spawn
  // tile. Descending off F50 or dying clears all three.
  function hasItemNamed(name) {
    for (var i = 0; i < pack.length; i++)
      if (pack[i] && pack[i].Name === name) return true
    return false
  }
  function maybePickupOmatrix(r, c) {
    if (floorNum !== 50) return false
    if (omatrixPos === (r + "," + c) && !hasItemNamed("The Omatrix")) {
      pickUpOmatrix()
      return true
    }
    return false
  }
  function pickUpOmatrix() {
    // Full pack? Block the pickup behind a discard-choice modal: the player
    // MUST have room for the Omatrix (dropping it would softlock the run —
    // the only path to victory is holding it). popupMode "omatrix" lists
    // the pack; choosing a slot discards it and re-runs this function.
    var free = -1
    for (var i = 0; i < pack.length; i++)
      if (!pack[i]) { free = i; break }
    if (free < 0) {
      popupMode = "omatrix"
      console.log("omakon pack is full — choose an item to discard for the Omatrix")
      return
    }
    var next = pack.slice()
    next[free] = { Name: "The Omatrix" }
    pack = next
    omatrixPos = ""
    var pr = pos.row, pc = pos.col
    var candidates = []
    for (var rr = 0; rr < Dungeon.ROWS; rr++)
      for (var cc = 0; cc < Dungeon.COLS; cc++) {
        var dr = Math.abs(rr - pr), dc = Math.abs(cc - pc)
        if (Math.max(dr, dc) >= 3) candidates.push(rr + "," + cc)
      }
    if (candidates.length === 0) {
      for (rr = 0; rr < Dungeon.ROWS; rr++)
        for (cc = 0; cc < Dungeon.COLS; cc++)
          candidates.push(rr + "," + cc)
    }
    exitsPos = candidates[Math.floor(Math.random() * candidates.length)]
    hasOmatrix = true
    console.log("omakon Omatrix picked up — exit staircase spawned at " + exitsPos)
  }
  function onExitStairs() {
    return hasOmatrix && exitsPos === (pos.row + "," + pos.col)
  }
  // Discard-choice modal (popupMode "omatrix") pick: the pack was full when
  // the hero stepped on the Omatrix tile. Chosen slot is discarded via the
  // normal discard path (clears its equip pointer if set), then pickup
  // retries with room guaranteed.
  function discardForOmatrix(i) {
    if (i < 0 || i >= pack.length || !pack[i]) return
    popupMode = "none"
    discardItem(i)
    pickUpOmatrix()
    saveRun()
  }
  function cancelOmatrixDiscard() {
    // Step off the tile first if you want to pick it up later — canceling
    // leaves the Omatrix on the ground at omatrixPos.
    popupMode = "none"
    console.log("omakon you back away from the Omatrix for now")
  }
  function isSpellActive(name) {
    for (var i = 0; i < activeSpells.length; i++)
      if (activeSpells[i].name === name) return true
    return false
  }
  function getActive(name) {
    for (var i = 0; i < activeSpells.length; i++)
      if (activeSpells[i].name === name) return activeSpells[i]
    return null
  }
  function hasSpell(name) {
    for (var i = 0; i < spells.length; i++)
      if (spells[i].Name === name || spells[i].name === name) return true
    return false
  }

  // Cast a learned spell by name. Returns true if it fired. Attack spells
  // require combat and target the current monster. Buffs push onto
  // activeSpells (their effects are read by combatState/move/etc at
  // resolution time). Blink opens the target chooser modal via
  // blinkTargets (it is rejected while combat is active).
  property var blinkTargets: []
  property string spellInfoName: ""
  function castSpell(name) {
    var def = Spells.findByName(spellTable, name)
    if (!def) return false
    if (heroMp < def.Cost) { console.log("omakon not enough MP for " + name); return false }
    var cls = Spells.classify(def)
    if (cls === "damage" && !combat) return false        // nothing to hit
    if (cls === "blink" && combat) return false          // no teleporting out of a fight

    heroMp -= def.Cost
    var intn = heroStats.int || 0

    if (cls === "damage") {
      if (name === "Mana Missile") {
        // Infinite accuracy, never misses.
        var mmDmg = Spells.rollFormula(def.Damage, intn, Math.random)
        combat.monster.hp -= mmDmg
        combat.log.push("Mana Missile hits the " + combat.monster.name
          + " for " + mmDmg + " damage!")
      } else {
        // Regular attack spell: rolls to hit vs DV like a weapon.
        var res = Combat.attack(combatState(), combat.monster)
        if (!res.hit) {
          combat.log.push(name + " misses the " + combat.monster.name
            + ". (ACC " + res.accuracy + "+2d6=" + res.accRoll
            + " vs DV " + res.dv + ")")
          monsterTurn()
          bumpCombatLog(); saveRun(); return true
        }
        var dmg = Spells.rollFormula(def.Damage, intn, Math.random)
        combat.monster.hp -= dmg
        combat.log.push(name + " hits the " + combat.monster.name
          + " for " + dmg + " damage!")
        if (name === "Fireball") {
          combat.burn = { dmg: Dice.roll("1d4"), rounds: 3 }
          combat.log.push("The " + combat.monster.name
            + " is burning! (" + combat.burn.dmg + " per round)")
        } else if (name === "Glacial Shard") {
          combat.slipNext = true
        } else if (name === "Blood Wrench") {
          heroHp = Math.min(heroHpMax, heroHp + dmg)
          combat.log.push("You absorb " + dmg + " HP from the "
            + combat.monster.name + ".")
        }
      }
      if (combat.monster.hp <= 0) {
        combat.log.push("The " + combat.monster.name + " dies!")
        combat.over = true; combat.won = true
        resolveKill()
      } else {
        monsterTurn()
      }
      tickActiveSpells()      // cast counted as a player action
      bumpCombatLog(); saveRun(); return true
    }

    if (cls === "heal") {
      var amount = Spells.rollFormula(def.Damage, intn, Math.random)
      heroHp = Math.min(heroHpMax, heroHp + amount)
      if (combat) {
        combat.log.push(name + " restores " + amount + " HP.")
        monsterTurn()          // heal consumes your action in combat
        tickActiveSpells()
        bumpCombatLog()
      } else {
        console.log("omakon " + name + " restores " + amount + " HP")
      }
      saveRun(); return true
    }

    if (cls === "buff") {
      var act = Spells.activate(def, intn, Math.random)
      if (name === "Ice Shield") act.custom.shieldHp = 14
      activeSpells = activeSpells.concat([act])
      if (combat) {
        combat.log.push(name + " surrounds you. (" + act.stepsLeft + " rounds)")
        monsterTurn()          // casting in combat = your action
        tickActiveSpells()
        bumpCombatLog()
      } else {
        console.log("omakon cast " + name + " (" + act.stepsLeft + " steps)")
      }
      saveRun(); return true
    }

    if (cls === "blink") {
      blinkTargets = computeBlinkTargets()
      if (blinkTargets.length === 0) {
        // Refund: nothing on offer (shouldn't happen — you can always see
        // one cell ahead — but never eat MP for a no-op).
        heroMp += def.Cost
        console.log("omakon blink fizzles: no visible destination")
        saveRun(); return false
      }
      popupMode = "blink"
      console.log("omakon blink: choose a destination (" + blinkTargets.length + " tiles)")
      saveRun(); return true
    }

    // specials
    if (name === "Slip" && combat && !combat.over) {
      combat.slipNext = true
      combat.log.push("The " + combat.monster.name + " slips on ice!")
      tickActiveSpells()
      bumpCombatLog(); saveRun(); return true
    }
    if (name === "Imbibe Luck") {
      luckPending = true
      console.log("omakon luck imbued — next kill drops for sure")
      saveRun(); return true
    }
    return false
  }

  // Monster retaliation shared by attacks and spell casts in combat.
  function monsterTurn() {
    if (!combat || combat.over) return
    // Bindor's Deceit: the smoke holds for exactly 2 incoming swings.
    if (combat.deceitLeft && combat.deceitLeft > 0) {
      combat.deceitLeft--
      combat.log.push("The smoke blinds the " + combat.monster.name
        + " — attack negated! (" + combat.deceitLeft + " left)")
      return
    }
    if (combat.slipNext) {
      combat.slipNext = false
      combat.log.push("The " + combat.monster.name + " loses its footing — no attack!")
      return
    }
    var state = combatState()
    var accRoll = Dice.roll(combat.monster.accExpr)
    var mres = Combat.defend(state, { acc: accRoll, dmg: 0,
                                      isMagic: combat.monster.isMagic })
    if (mres.hit) {
      var mdmg = Dice.roll(combat.monster.damageExpr)
      // Wind/Water Shield negate one attack per cast.
      var ws = getActive("Wind Shield"), wa = getActive("Water Shield")
      if ((mres.target === "DV" && ws) || (mres.target === "MDV" && wa)) {
        combat.log.push("Your " + (mres.target === "DV" ? "Wind" : "Water")
          + " Shield negates the blow!")
        activeSpells = activeSpells.filter(function (a) {
          return a.name !== "Wind Shield" && a.name !== "Water Shield"
        })
        return
      }
      combat.log.push("The " + combat.monster.name + " attacks you for "
        + mdmg + " damage!")
      heroHp = Math.max(0, heroHp - mdmg)
      // Revengeance Barrier reflects.
      var rb = getActive("Revengeance Barrier")
      if (rb) {
        var rdmg = Spells.rollFormula(rb.def.Damage, heroStats.int || 0, Math.random)
        combat.monster.hp -= rdmg
        combat.log.push("The barrier retaliates for " + rdmg + " damage!")
        if (combat.monster.hp <= 0) {
          combat.log.push("The " + combat.monster.name + " dies!")
          combat.over = true; combat.won = true
          resolveKill(); return
        }
      }
      if (combat.monster.isPoison && !combat.poisoned) {
        combat.poisoned = true
        combat.log.push("You feel poison coursing through your veins!")
      }
      if (heroHp <= 0) { die(); return }
    } else {
      combat.log.push("The " + combat.monster.name + " attacks — misses.")
      // Ice Shield decays on enemy misses by the would-be roll.
      var ice = getActive("Ice Shield")
      if (ice && ice.custom.shieldHp > 0) {
        var would = Dice.roll(combat.monster.damageExpr)
        var left = ice.custom.shieldHp - would
        combat.log.push("The ice shield absorbs " + would
          + " (shield " + Math.max(0, left) + " left)")
        activeSpells = activeSpells.map(function (a) {
          if (a.name !== "Ice Shield") return a
          return { name: a.name, def: a.def, stepsLeft: a.stepsLeft,
                   custom: { shieldHp: left } }
        })
        if (left <= 0) {
          combat.log.push("The ice shield shatters!")
          activeSpells = activeSpells.filter(function (a) { return a.name !== "Ice Shield" })
        }
      }
    }
  }

  // Kill rewards shared by weapon and spell kills.
  property bool luckPending: false
  function resolveKill() {
    grantXp(combat.monster.xp, combat.monster.name)
    if (combat.poisoned) {
      if (poisonImmune()) combat.log.push("Your amulet wards off the poison.")
      else {
        heroPoison = Poison.start(combat.monster.poisonDamage || 1)
        combat.log.push("The poison takes hold. (" + heroPoison.dmg
          + " damage per step, " + heroPoison.movesLeft + " steps)")
      }
    }
    var drop = luckPending
      ? forceDrop()
      : Drops.rollDrop(equipmentTable, floorNum, Math.random)
    luckPending = false
    if (drop) {
      var packed = giveLoot(drop)
      combat.log.push("It drops a " + drop.Name
        + (drop.Enchant ? " (+" + drop.Enchant + ")" : "") + "!"
        + (packed ? "" : " — but your pack is full; it is left behind."))
    } else {
      combat.log.push("It drops nothing.")
    }
    // Spell drop: independent roll; re-learning a known spell fizzles.
    var sdrop = Drops.rollSpellDrop(spellTable, floorNum, Math.random)
    if (sdrop) {
      if (hasSpell(sdrop.Name)) {
        combat.log.push("You already know " + sdrop.Name + ".")
      } else {
        spells = spells.concat([{ Name: sdrop.Name }])
        combat.log.push("You learn the spell " + sdrop.Name + "!")
      }
    }
    combatVictory = true
  }
  // Imbibe Luck: roll items until one lands (same table/rank gating).
  function forceDrop() {
    for (var tries = 0; tries < 20; tries++) {
      var d = Drops.rollDrop(equipmentTable, floorNum, Math.random)
      if (d) return d
    }
    return null
  }
  function turn(rel) {
    if (combat) return
    pos = Dungeon.turn(pos, rel); debugVista()
  }

  // ---- Encounter lifecycle --------------------------------------------------
  // Called after every successful tile change. Omatrix's pickup raises the
  // spawn rate on F50 by +5% (0.15 -> 0.20) and adds Omakron to the pool
  // while hasOmatrix.
  function trySpawnEncounter() {
    if (monsterTable.length === 0) return   // table not loaded yet (boot race)
    var pool = monsterTable
    if (floorNum === 50 && hasOmatrix) {
      // Roll the flat 15%, then the Omatrix's extra 5% if the first missed.
      // Pool = F50 ± (1d3-1), with Omakron injected.
      if (Math.random() >= 0.20) return
      var omakron = null
      for (var i = 0; i < monsterTable.length; i++)
        if (monsterTable[i].Name === "Omakron") { omakron = monsterTable[i]; break }
      var others = []
      var k = Math.floor(Math.random() * 3)          // 1d3 - 1
      var target = 50 + k
      for (var i = 0; i < monsterTable.length; i++) {
        var d = monsterTable[i].Depth
        if (d === 50 || d === target) others.push(monsterTable[i])
      }
      if (omakron) others.push(omakron)
      if (others.length === 0) return
      var row = others[Math.floor(Math.random() * others.length)]
      combat = CombatLoop.newEncounter(row)
      bumpCombatLog()
      return
    }
    var row = Monsters.rollSpawn(monsterTable, floorNum, Math.random)
    if (!row) return
    combat = CombatLoop.newEncounter(row)
    bumpCombatLog()
  }
  // Dev hotkey (paired with ']' vista trace): force an encounter against the
  // first Depth-1 monster in the table (the Rat) so the combat loop is
  // testable without walking for a 0.1% spawn.
  function debugSpawnEncounter() {
    if (combat) return
    var row = null
    for (var i = 0; i < monsterTable.length; i++)
      if (monsterTable[i].Depth === 1) { row = monsterTable[i]; break }
    if (!row) return
    combat = CombatLoop.newEncounter(row)
    console.log("omakon DEBUG forced encounter: " + row.Name)
    bumpCombatLog()
  }
  function bumpCombatLog() {
    combatLogVersion++
    // Pin the log to the newest line. combatLog is a component-scope id,
    // reachable from root functions.
    if (combatLog) combatLog.positionViewAtEnd()
  }

  // Player acts (the left-card click). Strike first; if the monster
  // survives, it retaliates in the same click (design: player-first,
  // retaliate-only — the "round" resolves in one action). On a kill the
  // overlay HOLDS (combatVictory) with the reward lines on screen; the
  // One player combat action = weapon strike(s) + monster retaliation.
  // Haste: player attacks twice per click while active.
  function combatAct() {
    if (!combat) return
    if (combat.over) {          // victory-hold click → return to exploration
      combat = null
      combatVictory = false
      saveRun()
      return
    }
    var state = combatState()
    var wlabel = weaponLabel(rightHand)
    var strikes = isSpellActive("Haste") ? 2 : 1
    for (var round = 0; round < strikes && !combat.over; round++) {
      if (isBookOfPower(rightHand)) {
        // Book of Power: "cannot be dodged" — skips the ACC/DV roll entirely
        // and applies damage directly. Damage still uses the weapon's own
        // pool (10 base) + STR + d4 via Combat.attack's damage branch; the
        // ACC branch is bypassed here so the log reads correctly (no
        // "∞+2d6=∞" noise).
        var pdmg = Combat.baseDamageOf(state) + Dice.roll("1d4")
        combat.monster.hp -= pdmg
        combat.log.push("You read from the Book of Power — " + combat.monster.name
          + " takes " + pdmg + " damage!")
        if (combat.monster.hp <= 0) {
          combat.log.push("The " + combat.monster.name + " dies!")
          combat.over = true
          combat.won = true
          break
        }
        continue
      }
      var res = Combat.attack(state, combat.monster)
      if (!res.hit) {
        combat.log.push("You strike at the " + combat.monster.name + " with " + wlabel + " — miss. (ACC " + res.accuracy + "+2d6=" + res.accRoll + " vs DV " + res.dv + ")")
      } else if (isSapienCannon(rightHand)) {
        // Rider: any hit obliterates the target. Damage field is ignored
        // (the 1 DAM the table suggests is a bookkeeping value only).
        combat.monster.hp = 0
        combat.log.push("The Sapien Cannon's beam disintegrates the "
          + combat.monster.name + "!")
        combat.over = true
        combat.won = true
        break
      } else {
        var dmg = res.damage
        combat.log.push("You strike the " + combat.monster.name + " with " + wlabel + " for " + dmg + " damage (" + res.baseDamage + "+" + res.d4 + ")!")
        combat.monster.hp -= dmg
        if (combat.monster.hp <= 0) {
          combat.log.push("The " + combat.monster.name + " dies!")
          combat.over = true
          combat.won = true
          break
        }
      }
    }
    // Fireball burn ticks at the start of each ROUND (per round in combat).
    if (!combat.over && combat.burn && combat.burn.rounds > 0) {
      combat.monster.hp -= combat.burn.dmg
      combat.burn.rounds--
      combat.log.push("The flames lick the " + combat.monster.name
        + " for " + combat.burn.dmg + " damage. (" + combat.burn.rounds + " rounds left)")
      if (combat.burn.rounds <= 0) combat.burn = null
      if (combat.monster.hp <= 0) {
        combat.log.push("The " + combat.monster.name + " dies!")
        combat.over = true; combat.won = true
      }
    }
    if (!combat.over) monsterTurn()
    // Count this round against any active spell durations.
    tickActiveSpells()
    if (combat && combat.over && combat.won) resolveKill()
    bumpCombatLog()
  }

  // Flee attempt (FLEE button): one full player action. Success ends the
  // encounter in place (no move); failure gives the monster its normal
  // retaliation swing (monsterTurn — Slip/Deceit/shields all apply).
  // Chance = CombatLoop.fleeChance(DEX): 25% at 4 DEX, log2-shaped up.
  function attemptFlee() {
    if (!combat) return
    if (combat.over) return
    var p = CombatLoop.fleeChance(heroStats.dex || 0)
    if (Math.random() < p) {
      combat.log.push("You slip away from the " + combat.monster.name
        + "! (" + Math.round(p * 100) + "%)")
      // Hold the overlay one beat so the escape line is readable; the
      // next monster-card click dismisses via combatAct's over-branch.
      combat.over = true
      combat.fled = true
      bumpCombatLog()
      saveRun()
      return
    }
    combat.log.push("You try to flee — the " + combat.monster.name
      + " cuts you off! (" + Math.round(p * 100) + "%)")
    monsterTurn()
    tickActiveSpells()
    bumpCombatLog()
    if (combat && combat.over && combat.won) resolveKill()
  }

  // Put a dropped instance into the first empty pack slot. Returns true
  // if packed; if the pack is full the item is lost (the caller logs it).
  function giveLoot(drop) {
    if (!drop) return false
    for (var i = 0; i < pack.length; i++) {
      if (!pack[i]) {
        var next = pack.slice()
        next[i] = drop
        pack = next
        return true
      }
    }
    return false
  }

  // Dev trace: dumps the current cell, facing, and vista flags so on-screen
  // renders can be cross-checked against the maze data (journalctl).
  // One SHORT line per slice — long JSON lines get truncated by journalctl's
  // line width, which made the old format useless past v1. Press ']' in
  // game mode.
  function debugVista() {
    var v = Dungeon.vista(floor, pos)
    console.log("omakon pos=" + pos.row + "," + pos.col + " face=" + pos.facing
      + " F" + floorNum + " seed=" + floorSeed
      + " w0=" + (wallAt(0) ? 1 : 0))
    for (var i = 0; i < v.length; i++) {
      var s = v[i]
      console.log("omakon v" + (i + 1)
        + " " + (s.visible ? "vis" : "hid")
        + " l=" + (s.left ? 1 : 0)
        + " r=" + (s.right ? 1 : 0)
        + " e=" + (s.end ? 1 : 0)
        + " sL=" + sideShort(s.sideL)
        + " sR=" + sideShort(s.sideR))
    }
  }
  // Compact side-passage code: <partition><endDist(9=continues)><feature>
  // e.g. "04d" = open partition, ends 4 cells out on the downstairs.
  function sideShort(s) {
    if (!s) return "-"
    var t = s.terminus === "up" ? "u" : s.terminus === "down" ? "d" : "-"
    return (s.side ? 1 : 0) + (s.endDist === 0 ? 9 : s.endDist) + t
  }
  // ---- Window ---------------------------------------------------------------
  PanelWindow {
    id: win
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: 640
    implicitHeight: 480

    WlrLayershell.namespace: "omarchy-omakon"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    property bool focusPrimed: false
    onVisibleChanged: {
      if (visible) {
        focusPrimed = false
        focusPrimeTimer.restart()
      }
    }

    Timer {
      id: focusPrimeTimer
      interval: 120
      onTriggered: win.focusPrimed = true
    }

    Rectangle {
      id: frame
      anchors.fill: parent
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      focus: true

      Keys.onEscapePressed: {
        if (root.infoSlot >= 0) { root.infoSlot = -1; return }
        if (root.popupMode === "blink") { root.cancelBlink(); return }
        if (root.popupMode === "enchant") { root.cancelEnchant(); return }
        if (root.popupMode === "omatrix") { root.cancelOmatrixDiscard(); return }
        if (root.popupMode !== "none") root.popupMode = "none"
        else if (root.mode === "menu") root.close()
        else root.close()      // close always saves in game mode
      }

      // ']' — dump the vista trace (short lines, journalctl-friendly).
      // 'f' — (dev) force a Depth-1 encounter so the combat loop is testable.
      Keys.onPressed: function(event) {
        if (root.mode === "game" && event.key === 0x5d /* ] */) root.debugVista()
        if (root.mode === "game" && event.key === Qt.Key_F) root.debugSpawnEncounter()
      }

      Component.onCompleted: {
        if (root.mode === "loading") root.bootLoad()
      }

      // ---- Title strip ------------------------------------------------------
      Rectangle {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 28
        color: "transparent"
        border.color: Color.menu.border
        border.width: 2

        Text {
          anchors.centerIn: parent
          text: "DUNGEONS OF OMAKON"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.bold: true
          font.pixelSize: 13
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 8
          text: "✕"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: 12
          MouseArea {
            anchors.fill: parent
            onClicked: root.close()
          }
        }
      }

      // ---- Viewport: pseudo-3D first-person render --------------------------
      Rectangle {
        id: viewport
        visible: root.mode === "game"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        anchors.bottom: hud.top
        anchors.margins: 8
        color: "#05060a"           // deep-space overdraw guard
        border.color: Color.menu.border
        border.width: 2
        clip: true

        readonly property color wallNear: "#8a7f66"
        readonly property color wallFar:  "#565045"
        readonly property color endNear:  "#6e6552"
        readonly property color endFar:   "#3c3830"
        readonly property color voidCol:  "#0a0b10"

        // Sky (ceiling) and floor slabs.
        Rectangle { anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; height: parent.height / 2
                    color: "#11131c" }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: parent.bottom; height: parent.height / 2
                    color: "#1b1712" }

        // Pseudo-3D cell-forward renderer. The view is composed of trapezoid
        // wall Ungl panels whose footprints match the perspective of a
        // 2-node-deep corridor; panels only render where the maze data says
        // there is a wall, so what you see IS the floor plan.
        //
        // Geometry: forward cell face = full viewport. Depth-1 end wall is a
        // centered rect 0.62w x 0.62h covering 0.19->0.81 on both axes. The
        // depth-1 side corridors (when that cell's left/right is OPEN) show
        // through the strips left/right of the end rect; when closed, side
        // wall trapezoids fill frame->end edges. Same construction repeats
        // between the end rect (0.62) and depth-2 rect (0.30).
        Canvas {
          id: scene3d
          anchors.fill: parent

          onPaint: {
            var ctx = getContext("2d")
            var W = width, H = height
            // Canvas persists between paints — clear fully first or old wall
            // slices linger and smear over the new frame.
            ctx.clearRect(0, 0, W, H)
            var W2 = W / 2, H2 = H / 2

            // face geometry at depth d (0 = current cell, 1..4): half-size of
            // the projected square face, centered. Scale series uses roughly
            // harmonic falloff (1/(d+1)) so successive cells read at even
            // visual steps; with depth-4 the farthest perceptible segment is
            // four cells away — enough to see a three-cells-away side branch
            // or a four-cells-away end wall clearly.
            var base = Math.min(W2, H2)
            var half = [base, base * 0.62, base * 0.40, base * 0.26, base * 0.17]

            function faceRect(d) {
              if (d === 0) return { x: 0, y: 0, w: W, h: H }
              return { x: W2 - half[d], y: H2 - half[d], w: half[d] * 2, h: half[d] * 2 }
            }

            function wallQuad(d, side) { // side: -1 left, +1 right; d = cell depth
              return sideQuad(d - 1, d, side)
            }

            function fillQuad(pts, color) {
              ctx.beginPath()
              ctx.moveTo(pts[0][0], pts[0][1])
              for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
              ctx.closePath()
              ctx.fillStyle = color
              ctx.fill()
            }
            function fillFace(d, color) {
              var r = faceRect(d)
              ctx.fillStyle = color
              ctx.fillRect(r.x, r.y, r.w, r.h)
            }

            var v = root.view
            if (v.length !== 4) return

            // Bright close → dark far (classic flashlight falloff).
            var colEnd  = ["#6e6552", "#51493c", "#3c362c", "#2a2620"]
            var colSide = ["#8a7f66", "#605847", "#453f34", "#332e27"]
            // Side-passage interiors: lit near, receding dark far. The
            // mouth of an open side is NEVER sky/floor — looking through
            // it shows the passage's dark, whatever is at its end.
            var colPass  = ["#282018", "#1c1611", "#13100c", "#0c0a08"]
            // A staircase where the side passage ends reads warm.
            var colStair = ["#7a5f2e", "#564522", "#382e19", "#241e12"]

            // sideQuad(a, b, side): the side-column strip between face
            // boundaries a and b (a < b, 0..4; boundary 0 = viewport edge).
            // wallQuad(d, side) is sideQuad(d-1, d, side).
            function sideQuad(a, b, side) {
              function ex(bb) {
                if (bb === 0) return side < 0 ? 0 : W
                var f = faceRect(bb)
                return side < 0 ? f.x : f.x + f.w
              }
              function ey0(bb) { return bb === 0 ? 0 : faceRect(bb).y }
              function ey1(bb) { return bb === 0 ? H : faceRect(bb).y + faceRect(bb).h }
              return [[ex(a), ey0(a)], [ex(b), ey0(b)],
                      [ex(b), ey1(b)], [ex(a), ey1(a)]]
            }
            function wallQuad(d, side) { return sideQuad(d - 1, d, side) }

            // paintSidePassage(d, side, endDist, terminus): the side
            // passage one cell off-axis at depth d (d=0 = your own cell).
            // endDist (from the vista trace): 1 = dead-end alcove, 2..4 =
            // hallway continues that many cells, 0 = still open past the
            // 4th band (render the dark continuation, no visible terminus).
            // The passage's MOUTH is the band-d face edge (boundary d);
            // its interior spans bands d..B-1 and its terminus wall spans
            // band B = d + endDist (clamped to 4). Together they tile the
            // side column exactly — no sky/floor leak in the opening.
            function paintSidePassage(d, side, sd, term) {
              var B = (sd === 0) ? 4 : Math.min(d + sd, 4)
              fillQuad(sideQuad(d, B - 1, side), colPass[Math.min(d, 3)])
              if (sd >= 1) {
                var ci = Math.min(B - 1, 3)
                fillQuad(sideQuad(B - 1, B, side),
                         term !== "none" ? colStair[ci] : colEnd[ci])
              }
            }

            // Perception rules (what the canvas may paint, per vista data):
            //   * cell(d).left/right: wall on that cell's side edge → slab
            //     spanning face(d-1) -> face(d) (pass B, over the passages).
            //   * cell(d).end: wall on that cell's far edge → face(d).
            //   * An OPEN side at depth d shows the side passage: dark
            //     interior + terminus wall from the trace (pass A). The
            //     partition slabs of the continuing cells (their side
            //     walls) are painted in pass B over the interior, so a
            //     hallway behind a turn still reads: mouth → dark →
            //     inner walls → end wall (or stairs).
            //   * wallAt(0): forward edge of YOUR cell is blocked → whole
            //     viewport (nose against the wall).

            // Pass A: side-passage interiors + terminus walls. Nearer
            // depths paint LATER (over deeper ones) — the mouth of a
            // shallower opening is the same physical hallway, one cell
            // nearer, and must read on top.
            for (var d = 4; d >= 0; d--) {
              if (d === 0) {
                if (!root.wallAt(3)) {
                  var ld0 = (root.pos.facing + 3) % 4
                  var tL0 = Dungeon.traceSidePassage(root.floor,
                    root.pos.row + Dungeon.DR[ld0], root.pos.col + Dungeon.DC[ld0],
                    root.pos.facing)
                  paintSidePassage(0, -1, tL0.endDist, tL0.terminus)
                }
                if (!root.wallAt(1)) {
                  var rd0 = (root.pos.facing + 1) % 4
                  var tR0 = Dungeon.traceSidePassage(root.floor,
                    root.pos.row + Dungeon.DR[rd0], root.pos.col + Dungeon.DC[rd0],
                    root.pos.facing)
                  paintSidePassage(0, 1, tR0.endDist, tR0.terminus)
                }
              } else {
                var sl = v[d - 1]
                if (sl.visible && !sl.left && sl.sideL)
                  paintSidePassage(d, -1, sl.sideL.endDist, sl.sideL.terminus)
                if (sl.visible && !sl.right && sl.sideR)
                  paintSidePassage(d, 1, sl.sideR.endDist, sl.sideR.terminus)
              }
            }

            // Ring r of the side column (sideQuad(r, r+1) = wallQuad(r+1))
            // is the side wall of corridor cell depth r. Gate: ring 0 =
            // your own cell (wallAt(±1)); ring r >= 1 = v[r-1].left/right.
            if (root.wallAt(3)) fillQuad(wallQuad(1, -1), colSide[0])
            if (root.wallAt(1)) fillQuad(wallQuad(1, 1), colSide[0])
            for (var n = 1; n < 4; n++) {           // rings 1..3
              var sl2 = v[n - 1]
              if (!sl2.visible) continue
              if (sl2.left) fillQuad(wallQuad(n + 1, -1), colSide[n])
              if (sl2.right) fillQuad(wallQuad(n + 1, 1), colSide[n])
            }
            for (var d2 = 1; d2 <= 4; d2++) {
              var slice = v[d2 - 1]
              if (!slice.visible) continue
              if (slice.end) fillFace(d2, colEnd[d2 - 1])
            }
            if (root.wallAt(0)) fillFace(0, colEnd[0])
          }

          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          // root.pos gets a new object identity on every move/turn (unlike
          // `view`, a readonly computed var whose binding never notifies),
          // so this reliably repaints the scene each step.
          property var repaintKey: root.pos
          onRepaintKeyChanged: requestPaint()
          Component.onCompleted: requestPaint()
        }

        // Floor number tag, top-left of the viewport.
        Text {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: 6
          text: "FLOOR " + root.floorNum
          color: Qt.darker(Color.menu.text, 1.6)
          font.family: Style.font.menuFamily
          font.pixelSize: 10
        }

        // Stairs-down glyph when standing on (or directly facing) the
        // downstairs node. No ascent glyph: there is no going back up.
        Text {
          anchors.centerIn: parent
          visible: {
            if (root.floor.nodes[root.pos.row][root.pos.col].feature === "down") return true
            return root.view.length === 2 && root.view[0].feature === "down" && !root.view[0].end
          }
          text: "⬇"
          color: "#d0b040"
          font.family: Style.font.menuFamily
          font.bold: true
          font.pixelSize: 40
        }

        // Directional arrows: ◀ ▶ turn, ▲ ▼ step forward/back, greyed by
        // real wall state from Dungeon.hasWall.
        component Arrow: Text {
          property int dir: 0          // 0 fwd, 1 right, 2 back, 3 left
          property bool blocked: false
          font.family: Style.font.menuFamily
          font.pixelSize: 22
          color: blocked ? Qt.darker(Color.menu.text, 2.2) : Color.menu.text
          MouseArea {
            anchors.fill: parent
            enabled: !blocked
            onClicked: {
              if (parent.dir === 3) root.turn(-1)
              else if (parent.dir === 1) root.turn(1)
              else if (parent.dir === 0) root.move(0)
              else root.move(2)
            }
          }
        }

        Arrow { dir: 0; text: "▲"
          blocked: root.wallAt(0)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top; anchors.topMargin: 8 }
        Arrow { dir: 3; text: "◀"
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left; anchors.leftMargin: 8 }
        Arrow { dir: 1; text: "▶"
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right; anchors.rightMargin: 8 }
        Arrow { dir: 2; text: "▼"
          blocked: root.wallAt(2)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom; anchors.bottomMargin: 8 }

        // Descend button — appears when standing on the downstairs.
        Rectangle {
          id: descendBtn
          visible: root.floor.nodes[root.pos.row][root.pos.col].feature === "down"
            && !root.descending
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 40
          width: 120
          height: 30
          color: "#d0b040"
          border.color: Color.menu.border
          border.width: 2
          Text {
            anchors.centerIn: parent
            text: "DESCEND"
            color: "#1b1712"
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 13
          }
          MouseArea { anchors.fill: parent; onClicked: root.beginDescend() }
        }

        // Ascend button — appears only while the player holds the Omatrix
        // on Floor 50 and is standing on the exit staircase.
        Rectangle {
          id: ascendBtn
          visible: root.onExitStairs()
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 72
          width: 120
          height: 30
          color: "#b03030"
          border.color: Color.menu.border
          border.width: 2
          Text {
            anchors.centerIn: parent
            text: "ASCEND"
            color: "#f8e8e0"
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 13
          }
          MouseArea { anchors.fill: parent; onClicked: root.winGame() }
        }

        // ---- Automap (toggleable; top-right corner) -------------------------
        Rectangle {
          id: automap
          visible: root.automapOn
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 8
          width: mapGrid.width + 8
          height: mapGrid.height + 8
          color: Qt.rgba(0, 0, 0, 0.7)
          border.color: Color.menu.border
          border.width: 1

          Grid {
            id: mapGrid
            anchors.centerIn: parent
            rows: 6
            columns: 7
            spacing: 1

            Repeater {
              model: 42
              Item {
                property int c: index % 7
                property int r: Math.floor(index / 7)
                property bool seen: root.explored[r + "," + c] === true
                property bool hero: c === root.pos.col && r === root.pos.row
                property string feat: root.floor.nodes[r][c].feature
                property bool isDown: feat === "down"
                property bool isOmatrix: root.omatrixPos === (r + "," + c)
                property bool isExit: root.exitsPos === (r + "," + c) && root.hasOmatrix
                width: 12
                height: 12

                Rectangle {
                  anchors.fill: parent  // the node's floor tile
                  color: !seen ? "black"
                    : hero ? "#e0c040"
                    : feat === "down" ? "#b09030"
                    : "#5b5548"
                  border.color: Qt.darker(Color.menu.border, 1.5)
                  border.width: 1
                }
                // Beacon highlight: gold ring around the downstairs tile
                // while the beacon is lit. Underlays the wall bars so the
                // frame stays visible even on the tile's edges.
                Rectangle {
                  visible: root.beaconOn && isDown
                  anchors.fill: parent
                  color: "transparent"
                  border.color: root.gold
                  border.width: 2
                }
                // Omatrix tile (Floor 50, pre-pickup): pulsing gold frame.
                Rectangle {
                  visible: isOmatrix
                  anchors.fill: parent
                  color: "transparent"
                  border.color: "#ffd040"
                  border.width: 2
                }
                // Exit staircase (Floor 50, while the player holds the
                // Omatrix): red-gold frame — distinct from the beacon gold.
                Rectangle {
                  visible: isExit
                  anchors.fill: parent
                  color: "transparent"
                  border.color: "#ff6a50"
                  border.width: 2
                }
                // Per-edge wall lines, overlaid on the tile so the automap
                // doubles as a debugging truth table for the 3D render.
                Rectangle { // N
                  visible: seen && root.floor.nodes[r][c].n
                  anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                  height: 2; color: "#f0e0c0"
                }
                Rectangle { // E
                  visible: seen && root.floor.nodes[r][c].e
                  anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                  width: 2; color: "#f0e0c0"
                }
                Rectangle { // S
                  visible: seen && root.floor.nodes[r][c].s
                  anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                  height: 2; color: "#f0e0c0"
                }
                Rectangle { // W
                  visible: seen && root.floor.nodes[r][c].w
                  anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                  width: 2; color: "#f0e0c0"
                }
                // Facing arrow over the hero tile.
                Text {
                  anchors.centerIn: parent
                  visible: hero
                  text: ["▲", "▶", "▼", "◀"][root.pos.facing]
                  color: "#1b1712"
                  font.family: Style.font.menuFamily
                  font.bold: true
                  font.pixelSize: 9
                }
              }
            }
          }
        }
        // ---- Combat overlay (2026-08-31 design) ------------------------------
        // Two panels over the viewport: LEFT = monster card (the attack
        // target — click the glyph to act), RIGHT = scrolling combat log.
        // z:50 keeps them above the automap and dissolve layer.
        Rectangle {
          id: combatOverlay
          visible: root.combatView !== null
          anchors.fill: parent
          color: "transparent"
          z: 50

          // Dim the scene under the fight.
          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            enabled: false
          }

          // LEFT — monster card: glyph, name, HP bar. Clicking the card
          // acts with the current right-hand weapon.
          Rectangle {
            id: monsterCard
            width: 150
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 10
            color: Color.menu.background
            border.color: Color.menu.border
            border.width: 2

            readonly property string tierColor: {
              if (!root.combatView) return Color.menu.text
              var c = root.combatView.color
              return c === "red" ? "#e06060"
                   : c === "yellow" ? "#e0c050" : Color.menu.text
            }

            Column {
              anchors.centerIn: parent
              spacing: 6
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ENCOUNTER"
                color: Qt.darker(Color.menu.text, 1.6)
                font.family: Style.font.menuFamily
                font.bold: true
                font.pixelSize: 10
              }
              // Monster glyph — the target. Nerd Font pinned: PUA glyphs
              // vanish if OMARCHY_MENU_FONT points elsewhere.
              Text {
                id: monsterGlyph
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.combatView ? (root.combatView.icon || "?") : "?"
                color: root.combatView && root.combatView.victory
                  ? "#8860a0" : monsterCard.tierColor
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 56
              }
              Text {
                id: monsterName
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.combatView ? root.combatView.name : ""
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.bold: true
                font.pixelSize: 13
              }
              // Monster HP bar.
              Rectangle {
                width: monsterCard.width - 28
                height: 12
                anchors.horizontalCenter: parent.horizontalCenter
                color: "transparent"
                border.color: Color.menu.border
                border.width: 1
                Rectangle {
                  anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                  width: root.combatView
                    ? (root.combatView.hp / root.combatView.hpMax) * (parent.width - 2) : 0
                  color: Qt.darker(monsterCard.tierColor, 1.3)
                }
                Text {
                  anchors.centerIn: parent
                  text: root.combatView
                    ? root.combatView.hp + "/" + root.combatView.hpMax : ""
                  font.pixelSize: 9; font.family: Style.font.menuFamily
                  color: Color.menu.text
                }
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 10
              text: root.combatView && root.combatView.victory
                ? "CLICK TO CONTINUE" : "CLICK TO ATTACK"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              z: 10
              onClicked: root.combatAct()
            }
          }

          // RIGHT — combat log, newest line at the bottom.
          Rectangle {
            width: 230
            height: 240
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            color: Qt.rgba(0.04, 0.05, 0.08, 0.96)
            border.color: Color.menu.border
            border.width: 2

            Text {
              id: combatLogTitle
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: 8
              anchors.leftMargin: 8
              text: "COMBAT LOG"
              color: Qt.darker(Color.menu.text, 1.4)
              font.family: Style.font.menuFamily
              font.bold: true
              font.pixelSize: 10
            }
            ListView {
              id: combatLog
              anchors.top: combatLogTitle.bottom
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: 8
              spacing: 3
              model: root.combatView ? root.combatView.log : []
              clip: true
              delegate: Text {
                width: combatLog.width
                text: modelData
                color: /dies!|slain/.test(modelData)
                  ? "#e06060" : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: 11
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        // ---- Pixel-dissolve transition into the next floor -------------------
        // Active while root.descending: a 26x20 grid of black pixels whose
        // opacity animates 0 -> 1 in pseudo-random order over ~500ms, the
        // floor state swaps at full dissolve, then the pixels fade back out.
        Item {
          id: dissolveLayer
          anchors.fill: parent
          visible: root.descending
          onVisibleChanged: if (visible) step = 0

          property int step: 0
          readonly property int cells: 26 * 20

          Repeater {
            model: dissolveLayer.visible ? dissolveLayer.cells : 0
            Rectangle {
              property int cx: index % 26
              property int cy: Math.floor(index / 26)
              // Stable pseudo-random order key per cell.
              property real ord: ((index * 137 + Math.floor(index / 7) * 61) % 521) / 521.0
              x: cx * (dissolveLayer.width / 26)
              y: cy * (dissolveLayer.height / 20)
              width: Math.ceil(dissolveLayer.width / 26) + 1
              height: Math.ceil(dissolveLayer.height / 20) + 1
              color: "#05060a"
              opacity: (dissolveLayer.step - ord * 520) > 0 ? 1 : 0
            }
          }

          Timer {
            id: dissolveTimer
            interval: 16
            repeat: true
            running: root.descending
            onTriggered: {
              dissolveLayer.step += 20
              if (dissolveLayer.step >= 560) root.completeDescend()
              // completeDescend sets descending = false; the running binding
              // then evaluates to false on its own (never assign `running`
              // imperatively — it clobbers the binding and the next
              // descent's dissolve never restarts, leaving root.descending
              // stuck true, which hid the DESCEND button the second time).
            }
          }
        }
      }

      // ---- Mode overlay screens (Phase 4) -----------------------------------
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: 28
        visible: root.mode === "menu" || root.mode === "newgame"
          || root.mode === "archive" || root.mode === "dead" || root.mode === "loading"
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 2
        z: 20

        // MENU
        Column {
          visible: root.mode === "menu"
          anchors.centerIn: parent
          spacing: 22

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "DUNGEONS OF OMAKON"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 18
          }
          Repeater {
            model: [
              { label: "NEW GAME", act: "newgame" },
              { label: "ARCHIVE", act: "archive" }
            ]
            Rectangle {
              property var m: modelData
              width: 160; height: 34
              color: Color.menu.selectedBackground
              border.color: Color.menu.border
              border.width: 2
              anchors.horizontalCenter: parent.horizontalCenter
              Text {
                anchors.centerIn: parent
                text: m.label
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.bold: true
                font.pixelSize: 13
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (m.act === "newgame") root.startNewGame()
                  else root.showArchive()
                }
              }
            }
          }
        }

        // NEWGAME name entry
        Column {
          visible: root.mode === "newgame"
          anchors.centerIn: parent
          spacing: 14

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "NAME YOUR ADVENTURER"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 15
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220; height: 36
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            TextInput {
              id: nameInput
              anchors.fill: parent
              anchors.margins: 6
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: 15
              maximumLength: 18
              focus: true
              Keys.onReturnPressed: root.confirmNewGame(text)
              Keys.onEnterPressed: root.confirmNewGame(text)
            }
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 140; height: 32
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            Text {
              anchors.centerIn: parent
              text: "BEGIN"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.bold: true; font.pixelSize: 12
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.confirmNewGame(nameInput.text)
            }
          }
        }

        // ARCHIVE
        Column {
          visible: root.mode === "archive"
          anchors.fill: parent
          anchors.margins: 16
          spacing: 6

          Text {
            text: "FALLEN HEROES"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true; font.pixelSize: 14
          }
          Rectangle { height: 1; width: parent.width; color: Color.menu.border }
          Repeater {
            model: root.archive
            Row {
              property var e: modelData
              spacing: 16
              Text { text: e.name; color: Color.menu.text
                     font.family: Style.font.menuFamily; font.pixelSize: 12; width: 120 }
              Text { text: e.started || ""; color: Qt.darker(Color.menu.text, 1.4)
                     font.family: Style.font.menuFamily; font.pixelSize: 11; width: 90 }
              Text { text: "FLOOR " + e.floor; color: "#b09030"
                     font.family: Style.font.menuFamily; font.pixelSize: 12; width: 70 }
              Text { text: "LVL " + e.level; color: Color.menu.text
                     font.family: Style.font.menuFamily; font.pixelSize: 12; width: 60 }
              Text { text: "SCORE " + e.score; color: Color.menu.text
                     font.family: Style.font.menuFamily; font.pixelSize: 12 }
            }
          }
          Text {
            visible: root.archive.length === 0
            text: "— no fallen heroes yet —"
            color: Qt.darker(Color.menu.text, 1.8)
            font.family: Style.font.menuFamily; font.pixelSize: 11
          }
          Rectangle {
            width: 120; height: 28
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            Text { anchors.centerIn: parent; text: "BACK"
                   color: Color.menu.text; font.family: Style.font.menuFamily
                   font.bold: true; font.pixelSize: 11 }
            MouseArea { anchors.fill: parent; onClicked: root.mode = "menu" }
          }
        }

        // DEAD
        Column {
          visible: root.mode === "dead"
          anchors.centerIn: parent
          spacing: 18

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "YOU HAVE FALLEN"
            color: "#a55555"
            font.family: Style.font.menuFamily
            font.bold: true; font.pixelSize: 20
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.runName + " of Floor " + root.floorNum
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: 13
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 170; height: 34
            color: Color.menu.selectedBackground
            border.color: Color.menu.border
            border.width: 2
            Text { anchors.centerIn: parent; text: "RETURN TO MENU"
                   color: Color.menu.text; font.family: Style.font.menuFamily
                   font.bold: true; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; onClicked: root.mode = "menu" }
          }
        }

        // LOADING
        Text {
          visible: root.mode === "loading"
          anchors.centerIn: parent
          text: "awakening the dungeon…"
          color: Qt.darker(Color.menu.text, 1.6)
          font.family: Style.font.menuFamily; font.pixelSize: 13
        }
      }

      Rectangle {
        id: hud
        visible: root.mode === "game"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        height: 64
        color: "transparent"
        border.color: Color.menu.border
        border.width: 2

        Row {
          anchors.centerIn: parent
          spacing: 14

          // Map toggle — permanently visible, leftmost in the HUD.
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.automapOn ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "▦"
                color: root.automapOn ? Color.menu.text : Qt.darker(Color.menu.text, 2.0)
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.automapOn = !root.automapOn
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "MAP"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // STATS — opens the character-sheet popup (heart icon per request).
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.popupMode === "stats" ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "♥"
                color: root.popupMode === "stats" ? Color.menu.text : Qt.darker(Color.menu.text, 2.0)
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea { anchors.fill: parent; onClicked: root.togglePopup("stats") }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "STATS"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // Left hand — shield slot
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: Color.menu.selectedBackground
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: root.leftHand
                  ? (root.iconOf(root.leftHand) || "·") : "⌾"
                color: root.leftHand ? Color.menu.text : Qt.darker(Color.menu.text, 2.2)
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("inventory")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "L"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // HP / MP read-outs
          Column {
            spacing: 4
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "HP " + root.heroHp + "/" + root.heroHpMax
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.bold: true
              font.pixelSize: 15
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "MP " + root.heroMp + "/" + root.heroMpMax
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.bold: true
              font.pixelSize: 15
            }
          }

          // Right hand — weapon slot
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: Color.menu.selectedBackground
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                // U+2694 (⚔) is NOT in the Nerd Font — falls back per glyph.
                // Empty hand shows the md-sword placeholder instead.
                text: root.rightHand
                  ? (root.iconOf(root.rightHand) || "󰓥") : "󰓥"
                color: Color.menu.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("inventory")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "R"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // Spell book button
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.popupMode === "spells" ? Color.menu.selectedBackground : "transparent"
              border.color: root.spells.length > 0 ? Color.menu.border : Qt.darker(Color.menu.border, 1.8)
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "✦"
                color: root.spells.length > 0 ? Color.menu.text : Qt.darker(Color.menu.text, 2.0)
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("spells")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "SPL"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // Inventory button
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              color: root.popupMode === "inventory" ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "▤"
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.togglePopup("inventory")
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "INV"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }

          // Flee button — only live mid-fight; greyed out otherwise.
          Column {
            spacing: 2
            Rectangle {
              width: 44
              height: 40
              property bool armed: root.combat && !root.combat.over && !root.combat.won
              color: "transparent"
              border.color: armed ? Color.menu.border : Qt.darker(Color.menu.border, 1.8)
              border.width: 2
              Text {
                anchors.centerIn: parent
                text: "󰜍"  // md-run U+F070D
                color: parent.armed ? Color.menu.text : Qt.darker(Color.menu.text, 2.0)
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                onClicked: if (parent.armed) root.attemptFlee()
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "FLEE"
              color: Qt.darker(Color.menu.text, 1.8)
              font.family: Style.font.menuFamily
              font.pixelSize: 9
            }
          }
        }

        // ---- Stats popup (STATS button) — read-only view ------------------------
        Rectangle {
          visible: root.popupMode === "stats"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 320
          height: 250
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 10
          Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Text { text: "CHARACTER SHEET"; font.bold: true; font.pixelSize: 12
              font.family: Style.font.menuFamily; color: Color.menu.text }
            Rectangle { width: parent.width; height: 1; color: Color.menu.border }

            Text { text: "LVL " + root.heroLevel + "  " + root.runName; font.pixelSize: 11
              font.family: Style.font.menuFamily; color: Color.menu.text }
            Text { text: "HP " + root.heroHp + "/" + root.heroHpMax
                   + "    MP " + root.heroMp + "/" + root.heroMpMax
              font.pixelSize: 11; font.family: Style.font.menuFamily; color: Color.menu.text }

            // EXP bar, e.g. EXP [|||||  ] 75/100
            Text { text: "EXP"; font.pixelSize: 10; font.family: Style.font.menuFamily;
              color: Qt.darker(Color.menu.text, 1.6) }
            Rectangle {
              width: parent.width; height: 12
              color: "transparent"; border.color: Color.menu.border; border.width: 1
              Rectangle {
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: (parent.width * Math.min(1, (root.heroXp % 100) / 100)) - 2
                color: "#b09030"
              }
              Text {
                anchors.centerIn: parent
                text: (root.heroXp % 100) + "/100"
                font.pixelSize: 9; font.family: Style.font.menuFamily
                color: Color.menu.text
              }
            }

            // Stat scores (left, vertical) with the equipped-items list
            // (right, vertical), both below the EXP bar as requested.
            Row {
              width: parent.width
              Column {
                Repeater {
                  model: [
                    { k: "str", label: "STR" }, { k: "dex", label: "DEX" },
                    { k: "con", label: "CON" }, { k: "int", label: "INT" },
                    { k: "wil", label: "WIL" }
                  ]
                  Text {
                    property var s: modelData
                    text: s.label + "  " + ((root.heroStats && root.heroStats[s.k]) || 0)
                    font.pixelSize: 12; font.family: Style.font.menuFamily; color: Color.menu.text
                  }
                }
              }
              Item { width: 96 }   // ~1 inch between the columns
              Column {
                spacing: 1
                Repeater {
                  model: [
                    { label: "Weapon",  inst: root.rightHand },
                    { label: "Shield",  inst: root.leftHand },
                    { label: "Armor",   inst: root.worn.armor },
                    { label: "Helmet",  inst: root.worn.helmet },
                    { label: "Amulet",  inst: root.worn.amulet }
                  ]
                  Text {
                    property var eq: modelData
                    width: 140
                    wrapMode: Text.WordWrap
                    text: eq.inst
                      ? eq.label + "  " + (root.weaponLabel(eq.inst))
                      : eq.label + "  —"
                    color: eq.inst ? Color.menu.text
                                   : Qt.darker(Color.menu.text, 1.8)
                    font.pixelSize: 11; font.family: Style.font.menuFamily
                  }
                }
              }
            }
          }
        }

        // ---- Spells popup ------------------------------------------------------
        // Left-click casts (attack spells only land in combat; heals work
        // anywhere; buffs activate). Right-click opens the info modal with
        // the spellDescription prose.
        Rectangle {
          visible: root.popupMode === "spells"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 240
          height: 220
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 10

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            text: "SPELLS  (MP " + root.heroMp + "/" + root.heroMpMax + ")"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 11
          }
          Text {
            anchors.centerIn: parent
            text: root.spells.length === 0 ? "— none discovered —" : ""
            color: Qt.darker(Color.menu.text, 1.8)
            font.family: Style.font.menuFamily
            font.pixelSize: 11
          }
          ListView {
            anchors.fill: parent
            anchors.topMargin: 30
            anchors.margins: 8
            clip: true
            model: root.spells
            delegate: Rectangle {
              property var spellDef: {
                for (var i = 0; i < root.spellTable.length; i++)
                  if (root.spellTable[i].Name === modelData.Name) return root.spellTable[i]
                return null
              }
              width: parent ? parent.width : 200
              height: 24
              color: "transparent"
              Row {
                anchors.fill: parent; anchors.margins: 2; spacing: 6
                Text {
                  text: spellDef ? (root.spellGlyph(spellDef) || "·") : "·"
                  color: Color.menu.text
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 14
                }
                Text {
                  text: modelData.Name
                  color: Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: 11
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: spellDef ? (spellDef.Cost + " MP") : ""
                  color: Qt.darker(Color.menu.text, 1.6)
                  font.family: Style.font.menuFamily
                  font.pixelSize: 9
                }
              }
              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(m) {
                  if (m.button === Qt.RightButton) root.spellInfoName = modelData.Name
                  else root.castSpell(modelData.Name)
                }
              }
            }
          }
        }

        // ---- Inventory popup (12 slots) ---------------------------------------
        Rectangle {
          visible: root.popupMode === "inventory"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 232
          height: 158
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 10

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 6
            text: "PACK"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 11
          }
          Grid {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 8
            rows: 3
            columns: 4
            spacing: 4
            Repeater {
              model: 12
              Rectangle {
                property var item: root.pack[index]
                property bool equipped: item ? root.isEquipped(index) : false
                width: 40
                height: 34
                color: Color.menu.selectedBackground
                // Equipped gear gets the gold frame (normal border otherwise).
                border.color: equipped ? root.gold : Color.menu.border
                border.width: 1
                Text {
                  anchors.centerIn: parent
                  // Icon field on equipment.json is "<glyph> name"; take the
                  // glyph char. Nerd Font pinned (PUA glyphs).
                  text: item
                    ? (root.iconOf(item) || "·") : "·"
                  color: item ? Color.menu.text : Qt.darker(Color.menu.text, 2.4)
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: 14
                }
                // "E" badge — bottom-right corner of the equipped item's frame.
                Text {
                  visible: equipped
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.rightMargin: 1
                  anchors.bottomMargin: 1
                  text: "E"
                  color: root.gold
                  font.family: Style.font.menuFamily
                  font.bold: true
                  font.pixelSize: 8
                }
                MouseArea {
                  anchors.fill: parent
                  // onClicked defaults to left-button only — include
                  // right so right-click reaches the handler.
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  // Right-click: item info modal (name + prose), toggling.
                  // Left-click: equip/unequip by class, or use consumables.
                  onClicked: function(m) {
                    if (!item) return
                    if (m.button === Qt.RightButton) root.toggleInfo(index)
                    else root.packClick(index)
                  }
                }
              }
            }
          }
        }
      }
    }

    // ---- ALLOC modal — level up: pick one stat to bump ----------------------
    // Placed at frame scope (next to the info modal) so anchors.centerIn
    // centers it in the 640x480 window; when this lived under the HUD strip
    // the parent-center landed at the window's bottom edge and the modal
    // rendered half off-screen.
    Rectangle {
      visible: root.popupMode === "alloc" && root.mode === "game"
      anchors.centerIn: parent
      width: 240
      height: 220
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      z: 20
      Column {
        anchors.fill: parent; anchors.margins: 12; spacing: 6

        Text {
          text: "LEVEL UP — " + root.lastLevelUpToast
          font.bold: true; font.pixelSize: 12
          font.family: Style.font.menuFamily; color: "#b09030"
        }
        Text { text: "Confirm a +1 to one stat:"; font.pixelSize: 10
          font.family: Style.font.menuFamily; color: Qt.darker(Color.menu.text, 1.5) }

        Repeater {
          model: [
            { k: "str", label: "STR" }, { k: "dex", label: "DEX" },
            { k: "con", label: "CON" }, { k: "int", label: "INT" },
            { k: "wil", label: "WIL" }
          ]
          Rectangle {
            property var s: modelData
            width: parent.width; height: 24
            color: Color.menu.selectedBackground
            border.color: Color.menu.border; border.width: 1
            Row {
              anchors.fill: parent; anchors.margins: 4; spacing: 8
              Text { text: s.label + "  " + ((root.heroStats && root.heroStats[s.k]) || 0)
                font.pixelSize: 11; font.family: Style.font.menuFamily; color: Color.menu.text }
              Rectangle {
                width: 22; height: 16
                color: "#d0b040"
                Text { anchors.centerIn: parent; text: "+"; color: "#1b1712"
                  font.bold: true; font.pixelSize: 11 }
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.assignStat(s.k)
                if ((root.heroStats && root.heroStats.unspent || 0) <= 0) root.popupMode = "none"
              }
            }
          }
        }
      }
    }

    // ---- BLINK modal — pick a visible tile to teleport to ----------------------
    // Frame-scope (same reasoning as the ALLOC modal: HUD-parented centering
    // drops half the modal off the window). Targets were computed at cast time
    // into root.blinkTargets; a click resolves the teleport, Cancel refunds.
    Rectangle {
      visible: root.popupMode === "blink" && root.mode === "game"
      anchors.centerIn: parent
      width: 300
      height: Math.min(320, blinkCol.contentHeight + 24)
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      z: 20
      Flickable {
        anchors.fill: parent; anchors.margins: 10
        contentHeight: blinkCol.height
        clip: true
        Column {
          id: blinkCol
          width: parent.width; spacing: 6
          Text {
            text: "BLINK — choose a destination"
            font.bold: true; font.pixelSize: 12
            font.family: Style.font.menuFamily; color: "#b09030"
          }
          Text {
            text: "Only tiles you can see are listed. Walls block sight."
            font.pixelSize: 9
            font.family: Style.font.menuFamily
            color: Qt.darker(Color.menu.text, 1.6)
          }
          Repeater {
            model: root.blinkTargets
            Rectangle {
              property var t: modelData
              width: blinkCol.width; height: 24
              color: Color.menu.selectedBackground
              border.color: Color.menu.border; border.width: 1
              Row {
                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                spacing: 8
                Text {
                  text: t.label
                  font.pixelSize: 11; font.family: Style.font.menuFamily
                  color: Color.menu.text
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: t.dist + " tile" + (t.dist === 1 ? "" : "s")
                  font.pixelSize: 9; font.family: Style.font.menuFamily
                  color: Qt.darker(Color.menu.text, 1.7)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.doBlinkTo(index)
              }
            }
          }
          Rectangle {
            width: blinkCol.width; height: 22
            color: "transparent"
            border.color: Color.menu.border; border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Cancel (MP refunded)"
              font.pixelSize: 10; font.family: Style.font.menuFamily
              color: Qt.darker(Color.menu.text, 1.4)
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.cancelBlink()
            }
          }
        }
      }
    }

    // ---- ENCHANT modal — pick a weapon/shield/armor/helmet to enchant -------
    // Triggered from useConsumable() when a Scroll of Enchantment row with an
    // Effect block is clicked. enchantCandidates was rebuilt from the pack at
    // that moment; a click bumps the target's Enchant and consumes the scroll
    // in slot enchantSourceSlot.
    Rectangle {
      visible: root.popupMode === "enchant" && root.mode === "game"
      anchors.centerIn: parent
      width: 300
      height: Math.min(320, enchCol.contentHeight + 24)
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      z: 20
      Flickable {
        anchors.fill: parent; anchors.margins: 10
        contentHeight: enchCol.height
        clip: true
        Column {
          id: enchCol
          width: parent.width; spacing: 6
          Text {
            text: "ENCHANT — choose equipment"
            font.bold: true; font.pixelSize: 12
            font.family: Style.font.menuFamily; color: "#b09030"
          }
          Text {
            text: "The scroll will be consumed. Enchantment stacks."
            font.pixelSize: 9
            font.family: Style.font.menuFamily
            color: Qt.darker(Color.menu.text, 1.6)
          }
          Repeater {
            model: root.enchantCandidates
            Rectangle {
              property var t: modelData
              width: enchCol.width; height: 24
              color: Color.menu.selectedBackground
              border.color: Color.menu.border; border.width: 1
              Row {
                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                spacing: 8
                Text {
                  text: t.name
                  font.pixelSize: 11; font.family: Style.font.menuFamily
                  color: Color.menu.text
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: t.currentEnchant > 0 ? ("+" + t.currentEnchant + " \u2192 +" + (t.currentEnchant + 1)) : "+0 \u2192 +1"
                  font.pixelSize: 9; font.family: Style.font.menuFamily
                  color: Qt.darker(Color.menu.text, 1.7)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.applyEnchant(t.index)
              }
            }
          }
          Rectangle {
            width: enchCol.width; height: 22
            color: "transparent"
            border.color: Color.menu.border; border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Cancel (scroll kept)"
              font.pixelSize: 10; font.family: Style.font.menuFamily
              color: Qt.darker(Color.menu.text, 1.4)
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.cancelEnchant()
            }
          }
        }
      }
    }

    // ---- BEACON notice — one already lit -------------------------------------
    Rectangle {
      visible: root.popupMode === "beacon" && root.mode === "game"
      anchors.centerIn: parent
      width: 260
      height: 90
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      z: 20
      Column {
        anchors.fill: parent; anchors.margins: 10; spacing: 6
        Text {
          text: "BEACON"
          font.bold: true; font.pixelSize: 12
          font.family: Style.font.menuFamily; color: "#b09030"
        }
        Text {
          text: root.beaconMessage
          font.pixelSize: 10
          font.family: Style.font.menuFamily
          color: Color.menu.text
          wrapMode: Text.WordWrap
          width: parent.width
        }
        Text {
          text: "click anywhere to close"
          color: Qt.darker(Color.menu.text, 2.0)
          font.family: Style.font.menuFamily
          font.pixelSize: 9
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: root.popupMode = "none"
      }
    }

    // ---- OMATRIX discard-choice modal ----------------------------------------
    // Reached from pickUpOmatrix() when the pack is full. Every pack item is
    // listed; clicking discards it and the Omatrix takes its slot. Canceling
    // leaves the Omatrix on the ground (you can step back later with room).
    Rectangle {
      visible: root.popupMode === "omatrix" && root.mode === "game"
      anchors.centerIn: parent
      width: 320
      height: Math.min(360, omCol.contentHeight + 24)
      color: Color.menu.background
      border.color: root.gold
      border.width: 2
      z: 20
      Flickable {
        anchors.fill: parent; anchors.margins: 10
        contentHeight: omCol.height
        clip: true
        Column {
          id: omCol
          width: parent.width; spacing: 6
          Text {
            text: "THE OMATRIX"
            font.bold: true; font.pixelSize: 13
            font.family: Style.font.menuFamily; color: root.gold
          }
          Text {
            text: "Your pack is full. Discard one item to make room for the Omatrix — the only way out of this place."
            font.pixelSize: 10
            font.family: Style.font.menuFamily
            color: Qt.darker(Color.menu.text, 1.4)
            wrapMode: Text.WordWrap
            width: parent.width
          }
          Repeater {
            model: 12
            Rectangle {
              property int slot: index
              property var item: root.pack[slot]
              visible: item !== null && item !== undefined
              width: omCol.width; height: 24
              color: Color.menu.selectedBackground
              border.color: Color.menu.border; border.width: 1
              Row {
                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                spacing: 8
                Text {
                  text: item ? item.Name : ""
                  font.pixelSize: 11; font.family: Style.font.menuFamily
                  color: Color.menu.text
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  visible: root.isEquipped(slot)
                  text: "equipped"
                  font.pixelSize: 9; font.family: Style.font.menuFamily
                  color: root.gold
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.discardForOmatrix(slot)
              }
            }
          }
          Rectangle {
            width: omCol.width; height: 22
            color: "transparent"
            border.color: Color.menu.border; border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Step back for now (Omatrix stays here)"
              font.pixelSize: 10; font.family: Style.font.menuFamily
              color: Qt.darker(Color.menu.text, 1.4)
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.cancelOmatrixDiscard()
            }
          }
        }
      }
    }

    // ---- Spell info modal (right-click a spell in the book) -------------
    // Frame scope so anchors.centerIn resolves against the 640x480 window
    // (HUD-scope parent-center put the modal half off-screen, same bug the
    // ALLOC modal had).
    Rectangle {
      visible: root.spellInfoName !== ""
      anchors.centerIn: parent
      width: 280
      height: 170
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      z: 16
      Column {
        anchors.fill: parent; anchors.margins: 10; spacing: 8
        Text {
          text: root.spellInfoName
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.bold: true; font.pixelSize: 13
        }
        Text {
          property var sd: {
            for (var i = 0; i < root.spellTable.length; i++)
              if (root.spellTable[i].Name === root.spellInfoName) return root.spellTable[i]
            return null
          }
          text: sd ? ("Cost " + sd.Cost + " MP"
            + (sd.Damage && sd.Damage !== "0" ? "   dmg " + sd.Damage : "")
            + (sd.Duration && sd.Duration !== "0" ? "   dur " + sd.Duration : "")) : ""
          color: Qt.darker(Color.menu.text, 1.4)
          font.family: Style.font.menuFamily
          font.pixelSize: 10
        }
        Rectangle { width: parent.width; height: 1; color: Color.menu.border }
        Text {
          property var sd2: {
            for (var i = 0; i < root.spellTable.length; i++)
              if (root.spellTable[i].Name === root.spellInfoName) return root.spellTable[i]
            return null
          }
          width: parent.width
          wrapMode: Text.WordWrap
          text: sd2 ? sd2.Description : ""
          color: Qt.darker(Color.menu.text, 1.3)
          font.family: Style.font.menuFamily
          font.pixelSize: 11
        }
        Item { height: 1; width: 1 }
        Text {
          text: "click anywhere to close"
          color: Qt.darker(Color.menu.text, 2.0)
          font.family: Style.font.menuFamily
          font.pixelSize: 9
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: root.spellInfoName = ""
      }
    }

    // ---- Item info modal (right-click a pack item) -----------------------------
    // Name + the prose description from equipment.json. Right-clicking the
    // same item again (or Escape) closes it; right-clicking another item
    // swaps the contents.
    Rectangle {
      visible: root.infoSlot >= 0
        && root.pack[root.infoSlot] !== null
        && root.mode === "game"
      anchors.centerIn: parent
      width: 280
      height: 170
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 2
      z: 15

      Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Header: glyph + display name (e.g. "+2 Katana").
        Row {
          spacing: 8
          Text {
            text: root.infoSlot >= 0
              ? (root.iconOf(root.pack[root.infoSlot]) || "·") : ""
            color: Color.menu.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.infoSlot >= 0
              ? (root.weaponLabel(root.pack[root.infoSlot])) : ""
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: 13
          }
        }
        Rectangle { width: parent.width; height: 1; color: Color.menu.border }

        // Description — capped so the footer row (hint + trash) stays clear
        // of the prose on long descriptions.
        Item {
          width: parent.width
          height: 70
          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: childrenRect.height
            clip: true
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.infoText()
              color: Qt.darker(Color.menu.text, 1.3)
              font.family: Style.font.menuFamily
              font.pixelSize: 11
            }
          }
        }
        Item { height: 1; width: 1 }   // spacer so the row hugs the bottom
        Row {
          width: parent.width
          // Hint centered horizontally; the flexible spacer pushes the
          // trash to the far right (= modal's bottom-right corner).
          Item { width: 20 }             // balances the ~20px trash glyph
          Text {
            text: "right-click to close"
            color: Qt.darker(Color.menu.text, 2.0)
            font.family: Style.font.menuFamily
            font.pixelSize: 9
          }
          // Flexible spacer: with the Row's width fixed, this Item picks up
          // the leftover width so the trash Text lands flush right.
          Item { width: parent.width - 20 - 96 - 1 }   // hint ~96px
          // fa-trash_arrow_up (U+EF90, verified present in the Nerd Font)
          // bottom-right corner of the modal. Discards the item, clearing
          // its slot if equipped.
          Text {
            text: ""
            color: Qt.darker(Color.menu.text, 1.3)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.discardItem(root.infoSlot)
            }
          }
        }
      }
    }
  }
}
