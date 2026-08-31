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

  // ---- Equipment / inventory shells ---------------------------------------
  property var leftHand: null          // shield-type item card, or null
  property var rightHand: ({ Name: "Rusty Sword" })   // instance {Name, Enchant?}
  property var pack: (new Array(12)).fill(null)
  property var spells: []              // discovered spells

  // ---- Combat state (2026-08-31 design: player-first, retaliate-only,
  // ---- no flee; poison is log-only until the movement-tick system lands) ---
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
  // Null-safe glyph accessor for the UI: "" when the table isn't loaded yet
  // or the entry is missing, so Text nodes can fall back to their own glyph.
  function iconOf(inst) {
    var r = resolveInstance(inst)
    return (r && r.icon) ? r.icon : ""
  }

  property string popupMode: "none"    // "none" | "spells" | "inventory" | "stats" | "alloc"
  function togglePopup(mode) {
    popupMode = (popupMode === mode) ? "none" : mode
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
      lastLevelUpToast = "LEVEL UP → " + out.level + " (+" + out.levelsGained + ")"
      popupMode = "alloc"
    }
  }
  function assignStat(stat) {
    heroStats = Stats.assignPoint(heroStats, stat)
    heroHpMax = Stats.hpMax(heroStats, heroLevel)
    heroMpMax = Stats.mpMax(heroStats, heroLevel)
  }
  // Combat hooks read the primary stats via combatState().

  // Build the state object Combat.attack() expects — this is the seam that
  // Phase 5's HUD buttons and Phase 6's status effects will feed through.
  // First pack instance whose equipment.json Type matches slot ("Armor",
  // "Helmet", "Amulet") — worn gear. The pack is the single source of
  // truth for worn items (drops land there; no separate equip screen yet).
  function wornForSlot(slotType) {
    for (var i = 0; i < pack.length; i++) {
      var e = null
      var inst = pack[i]
      if (!inst) continue
      for (var j = 0; j < equipmentTable.length; j++)
        if (equipmentTable[j].Name === inst.Name) { e = equipmentTable[j]; break }
      if (e && e.Type === slotType) return inst
    }
    return null
  }
  function combatState() {
    var rh = resolveInstance(rightHand)
    var lh = resolveInstance(leftHand)
    var worn = [
      resolveInstance(wornForSlot("Armor")),
      resolveInstance(wornForSlot("Helmet")),
      resolveInstance(wornForSlot("Amulet"))
    ].filter(function (x) { return x !== null })
    return {
      str: heroStats.str || 0, dex: heroStats.dex || 0, int: heroStats.int || 0,
      wil: heroStats.wil || 0,
      rightHand: rh, leftHand: lh,
      worn: worn, effects: heroEffects
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
  FileView { id: monsterFile; path: root.dataDir + "/monsters.json"; onLoaded: root.loadMonsters(text()) }
  FileView { id: equipFile;   path: root.dataDir + "/equipment.json"; onLoaded: root.loadEquipment(text()) }

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

  function currentState() {
    return {
      name: runName, started: runStarted,
      hp: heroHp, hpMax: heroHpMax, mp: heroMp, mpMax: heroMpMax,
      level: heroLevel, xp: heroXp,
      stats: heroStats,
      leftHand: leftHand, rightHand: rightHand,
      pack: pack, spells: spells, effects: heroEffects,
      floorNum: floorNum, seed: floorSeed,
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
  function applyRun(run) {
    runName = run.name || "Hero"
    runStarted = run.started || ""
    heroHp = run.hp; heroHpMax = run.hpMax
    heroMp = run.mp; heroMpMax = run.mpMax
    heroLevel = run.level || 1; heroXp = run.xp || 0
    heroStats = run.stats || Stats.freshStats()
    heroEffects = run.effects || []
    leftHand = handFromSave(run.leftHand)
    rightHand = handFromSave(run.rightHand) || ({ Name: "Rusty Sword" })
    pack = run.pack || (new Array(12)).fill(null)
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
    leftHand = null
    rightHand = ({ Name: "Rusty Sword" })
    pack = (new Array(12)).fill(null)
    combat = null
    combatVictory = false
    spells = []
    floorNum = 1
    floorSeed = (Math.random() * 0x7fffffff) | 0
    floor = Dungeon.generate(floorSeed)
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
    // Permadeath: archive the run, clear the active run, bump to menu.
    saveArchiveEntry({
      name: runName, started: runStarted,
      floor: floorNum, level: heroLevel,
      score: Save.computeScore(currentState())
    })
    clearRun()      // queue serializes: archive store, then run clear
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
    var np = Dungeon.move(floor, pos, dir)
    if (np.row !== pos.row || np.col !== pos.col) {
      pos = np
      markExplored(np.row, np.col)
      trySpawnEncounter()
    }
    debugVista()
  }
  function turn(rel) {
    if (combat) return
    pos = Dungeon.turn(pos, rel); debugVista()
  }

  // ---- Encounter lifecycle --------------------------------------------------
  // Called after every successful tile change. Monsters.rollSpawn returns a
  // monsters.json row or null per the agreed spawn formula.
  function trySpawnEncounter() {
    if (monsterTable.length === 0) return   // table not loaded yet (boot race)
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
  // next click closes the encounter.
  function combatAct() {
    if (!combat) return
    if (combat.over) {          // victory-hold click → return to exploration
      combat = null
      combatVictory = false
      saveRun()
      return
    }
    // Inline CombatLoop.round logic — QML can't call imported JS module functions
    var state = combatState()
    var wlabel = weaponLabel(rightHand)
    // player strike
    var res = Combat.attack(state, combat.monster)
    if (!res.hit) {
      combat.log.push("You strike at the " + combat.monster.name + " with " + wlabel + " — miss. (ACC " + res.accuracy + "+2d6=" + res.accRoll + " vs DV " + res.dv + ")")
    } else {
      var dmg = res.damage
      combat.log.push("You strike the " + combat.monster.name + " with " + wlabel + " for " + dmg + " damage (" + res.baseDamage + "+" + res.d4 + ")!")
      combat.monster.hp -= dmg
      if (combat.monster.hp <= 0) {
        combat.log.push("The " + combat.monster.name + " dies!")
        combat.over = true
        combat.won = true
      }
    }
    // monster retaliation (if not dead)
    if (!combat.over) {
      var accRoll = Dice.roll(combat.monster.accExpr)
      var mres = Combat.defend(state, { acc: accRoll, dmg: 0, isMagic: combat.monster.isMagic })
      if (mres.hit) {
        var mdmg = Dice.roll(combat.monster.damageExpr)
        combat.log.push("The " + combat.monster.name + " attacks you for " + mdmg + " damage!")
        heroHp = Math.max(0, heroHp - mdmg)
        if (heroHp <= 0) {
          die()
          return
        }
      } else {
        combat.log.push("The " + combat.monster.name + " attacks — misses.")
      }
    }
    // kill rewards — the overlay holds (combatVictory) so the player can
    // read the outcome; the next click closes the encounter.
    if (combat.over && combat.won) {
      grantXp(combat.monster.xp, combat.monster.name)
      var drop = Drops.rollDrop(equipmentTable, floorNum, Math.random)
      if (drop) {
        var packed = giveLoot(drop)
        combat.log.push("It drops a " + drop.Name + (drop.Enchant ? " (+" + drop.Enchant + ")" : "") + "!"
          + (packed ? "" : " — but your pack is full; it is left behind."))
      } else {
        combat.log.push("It drops nothing.")
      }
      combatVictory = true
    }
    bumpCombatLog()
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
        }

        // ---- Stats popup (STATS button) — read-only view ------------------------
        Rectangle {
          visible: root.popupMode === "stats"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 260
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
        }

        // ---- ALLOC modal — level up: pick one stat to bump ----------------------
        Rectangle {
          visible: root.popupMode === "alloc"
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

        // ---- Spells popup ------------------------------------------------------
        Rectangle {
          visible: root.popupMode === "spells"
          anchors.bottom: parent.top
          anchors.right: parent.right
          anchors.bottomMargin: 4
          width: 220
          height: 140
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 2
          z: 10

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            text: "SPELLS"
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
            model: root.spells
            delegate: Text {
              text: modelData.icon + " " + modelData.name
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: 11
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
                width: 40
                height: 34
                color: Color.menu.selectedBackground
                border.color: Color.menu.border
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
              }
            }
          }
        }
      }
    }
  }
}
