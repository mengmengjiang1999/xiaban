extends SceneTree
## Resource-lifetime regression; actual GPU stalls require browser rAF checks.
## Godot exposes material RIDs, not the internal BaseMaterial3D shader RID.
var world: Node3D
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = load("res://scenes/release.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	world.set_process(false)
	var actor: Node3D = world.player.actor
	var retained: Array = actor._camera_fade_shader_materials
	_check(retained.size() == actor.materials.size() and retained.size() > 6,
		"Release retains a fade variant for every final wardrobe material")
	_check(world.guards.all(func(guard): return guard.actor._camera_fade_shader_materials.is_empty()),
		"Only the release player opts into shader retention")
	var resource_ids: Array[RID] = []
	var source_ids: Array[RID] = []
	var modes: Array[int] = []
	var alphas: Array[float] = []
	var colors: Array[Color] = []
	var matching_features := true
	for index in retained.size():
		var original: StandardMaterial3D = actor.materials[index]
		var keeper: StandardMaterial3D = retained[index]
		resource_ids.append(keeper.get_rid())
		source_ids.append(original.get_rid())
		modes.append(original.transparency)
		alphas.append(original.albedo_color.a)
		colors.append(keeper.albedo_color)
		matching_features = matching_features and keeper != original and keeper.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		for property in ["albedo_texture", "normal_texture", "normal_enabled", "cull_mode", "vertex_color_use_as_albedo", "shading_mode", "alpha_scissor_threshold"]:
			matching_features = matching_features and keeper.get(property) == original.get(property)
	_check(matching_features, "Retained variants preserve texture, cutout, normals, culling and vertex-color features")
	actor.retain_camera_fade_shaders()
	_check(actor._camera_fade_shader_materials == retained, "Repeated preparation does not replace or append retained resources")
	var preserved := true
	var correct_fade := true
	var restored := true
	for cycle in 12:
		for amount in [1.0, 0.998, 0.5, 0.12, 0.5, 1.0]:
			actor.set_camera_alpha(amount)
			await _frames(1)
			for index in retained.size():
				var keeper: StandardMaterial3D = retained[index]
				var original: StandardMaterial3D = actor.materials[index]
				preserved = preserved and keeper.get_rid() == resource_ids[index] and original.get_rid() == source_ids[index]
				preserved = preserved and keeper.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH and keeper.albedo_color == colors[index]
				correct_fade = correct_fade and is_equal_approx(original.albedo_color.a, alphas[index] * amount)
				if amount == 1.0: restored = restored and original.transparency == modes[index]
	_check(preserved, "Twelve fade cycles preserve every immutable keeper and authored material resource RID")
	_check(correct_fade and restored, "Every fade scales authored alpha and restores original opaque/hair-cutout modes")
	_check(actor._material_modes == modes and actor._material_alphas == alphas,
		"Material registration arrays retain their original order and values")
	print("RELEASE_FADE_SHADER_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	world.show_menu()
	for source in world.find_children("*", "AudioStreamPlayer", true, false): source.stop()
	await _frames(3)
	OS.delay_msec(150)
	world.queue_free()
	await _frames(4)
	OS.delay_msec(150)
	quit(1 if failed else 0)

func _frames(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS ", message)
	else:
		failed += 1
		push_error("FAIL " + message)
