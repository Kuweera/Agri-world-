# AgriWorld 3D — Project Log

## Decisions
- Engine: Godot 4.3, GL Compatibility renderer, GDScript.
- Phone-only workflow: GitHub repo + GitHub Actions builds the APK (arm64 + armeabi-v7a).
- Test device: TECNO BF6 (Pop 7), PowerVR Rogue GE8322. Needs 32-bit ARM build.
- Simulation data (tile dictionaries) kept separate from 3D nodes.
- Look: flat-colour low-poly, one directional light + ambient colour, no shadows.
- Scripts are loaded with preload(), not class_name, to avoid class-cache issues in CI.
- Stage 1: landscape, 8x8 field.
- Growth uses unix timestamps (planted_at) so offline progress can be computed on load.
- Game logic (scripts/game_state.gd) has no nodes; time is passed in, so it can be tested headless.
- Crop numbers live in scripts/crop_data.gd (growth times are short for testing).
- Touch: emulate_mouse_from_touch=true so Buttons receive touches (was false in Stage 0/1).

## Status
- Stage 0 (toolchain proof): DONE and tested on device. ~60 FPS, ~21 MB, orbit + pinch zoom work.
- Stage 1 (farm grid, tap-to-select): built and run on device. Confirmed from screenshots:
  launches, farm renders, tile tap highlights tile and updates panel, ~60 FPS, ~20 MB.
  NOT yet confirmed: drag/pinch never selects a tile, tapping outside the field clears
  the selection, pinch zoom limits.
  Files: scenes/main.tscn, scripts/farm_main.gd, farm_grid.gd, camera_rig.gd, hud.gd.
  Verified on device: drag/pinch do not select, outside tap clears selection, zoom works.
- Milestone 2 Step A (plough, plant maize/beans, grow, harvest, money, stock, sell): files
  written, NOT yet built or tested on device. CI runs a syntax check and logic tests
  (scripts/tests/test_game_state.gd); check those log steps show PASS lines.
- Milestone 2 Step B (save/load): not started.

## Known issues
- Original scripts/main.gd hung on the splash screen; cause never confirmed (suspected
  repo typo or path). It is no longer used and can be deleted.
- scripts/diag.gd and scenes/diag_*.tscn are diagnostics; keep until Stage 1 is verified.
- Tap me button never counted in Stage 0 screenshots. Suspected cause: emulate_mouse_from_touch
  was false, so Buttons got no touches. Changed to true in Step A; confirm HUD buttons work.

## Stage 1 test checklist
1. App launches (no splash hang), sky-blue background, farm visible.
2. One-finger drag rotates; camera never flips; pitch is limited.
3. Pinch zooms between close and far limits.
4. Tapping a field tile turns it yellow and the panel shows its number.
5. Tapping another tile moves the highlight; tapping ground outside the field clears it.
6. Dragging or pinching does NOT select a tile.
7. FPS stays near 60 and memory stays low.

## Milestone 2 Step A test checklist
1. HUD shows Money: 500 and Stock: empty (top-right) and a Sell all button.
2. Tap a tile: the Plough button appears. Tap Plough: tile turns dark brown.
3. Tap the ploughed tile: Plant Maize (20) and Plant Beans (12) appear.
4. Plant maize: money drops by 20, a green crop appears and grows over ~40 s.
5. When ripe the crop turns yellow, panel says ripe, Harvest button appears.
6. Harvest: Stock shows Maize 4, tile returns to ploughed.
7. Sell all: money rises by 60, stock empty.
8. Errors: with money too low, planting shows "Not enough money".
9. Buttons do not rotate the camera or select a tile behind them.
