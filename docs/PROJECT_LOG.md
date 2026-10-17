# AgriWorld 3D — Project Log

## Decisions
- Engine: Godot 4.3, GL Compatibility renderer, GDScript.
- Phone-only workflow: GitHub repo + GitHub Actions builds the APK (arm64 + armeabi-v7a).
- Test device: TECNO BF6 (Pop 7), PowerVR Rogue GE8322. Needs 32-bit ARM build.
- Simulation data (tile dictionaries) kept separate from 3D nodes.
- Look: flat-colour low-poly, one directional light + ambient colour, no shadows.
- Scripts are loaded with preload(), not class_name, to avoid class-cache issues in CI.
- Stage 1: landscape, 8x8 field.

## Status
- Stage 0 (toolchain proof): DONE and tested on device. ~60 FPS, ~21 MB, orbit + pinch zoom work.
- Stage 1 (farm grid, tap-to-select): files written, NOT yet built or tested.
  Files: scenes/main.tscn, scripts/farm_main.gd, farm_grid.gd, camera_rig.gd, hud.gd.

## Known issues
- Original scripts/main.gd hung on the splash screen; cause never confirmed (suspected
  repo typo or path). It is no longer used and can be deleted.
- scripts/diag.gd and scenes/diag_*.tscn are diagnostics; keep until Stage 1 is verified.
- Tap me button counter never confirmed on device (Stage 0).

## Stage 1 test checklist
1. App launches (no splash hang), sky-blue background, farm visible.
2. One-finger drag rotates; camera never flips; pitch is limited.
3. Pinch zooms between close and far limits.
4. Tapping a field tile turns it yellow and the panel shows its number.
5. Tapping another tile moves the highlight; tapping ground outside the field clears it.
6. Dragging or pinching does NOT select a tile.
7. FPS stays near 60 and memory stays low.
