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

## Other findings (not changed yet)
* No separate brake: braking and coasting stop identically (about 1.3 s). No handbrake, no gears, no traction or slip.
* All tractors accelerate to 90% speed in 1.2-1.3 s regardless of power or mass. Heavy tractors are barely slowed by any implement.
* Steering radius is a fixed 3-4 m at low speed (not derived from wheelbase) and grows with speed; the visual front-wheel angle comes from the yaw rate, not a steering angle.
* Combine `hit_wid` (1.8-2.2) is far smaller than the model width (4.3-7.5).
* `combine_large_b` front tyres float 7.4 cm; `tools/plot_data_tail.gd` has a parse error (unused tool script).

## Proposed next steps
1. Data-driven drivetrain: power, mass, torque curve, separate brake/handbrake, steering angle from wheelbase; tractors differ meaningfully. Autopilot and its tests depend on the current model, so change it behind the same `step()` interface and re-run the headless job tests.
2. Separate wheels from the body so the body can lean visibly while tyres stay planted.
3. Implement load driven by draft force and slope, then traction/slip.
