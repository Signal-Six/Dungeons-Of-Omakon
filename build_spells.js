#!/usr/bin/env node
// build_spells.js — spells.csv → spells.json. Run after editing the csv.
// Columns kept verbatim from the user's table; the Icon stays "U+hex" like
// monsters.json's dual notation — Panel normalizes via existing helpers.
const fs = require("fs");

function parseCsv(text) {
  // Simple RFC4180 parser: quoted fields may contain commas.
  const rows = [];
  let row = [], cur = "", inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) {
      if (c === '"') {
        if (text[i + 1] === '"') { cur += '"'; i++; }
        else inQ = false;
      } else cur += c;
    } else if (c === '"') inQ = true;
    else if (c === ",") { row.push(cur); cur = ""; }
    else if (c === "\n" || c === "\r") {
      if (cur !== "" || row.length > 0) { row.push(cur); rows.push(row); row = []; cur = ""; }
      if (c === "\r" && text[i + 1] === "\n") i++;
    } else cur += c;
  }
  if (cur !== "" || row.length > 0) { row.push(cur); rows.push(row); }
  return rows;
}

const src = fs.readFileSync("spells.csv", "utf8");
const rows = parseCsv(src).filter(r => r.length && r[0] !== "spellName");
const out = rows.map(r => ({
  Name: r[0],
  Damage:   r[1] === "" ? null : r[1],   // dice string with INT refs, or "0"
  Duration: r[2] === "" ? null : r[2],
  Cost: parseInt(r[3], 10),
  Effect: r[4] || "",
  Description: r[5] || "",
  Rank: parseInt(r[6], 10),
  Icon: r[7]                              // "U+hex" — Spells.toGlyph converts
}));
fs.writeFileSync("spells.json", JSON.stringify(out, null, 2) + "\n");
console.log("wrote spells.json with " + out.length + " spells");
