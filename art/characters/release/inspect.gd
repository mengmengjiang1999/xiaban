extends SceneTree
## Native render contact sheet, never used as an input/gameplay acceptance test.
const Wardrobe = preload("res://scripts/release_character.gd")
class World extends Node3D:
	var phase := "menu"
	var player: Node3D
var output := "/tmp/xiaban-release-character-visual"
var world: Node3D
var guards: Array[Node3D] = []
func _initialize(): call_deferred("run")
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	world=World.new()
	root.add_child(world)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("273943")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("d3e3eb")
	environment.environment.ambient_light_energy=.7
	world.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.light_energy=.9
	light.rotation_degrees=Vector3(-35,-30,0)
	world.add_child(light)
	var floor:=MeshInstance3D.new()
	var box:=BoxMesh.new();box.size=Vector3(9,.1,4)
	floor.mesh=box;floor.position=Vector3(0,-.05,0)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("6d7f86")
	floor.material_override=material;world.add_child(floor)
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.position=Vector3(0,1.5,-6.5)
	camera.look_at(Vector3(0,1.0,0))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3.9
	camera.current=true
	var player=load("res://scripts/humanoid_actor.gd").new()
	world.add_child(player);player.position.x=-2.3
	Wardrobe.apply_to(player,"player")
	player.animation_player.seek(0.0,true)
	player.animation_player.pause()
	_label("玩家 / 浅衬衫 · 工牌",Vector3(-2.3,2.05,0))
	var ids=["team_lead","supervisor","manager"]
	var names=["工位组长 / 背心 · 圆镜","办公室主管 / 束发 · 文件夹","楼梯口经理 / 西装 · 夹板"]
	for index in 3:
		var guard=load("res://scripts/release_guard.gd").new()
		guard.guard_id=ids[index]
		guard.setup(world,Vector3(-.78+index*1.54,0,0),0)
		world.add_child(guard)
		guard._label.visible=false
		guard._fan.visible=false
		guard._pose.apply_pose(1,1)
		guards.append(guard)
		_label(names[index],guard.position+Vector3(0,2.05,0))
	await _capture("01-wardrobes-front")
	for guard in guards: guard._pose.apply_pose(0,2.1)
	await _capture("02-office-work")
	camera.position=Vector3(-3.3,1.9,-6)
	camera.look_at(Vector3(0,1.0,0))
	await _capture("03-office-work-angle")
	player.play_action("roll",1,true,false,0)
	player.animation_player.seek(.65,true);player.animation_player.pause()
	await _capture("04-player-roll-accessories")
	world.queue_free()
	await process_frame
	print("RELEASE_CHARACTER_VISUAL_OK screenshots=4")
	quit()
func _label(value: String, position: Vector3) -> void:
	var label:=Label3D.new()
	label.text=value;label.position=position
	label.font=load("res://assets/fonts/NotoSansSC-Regular.otf")
	label.font_size=32;label.pixel_size=.0025
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=true;label.outline_size=5
	world.add_child(label)
func _capture(name: String) -> void:
	for unused in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
