extends "res://scripts/level.gd"
## Reuse v0.1 footprints with opaque walls for shoulder-camera validation.

func _wall_visual(r: Rect2) -> void:
	# Opaque plaster starts above the skirt. Overlapping their full side faces
	# makes the depth buffer alternate between two colors as the camera moves.
	var skirt_height := 0.28
	var plaster_height := 2.3 - skirt_height
	var center := r.get_center()
	_box(Vector3(center.x, skirt_height + plaster_height * 0.5, center.y),
		Vector3(r.size.x, plaster_height, r.size.y), _material("glass", Color("91a9aa")))
	_box(Vector3(center.x, skirt_height * 0.5, center.y),
		Vector3(r.size.x, skirt_height, r.size.y), _material("wall", Color("526873")))
	_box(Vector3(center.x, 2.32, center.y),
		Vector3(r.size.x + 0.03, 0.07, r.size.y + 0.03), _material("frame", Color("82999b")))

func _material(key: String, color: Color, glow: bool = false) -> StandardMaterial3D:
	if key == "glass":
		color = Color("91a9aa")
	return super._material(key, color, glow)

func _desk(r: Rect2) -> void:
	super._desk(r)
	# The monitor is above the movement blocker: include it in camera collision.
	var seats := maxi(1, int(r.size.x / 1.7))
	for i in range(seats):
		var x := r.position.x + (i + 0.5) * r.size.x / seats
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.position = Vector3(x, 1.24, r.get_center().y - 0.12)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.72, 0.45, 0.1)
		collider.shape = shape
		body.add_child(collider)
		add_child(body)

func _sign(text: String, at: Vector3, color: Color, size: int = 36) -> void:
	# Ground-level billboard labels would intersect the character in this view.
	if text.begins_with("01") or text.begins_with("02") or text.begins_with("03"):
		return
	super._sign(text, at, color, size)
