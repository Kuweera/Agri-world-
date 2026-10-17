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
- Vehicles: pure model (vehicle_model.gd) + config (vehicle_data.gd); tractor state lives in
  GameState.tractor. Driving controls are two touch strips handled in _input() by touch index,
  because Buttons only see one touch at a time.
- Save: versioned JSON at user://save.json (schema_version 2; v1 saves are migrated, adding a default tractor), temp file + .bak backup,
  validated before applying, autosave after each action and when the app pauses/closes.
- Offline growth comes from stored unix timestamps. Changing the phone clock affects the
  OFFLINE game only; online play will use server time.

## Status
- Stage 0 (toolchain proof): DONE and tested on device. ~60 FPS, ~21 MB, orbit + pinch zoom work.
- Stage 1 (farm grid, tap-to-select): built and run on device. Confirmed from screenshots:
  launches, farm renders, tile tap highlights tile and updates panel, ~60 FPS, ~20 MB.
  NOT yet confirmed: drag/pinch never selects a tile, tapping outside the field clears
  the selection, pinch zoom limits.
  Files: scenes/main.tscn, scripts/farm_main.gd, farm_grid.gd, camera_rig.gd, hud.gd.
  Verified on device: drag/pinch do not select, outside tap clears selection, zoom works.
- Milestone 2 Step A (plough, plant maize/beans, grow, harvest, money, stock, sell): verified
  on device from screenshots (money 468 after planting both crops, 570 after selling 4 maize +
  3 beans, matching the logic tests; buttons respond).
- Milestone 2 Step B (save/load, offline growth, Reset button): files written, results from
  device not yet reported to me.
  Files: scripts/save_manager.gd, game_state.gd (to_dict/from_dict), farm_main.gd, hud.gd,
  tests in scripts/tests/test_game_state.gd. Check CI 'Run logic tests' shows 0 failures.

- Milestone 3 Step A (tractor): files written, NOT yet built or tested on device.
  Manual driving (arcade physics, not VehicleBody3D), follow camera, tools (plough, seeder,
  harvester) that work the tile BEHIND the tractor, fuel + refuel, running hours, save v2.
  Files: scripts/vehicle_data.gd, vehicle_model.gd, tractor_view.gd, drive_controls.gd,
  plus changes to game_state.gd, camera_rig.gd, hud.gd, farm_main.gd.
- Milestone 3 Step B (automated task): not started.

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

## Milestone 2 Step B test checklist
1. Plant a crop, swipe the app away, reopen: farm, money and the growing crop are still there.
2. Plant a crop, close the app, wait over 40 s, reopen: message says crops are ripe.
3. Harvest and sell, close and reopen: money and empty stock are kept.
4. Tap Reset (top-left) once: message asks to tap again. Tap again within 3 s: farm resets.
   Close and reopen: the reset farm is kept. Waiting more than 3 s makes it disarm.
5. Money, stock and tile states never look corrupted after repeated close/reopen.

## Milestone 3 Step A test checklist
1. Manage view shows a Drive tractor button (bottom-right) and a tractor near the field.
2. Tap Drive tractor: camera follows behind the tractor; steering strip (bottom-left),
   gas strip (bottom-right), tool buttons (left) and a Fuel/Speed/Run readout appear.
3. Hold the gas strip above its centre line: tractor drives forward. Below: reverses slower.
4. Hold both strips at once (one finger each): the tractor steers while driving.
5. Tractor cannot leave the fence or drive through the farmhouse.
6. Tool: Plough, drive over unploughed tiles: they turn dark. Tool: Seeder over ploughed
   tiles: plants the chosen seed (costs money). Tool: Harvester over ripe crops: stock rises.
7. Fuel drops while moving. At 0 the tractor stops and says Out of fuel. Refuel costs money.
8. Manage view returns to the farm view. Close and reopen: tractor position, fuel and tool kept.
9. Old save from before this update still loads (money, crops kept, default tractor added).
