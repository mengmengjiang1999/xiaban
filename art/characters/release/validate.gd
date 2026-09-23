extends SceneTree
## Execute from project root with tools/godot.sh --headless --script <absolute path>.
## Checks wardrobe fade, unchanged rig, actual attachment transforms across clips,
## and P4-versus-release observer eye positions. GPU rendering is separate.
const Wardrobe = preload("res://scripts/release_character.gd")
class World extends Node3D:
	var phase := "menu"
	var player: Node3D
var failures: Array[String] = []
var report := {"identities":{},"player_attachment_clips":{},"observer_eye_error_m":{}}
func _initialize(): call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func run() -> void:
	for identity in ["player","team_lead","supervisor","manager"]:
		var actor=load("res://scripts/humanoid_actor.gd").new()
		root.add_child(actor)
		await process_frame
		var cloth: MeshInstance3D
		for mesh in actor.meshes:
			if "CasualClothes" in mesh.name: cloth=mesh
		var original_area:=surface_area(cloth.mesh,1)
		var costume=Wardrobe.apply_to(actor,identity)
		var area_error:=absf(surface_area(cloth.mesh,1)-original_area)
		check(area_error<.00001,identity+" wardrobe retains complete shirt surface without geometric holes")
		check(costume == Wardrobe.apply_to(actor,identity),identity+" idempotence")
		check(actor.skeleton.get_bone_count()==53,identity+" original rig")
		check(actor.materials.size()==actor._material_modes.size(),identity+" fade bookkeeping")
		actor.set_camera_alpha(.4)
		for mat in actor.materials: check(is_equal_approx(mat.albedo_color.a,.4),identity+" fading")
		actor.set_camera_alpha(1)
		for mat in actor.materials: check(is_equal_approx(mat.albedo_color.a,1),identity+" restored opacity")
		var triangles:=0
		for mesh in actor.meshes:
			for surface in mesh.mesh.get_surface_count():
				var arrays=mesh.mesh.surface_get_arrays(surface)
				triangles += arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()/3
		report.identities[identity]={"meshes":actor.meshes.size(),"triangles":triangles,"bones":53,"actions":actor.ACTIONS,"shirt_area_error_m2":area_error}
		if identity=="player":
			actor.set_process(false)
			for action in actor.ACTIONS:
				actor.play_action(action,1,true,false,0)
				actor.animation_player.pause()
				var length:float=actor.action_length(action)
				var minimum:=Vector3(INF,INF,INF)
				var maximum:=Vector3(-INF,-INF,-INF)
				var samples:=ceili(length*60)+1
				for sample in samples:
					actor.animation_player.seek(minf(length,float(sample)/60),true)
					actor.skeleton.force_update_all_bone_transforms()
					await process_frame
					for mesh in actor.meshes:
						if mesh.skin!=null: continue
						for surface in mesh.mesh.get_surface_count():
							for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
								var point:Vector3=actor.to_local(mesh.to_global(vertex))
								minimum=minimum.min(point)
								maximum=maximum.max(point)
				var bounds={"samples":samples,"min":[minimum.x,minimum.y,minimum.z],"max":[maximum.x,maximum.y,maximum.z]}
				report.player_attachment_clips[action]=bounds
				check(minimum.y>=-.03,action+" attachment ground clearance")
				if action=="roll":
					check(maximum.y<=1.55 and absf(minimum.x)<=.53 and absf(maximum.x)<=.53 and absf(minimum.z)<=1.10 and absf(maximum.z)<=1.10,"roll accessories remain inside accepted swept volume")
		actor.queue_free()
		await process_frame
	var world:=World.new()
	root.add_child(world)
	var baseline=load("res://scripts/p4_guard.gd").new()
	baseline.setup(world,Vector3.ZERO,0)
	world.add_child(baseline)
	for identity in ["team_lead","supervisor","manager"]:
		var guard=load("res://scripts/release_guard.gd").new()
		guard.guard_id=identity
		guard.setup(world,Vector3.ZERO,0)
		world.add_child(guard)
		var maximum:=0.0
		for lift in [0.0,.5,1.0]:
			baseline._pose.apply_pose(lift,1)
			guard._pose.apply_pose(lift,1)
			maximum=maxf(maximum,baseline.eye_position().distance_to(guard.eye_position()))
		check(maximum<.0001,identity+" eye position matches accepted P4 telegraph")
		report.observer_eye_error_m[identity]=maximum
		guard.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	report["passed"]=failures.is_empty()
	report["failures"]=failures
	var output=ProjectSettings.globalize_path("res://../art/characters/release/validation.json")
	var file=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("RELEASE_CHARACTERS_VALIDATED ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func surface_area(mesh: Mesh, surface: int) -> float:
	var arrays:=mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for index in vertices.size(): indices.append(index)
	var area:=0.0
	for triangle in range(0,indices.size(),3):
		area+=(vertices[indices[triangle+1]]-vertices[indices[triangle]]).cross(vertices[indices[triangle+2]]-vertices[indices[triangle]]).length()*.5
	return area
