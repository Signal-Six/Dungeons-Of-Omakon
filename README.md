# Dungeons of Omakon

A first-person, 16-bit dungeon crawler that lives in the Omarchy bar. Click
the sword pill to open the game window, delve a randomly generated 6x7
floor, fight monsters, loot, and descend. Permadeath; a rolling archive of
your last 10 characters records their deepest floor and score.

## Status: Phase 1 — skeleton

- Bar widget (`BarWidget.qml`): HP/MP ticker pill + IPC handlers
- Game window (`Panel.qml`): exclusive-focus overlay, themed frame,
  viewport placeholder, HP/MP header strip
- No dungeon, combat, items, or persistence yet

## Install (dev)

```sh
ln -snf /home/haze/Projects/Dungeons-Of-Omakon ~/.config/omarchy/plugins/b.omakon
omarchy-shell shell rescanPlugins
omarchy plugin enable b.omakon
omarchy validate b.omakon
```

Then click the Omakon pill in the bar (or `omarchy-shell shell toggle
b.omakon`).

Unlink before packaging for real distribution (`omarchy plugin add <git
url>` clones into the plugins dir).

## Roadmap

- Phase 2: framed GUI — directional arrows, action buttons (attack/spell/
  inventory), automap toggle, procedural pixel-art surfaces
- Phase 3: `Dungeon.js` — seeded 6x7 maze gen (recursive backtracker), node
  types, movement, viewport depth 2
- Phase 4: persistence — `~/.local/share/omarchy/omakon/save.json` (or
  stateful equivalent), last-10 archive, score = f(item rank, depth, level)
- Phase 5: content JSON (`content/monsters.json`, `items.json`,
  `spells.json`) + combat loop
- Phase 6: audio, sprites, settings polish
