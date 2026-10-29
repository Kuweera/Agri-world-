# Vehicle physics: baseline, diagnosis, first fix (master plan phases 1-2)

Measured headless with `scripts/tests/physics_report.gd` (Godot 4.3, flat ground, 60 Hz). Only device testing can confirm how it feels.

## How vehicles work today
* Not a rigid-body or `VehicleBody3D` simulation. `vehicle_model.gd` is a 2D arcade model (x, z, heading, speed) on a perfectly flat
  ground plane; `tractor_view.gd` only draws the result.
* `suspension.gd` is looks-only springs. Before the fix it **pitched/rolled the whole model about its ground-level origin** with
  up to 0.07 rad pitch, 0.06 rad roll and a fake `sin()` bounce of 7 cm that ran whenever the machine moved, although the
  ground is flat.

## Root causes of "jumping" and "sinking"
1. Whole-model tilt about the ground origin: one end of the tyres goes **below** the ground, the other **above**.
2. A fake periodic bounce on flat ground (`bump`), plus acceleration read as a finite difference of speed, which spikes.
3. Models stand off the ground differently: small tractor tyres 1.6-3.0 cm below y=0, small combine 2.6-5.1 cm below,
   `combine_large_b` front tyres 7.4 cm above (model flaw, not fixed).

| tyre height vs ground (driving cycle) | before | after |
|---|---|---|
| tractor | -8.6 / +8.6 cm | 0 / +2.2 cm |
| tractor_heavy, tracked | -12.1 / +12.1 cm | 0 / +2.2 cm |
| combine_small | -19.8 / +19.1 cm | 0 / +2.2 cm |
| combine_large, large_b | -26.4 / +26.9 and -30.2 / +30.1 cm | 0 / +2.2 cm |

Measured on the real `tractor_view.gd` nodes (model bottom corners): before dip 3-18 cm, lift up to 18 cm; after dip 0, lift 2.1 cm.

## Fix applied (one coherent change)
* `suspension.gd`: no fake bounce; lean limited by the machine's size; `body_y()` raises the model so the lowest tyre rests exactly on y=0.
* `tractor_view.gd`: stands each model on the ground from its measured bounds; lean limit comes from model size.
* Trade-off: lean is now nearly invisible (about 0.3-0.5 degrees). Visible body lean with planted tyres needs wheels separated from the body.

## Drivetrain (phase 2, second change)
`vehicle_model.gd` keeps the same `step()` interface, so autopilot and farm_main are unchanged.
* **Acceleration** = min(grip, power / (mass x speed)). New data per vehicle in `vehicle_data.gd`: `mass_kg`, `wheelbase`, `max_steer_deg` (starting values, tune them). An implement's weight is added to the mass.
* **Brake** is separate from coasting. Pressing the opposite direction while rolling brakes, then reverses. Letting go only coasts (engine braking). An implement lengthens the stop.
* **Steering** is a bicycle model: yaw = speed x tan(wheel angle) / wheelbase. The wheel angle follows the input at a limited rate, the lock shrinks with speed, and sideways acceleration is capped at 0.7 g (understeer). The front wheels in `tractor_view.gd` now show that real angle.
* Old `accel` and `turn_rate` fields remain in the data but the physics no longer reads them.

| vehicle | 0-90% speed | coast stop | brake stop | turn radius at 1 u/s |
|---|---|---|---|---|
| tractor 75 hp | 1.2 s -> 2.9 s | 5.7 -> 11.5 m | 5.7 -> 8.2 m | 3.0 -> 2.2 m |
| tractor_heavy 160 hp | 1.3 -> 4.8 s | 8.0 -> 17.2 m | 8.0 -> 12.3 m | 4.2 -> 3.4 m |
| tractor_tracked 280 hp | 1.2 -> 4.4 s | 6.4 -> 12.8 m | 6.4 -> 9.1 m | 4.3 -> 4.1 m |

Autopilot jobs take about 17% longer (13.95 s -> 16.35 s for the one-row test), because of the slower, mass-based acceleration. The test limit was raised from 15 s to 20 s.

## Implement load only while working (phase 3, first step)
`loaded_config` now also keeps `free_speed` and `free_fuel_use`. `farm_main.gd` sets `m["_working"] = not view.raised` before `VehicleModel.step`.
Tool down: the loaded top speed and fuel use apply (as before). Tool raised: free speed and fuel use, but the implement's weight still counts for acceleration and braking.
If `_working` is missing, step() assumes working, so existing callers and tests behave as before.

## Still to do
* Handbrake and gear/direction selection (needs the new mobile controls, phase 5).
* Draft force from the working implement, slope, and wheel slip; the implement-load model is still the old power-versus-weight rule.
* Separate wheels from the body so the body can lean visibly.
* `combine_large_b` front tyres float 7.4 cm (model flaw); combine `hit_wid` is far smaller than the model width; `tools/plot_data_tail.gd` has a parse error (unused).
