# AgriWorld 3D — Project Log

## Decisions
- Engine: Godot 4.3, GL Compatibility renderer, GDScript.
- Phone-only workflow: GitHub repo + GitHub Actions builds the APK (arm64 + armeabi-v7a).
- Test device: TECNO BF6 (Pop 7), PowerVR Rogue GE8322. Needs 32-bit ARM build.
- Simulation data (tile dictionaries) kept separate from 3D nodes.
- Look (CHANGED, see docs/VISUAL_PLAN.md): moving from flat-colour primitives to textured low-poly
  (texture atlases, UV-mapped crop stages, sky, optional shadows). Offline gameplay stays the priority.
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
  Files: scenes/main.tscn, scripts/farm_main.gd, farm_grid.gd, camera_rig.gd, hud.gd.
  Verified on device: drag/pinch do not select, outside tap clears selection, zoom works.
- Milestone 2 Step A (plough, plant maize/beans, grow, harvest, money, stock, sell): verified
  on device from screenshots (money 468 after planting both crops, 570 after selling 4 maize +
  3 beans, matching the logic tests; buttons respond).
- Milestone 2 Step B (save/load, offline growth, Reset button): files written, results from
  device not yet reported to me.
  Files: scripts/save_manager.gd, game_state.gd (to_dict/from_dict), farm_main.gd, hud.gd,
  tests in scripts/tests/test_game_state.gd. Check CI 'Run logic tests' shows 0 failures.

- Milestone 3 Step A (tractor): verified on device from screenshots: drive mode, steering/gas
  strips, tool cycling with visible implements, seeding, harvesting, fuel and run time, ~58-61 FPS.
  (Original note: )
  Manual driving (arcade physics, not VehicleBody3D), follow camera, tools (plough, seeder,
  harvester) that work the tile BEHIND the tractor, fuel + refuel, running hours, save v2.
  Files: scripts/vehicle_data.gd, vehicle_model.gd, tractor_view.gd, drive_controls.gd,
  plus changes to game_state.gd, camera_rig.gd, hud.gd, farm_main.gd.
- Milestone 3 Step B (autopilot): VERIFIED on device from screenshots. Full-field runs worked
  (stock 256 maize + 192 beans = 64 tiles each), low-money warning shown, seeding stops at 0
  money. Milestone 3 is complete. Logic tests still need confirming (file path fix).
  (Original note: ) The Auto button
  (drive view) works the whole field with the chosen tool: plans lanes along rows, drives them,
  pivots between lanes. Stops on: finished, out of fuel, blocked, not enough money, tool
  changed, or any touch on the steering/gas strips.
  Reported on device: did not finish whole jobs and re-drove finished rows. Likely causes:
  fuel/money ran out, crops not yet ripe, and always starting from row 0. Fixed: lanes now cover
  only the columns that need work, start from the end nearest the tractor, up to 3 passes
  (re-detects work), fuel/money warning at start, summary message with the reason it stopped. The headless tests simulate full
  ploughing, seeding and harvesting jobs. Files: scripts/autopilot.gd, farm_layout.gd.

- Polish pass (written, NOT yet tested on device): FPS readout (current, 5 s average, 5 s low),
  Menu with graphics quality Low/Medium/High (Medium/High enable sun shadows; Low is default),
  debug readout on/off, Reset moved into Menu, outlined HUD text, drive strips dimmed during
  Auto, merged low-poly crop models (one draw call per tile, 3 growth stages), money safety net
  (100 grant when broke with no stock and nothing growing), drive autosave every 8 s (was 2 s,
  possible cause of FPS hitches), drive camera raised. Files: settings.gd, crop_models.gd,
  farm_grid.gd, hud.gd, farm_main.gd, game_state.gd.

- Visual overhaul (written, NOT yet tested on device): continuous ploughed/raw/stubble ground
  (no gaps), furrows, grass tufts, realistic stylised maize and bean plants (3 growth stages,
  crop detail 0/1), terrain with colour variation and distant hills, fence, trees, detailed
  farmhouse, blob shadows when shadows are off, procedural sky on Medium/High, detailed tractor
  with spinning lugged wheels, free orbit camera while driving (Camera: behind button), harvest
  leaves stubble that must be ploughed again (HARVEST_LEAVES_STUBBLE in game_state.gd).
  New files: mesh_builder.gd, tile_models.gd, farm_scenery.gd. Rewritten: crop_models.gd,
  farm_grid.gd, tractor_view.gd, farm_main.gd. Real photoreal crops would need textured .glb
  assets (e.g. free CC0 packs) uploaded to the repo.

- Visual direction reset (planning, no code yet): goal is realistic, textured, multi-stage crops
  and a deeper environment, close to the look of commercial mobile farming games, within mobile
  budgets. Plan, budgets and phases V1-V4 are in docs/VISUAL_PLAN.md. The last build (visual
  overhaul) is still vertex-colour only and has not been reported on yet.

## Known issues
- FPS: mostly 54-61 on the TECNO BF6, but dips seen at 44 (harvesting) and 36 (manage view,
  empty field), so not caused by crops alone. Cause unknown (heat, GC, screenshot?). Add an
  average/minimum FPS readout before adding more content.
- Economy: money can reach 0 (all spent on seed). Needs a safety net so the player cannot
  get stuck with no money, no stock and no crops. Prices also need balancing (income per
  cycle is very high).
- CI 'Run logic tests' failed with File not found: scripts/tests/test_game_state.gd was missing
  from the repo (wrong folder or name). The tests have not run yet. Create it at exactly
  scripts/tests/test_game_state.gd.
- Autopilot pivots on the spot between lanes (real U-turns do not fit between 1.5-unit rows).
- Autopilot start is blocked if the tractor is directly behind the farmhouse; it gives up.
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

## Milestone 3 Step B test checklist
1. In drive view, pick Tool: Plough on a fresh field and tap Auto: Start. Tractor drives to the
   field, ploughs row by row (tiles turn dark), pivots at each end, and stops with a finished message.
2. Pick Seeder and tap Auto again: ploughed tiles get planted (costs money). Money low = stops.
3. When crops are ripe, pick Harvester and Auto: tractor harvests them.
4. Touching the steering or gas strip during Auto cancels it and gives you control.
5. Auto: Stop button stops it. Switching tool or Manage view also stops it.
6. With Tool: None, or nothing left to do, Auto shows a message and does not start.
7. Low fuel: it stops with Out of fuel; refuel and start again.

## Polish pass test checklist
1. Top-left shows FPS (current, avg, low) and Mem; a Menu button sits under it.
2. Menu opens a Settings panel: Low/Medium/High (selected one in brackets), Debug info on/off,
   Reset farm, Close. Choosing a quality shows a message; the choice is kept after restart.
3. Low: no shadows. Medium: tractor, house, crops cast shadows. Compare FPS low on each.
4. Crops now look like plants (maize stalks with cobs when ripe, bean bushes with pods).
5. Text is readable over crops (black outline). Strips dim while Auto runs but still cancel it.
6. Spend all money with nothing to sell: after a moment you get a Farm grant of 100.
7. Drive for a few minutes: note the FPS low value and whether hitches are gone.

## Visual overhaul test checklist
1. App starts without hanging (compare FPS readout on Low, Medium, High).
2. Field is one continuous brown surface; ploughed land has furrows; no green lines between tiles.
3. Maize looks like maize (stalk, drooping leaves, cobs, tassel); beans look like bean bushes
   (flowers then pods). Seedlings are small.
4. After harvest the tile shows stubble; selecting it offers Plough; the seeder skips it.
5. In drive view, drag on empty screen to orbit around the tractor, pinch to zoom close up,
   tap Camera: behind to swing the view back. View the tractor from all sides.
6. Trees, fence, farmhouse details, hills in the distance. Medium/High: sky and shadows.
7. Note the FPS low number on each quality level and tell me if Low is still smooth.

## Realistic crops + bigger farm + pushing machines (this update)
- Crops are now textured leaf cards (assets/textures/crops.png, made by tools/gen_crop_atlas.py)
  on stalks, planted in straight rows on the soil ridges (no random tile rotation).
- 5 growth stages: sprout, young, growing, maturing, ripe. Ripe = fresh and harvestable
  (green leaves, plump husked cobs, full pods), not dry.
- Farm is bigger: LAND_HALF 20, DRIVE_BOUNDS 19, a much larger yard for parking.
- Machines push each other (vehicle_model.gd): a moving machine shoves a parked one aside; when
  two moving machines meet the more powerful pushes the weaker aside. Nobody stops working.

## Test checklist for this update
1. Look at maize and beans at every stage; check rows line up with the ridges across tiles.
2. Ripe maize/beans still look fresh. Harvest still only works when ripe.
3. FPS low on Low/Medium/High compared with before (crops are denser now).
4. Park machines in the yard; buy several. Drive one into a parked one: it gets pushed.
5. Run two autopilots near each other: neither should stop with "Autopilot blocked".
