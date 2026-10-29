extends SceneTree
# Repeatable vehicle physics measurements (headless). Prints a markdown report.
#   godot --headless --script res://scripts/tests/physics_report.gd
# Measures every catalogue vehicle on flat ground: acceleration, braking, turning circle,
# the effect of each implement, and how far the tyres move off the ground plane while the
# looks-only suspension (suspension.gd) runs through a fixed driving cycle.
# Tyre contact points are approximated from the machine footprint (hit_len x hit_wid).

const VehicleData := preload("res://scripts/vehicle_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")
const ImplementData := preload("res://scripts/implement_data.gd")

const DT := 1.0 / 60.0

# Loaded dynamically so the same report runs against the old and the new suspension API.
var Susp: GDScript = load("res://scripts/suspension.gd")
var new_api := false

func _fresh(cfg: Dictionary) -> Dictionary:
	return {"x": 100.0, "z": -100.0, "heading": 0.0, "speed": 0.0, "fuel": 9999.0, "hours": 0.0,
		"implement": "none", "vehicle": str(cfg["id"])}

# Seconds to reach 90% of top speed from rest at full throttle.
func _time_to_90(cfg: Dictionary) -> float:
	var v := _fresh(cfg)
	var t := 0.0
	while float(v["speed"]) < 0.9 * float(cfg["max_speed"]) and t < 60.0:
		VehicleModel.step(v, cfg, 1.0, 0.0, DT)
		t += DT
	return t

# Distance and time to stop from top speed. brake = true uses full reverse throttle, else coasting.
func _stop(cfg: Dictionary, brake: bool) -> Vector2:
	var v := _fresh(cfg)
	v["speed"] = float(cfg["max_speed"])
	var t := 0.0
	while float(v["speed"]) > 0.01 and t < 60.0:
		VehicleModel.step(v, cfg, -1.0 if brake else 0.0, 0.0, DT)
		t += DT
	return Vector2(float(v["z"]) + 100.0, t)   # start z is -100, clear of the farmhouse

# Turning circle radius with full steering at a held ground speed.
func _radius(cfg: Dictionary, speed: float) -> float:
	var v := _fresh(cfg)
	var thr := speed / float(cfg["max_speed"])
	v["speed"] = speed
	var h0 := float(v["heading"])
	var a := 0.0
	for i in 120:
		VehicleModel.step(v, cfg, thr, 1.0, DT)
		a += wrapf(float(v["heading"]) - h0, -PI, PI)
		h0 = float(v["heading"])
	var yaw: float = absf(a) / (120.0 * DT)
	if yaw < 0.0001:
		return INF
	return speed / yaw

# Tyre height range (metres) over a fixed driving cycle, using the same inputs the view uses.
func _tyre_range(cfg: Dictionary) -> Vector2:
	var v := _fresh(cfg)
	var hl: float = float(cfg["hit_len"]) * 0.5
	var hw: float = float(cfg["hit_wid"]) * 0.5
	var s: Dictionary = Susp.call("new_state")
	var cycle := [[5.0, 1.0, 0.0], [4.0, 1.0, 1.0], [4.0, 1.0, -1.0], [2.0, -1.0, 0.0], [3.0, 0.0, 0.0]]
	var prev_sp := 0.0
	var prev_h := 0.0
	var lo := 0.0
	var hi := 0.0
	for seg in cycle:
		for i in int(float(seg[0]) / DT):
			VehicleModel.step(v, cfg, float(seg[1]), float(seg[2]), DT)
			var sp: float = v["speed"]
			var yaw := wrapf(float(v["heading"]) - prev_h, -PI, PI) / DT
			var acc := (sp - prev_sp) / DT
			prev_sp = sp
			prev_h = float(v["heading"])
			var body_y := 0.0
			if new_api:
				Susp.call("step", s, acc, sp, yaw, DT, hl, hw)
				body_y = float(Susp.call("body_y", s, hl, hw))
			else:
				Susp.call("step", s, acc, sp, yaw, DT)
				body_y = float(s["bounce"])
			var p: float = s["pitch"]
			var r: float = s["roll"]
			for cx in [-hw, hw]:
				for cz in [-hl, hl]:
					var y: float = body_y + cx * sin(r) * cos(p) - cz * sin(p)
					lo = minf(lo, y)
					hi = maxf(hi, y)
	return Vector2(lo, hi)

func _init() -> void:
	for m in Susp.get_script_method_list():
		if str(m["name"]) == "body_y":
			new_api = true
	print("# Vehicle physics report (flat ground, 60 Hz)")
	print("")
	print("| vehicle | hp | top u/s | 0-90% s | coast stop m | brake stop m | radius @1 u/s | radius @top | tyre dip cm | tyre lift cm |")
	print("|---|---|---|---|---|---|---|---|---|---|")
	for id in VehicleData.VEHICLES:
		var cfg: Dictionary = VehicleData.VEHICLES[id]
		var coast := _stop(cfg, false)
		var brk := _stop(cfg, true)
		var tr := _tyre_range(cfg)
		print("| %s | %d | %.1f | %.2f | %.1f | %.1f | %s | %.1f | %.1f | %.1f |" % [
			id, int(cfg["power_hp"]), float(cfg["max_speed"]), _time_to_90(cfg), coast.x, brk.x,
			_fmt(_radius(cfg, 1.0)), _radius(cfg, float(cfg["max_speed"])), -tr.x * 100.0, tr.y * 100.0])
	print("")
	print("## Implement load (top speed in u/s, acceleration in u/s^2, engine load ratio)")
	print("")
	var ids: Array = ["none"] + ImplementData.ITEMS.keys()
	var head := "| implement | kg |"
	var sep := "|---|---|"
	for vid in VehicleData.ids_of_type("tractor"):
		head += " %s |" % vid
		sep += "---|"
	print(head)
	print(sep)
	for iid in ids:
		var row := "| %s | %d |" % [iid, int(ImplementData.weight_of(iid))]
		for vid in VehicleData.ids_of_type("tractor"):
			var lc: Dictionary = VehicleModel.loaded_config(VehicleData.VEHICLES[vid], iid)
			row += " %.1f / %.1f / %.2f |" % [float(lc["max_speed"]), float(lc["accel"]), float(lc["load_ratio"])]
		print(row)
	quit()

func _fmt(r: float) -> String:
	return "inf" if r == INF else "%.1f" % r
