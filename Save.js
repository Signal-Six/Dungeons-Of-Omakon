// Save.js — keyring persistence for Dungeons of Omakon, following the
// b.omanote secret-tool contract:
//   secret-tool store  omarchy-plugin b.omakon field <run|archive|active>
//   secret-tool lookup omarchy-plugin b.omakon field <...>
//   secret-tool clear  omarchy-plugin b.omakon field <...>
//
// Three fields:
//   active  — name of the living character (missing = no run in progress)
//   run     — full live state JSON for the active run
//   archive — JSON array, most recent first, max 10, of finished runs
//             {name, started, floor, level, score}
//
// A run's score = maxFloor*100 + level*10 + bestItemRank*25 (item rank lands
// in Phase 5; 0 until then). Werint through process stdin via a temp file in
// XDG_RUNTIME_DIR (secret-tool reads to EOF from stdin).

function loadCmd(field) {
  return "command -v secret-tool >/dev/null 2>&1 || { echo 'secret-tool not found' >&2; exit 127; }\n"
    + "secret-tool lookup omarchy-plugin b.omakon field " + field;
}

function storeScript(field) {
  return "path=$1\n"
    + "if ! command -v secret-tool >/dev/null 2>&1; then\n"
    + "  echo 'secret-tool not found' >&2\n"
    + "  rm -f -- \"$path\"\n"
    + "  exit 127\n"
    + "fi\n"
    + "secret-tool store --label='Dungeons of Omakon " + field + "' omarchy-plugin b.omakon field " + field + " < \"$path\"\n"
    + "status=$?\n"
    + "rm -f -- \"$path\"\n"
    + "exit \"$status\"";
}

function clearScript(field) {
  return "command -v secret-tool >/dev/null 2>&1 || { echo 'secret-tool not found' >&2; exit 127; }\n"
    + "secret-tool clear omarchy-plugin b.omakon field " + field;
}

// Serialize the live run state. All numbers/strings only — no functions.
function serializeRun(s) {
  return JSON.stringify({
    version: 4,
    name: s.name,
    started: s.started,
    hp: s.hp, hpMax: s.hpMax,
    mp: s.mp, mpMax: s.mpMax,
    level: s.level, xp: s.xp,
    str: s.str, dex: s.dex,
    leftHand: s.leftHand, rightHand: s.rightHand,
    pack: s.pack, spells: s.spells, effects: s.effects,
    floorNum: s.floorNum,
    seed: s.seed,
    pos: s.pos,
    explored: s.explored
  });
}

function parseRun(text) {
  if (!text || text === "") return null;
  try {
    var o = JSON.parse(text);
    if (!o || typeof o !== "object") return null;
    if (o.version !== 4) return null;
    return o;
  } catch (e) { return null; }
}

function parseArchive(text) {
  if (!text || text === "") return [];
  try {
    var o = JSON.parse(text);
    if (Array.isArray(o)) return o.slice(0, 10);
    return [];
  } catch (e) { return []; }
}

function computeScore(state) {
  var bestItemRank = 0; // Phase 5 scans the pack/equipment for rank values
  return state.floorNum * 100 + state.level * 10 + bestItemRank * 25;
}

// Archive entry appended (newest first), trimmed to 10.
function appendArchive(archive, entry) {
  var out = [entry].concat(archive);
  return out.slice(0, 10);
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    loadCmd: loadCmd, storeScript: storeScript, clearScript: clearScript,
    serializeRun: serializeRun, parseRun: parseRun,
    parseArchive: parseArchive, appendArchive: appendArchive,
    computeScore: computeScore
  };
}
