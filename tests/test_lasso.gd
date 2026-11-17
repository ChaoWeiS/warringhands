extends SceneTree
## The lasso is drawn and used as a smooth curve, even when the finger's
## points come in far apart (slow frames).
## Run: godot --headless -s res://tests/test_lasso.gd

var failures := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _initialize() -> void:
	var Panes = load("res://scripts/pane_layout.gd")
	var sparse := PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)])
	var smooth: PackedVector2Array = Panes.smooth_path(sparse)
	var longest := 0.0
	for i in smooth.size() - 1:
		longest = maxf(longest, smooth[i].distance_to(smooth[i + 1]))
	check("far-apart points are filled in (%d points, longest step %.1f px)" % [smooth.size(), longest],
			smooth.size() > 40 and longest < 16.0)
	var through := true
	for p in sparse:
		var near := false
		for q in smooth:
			near = near or q.distance_to(p) < 0.5
		through = through and near
	check("...and the curve still goes through where the finger was", through)
	check("dense paths stay about the same size",
			Panes.smooth_path(PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 2), Vector2(14, 6)])).size() <= 8)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
