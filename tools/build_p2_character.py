"""Retarget the licensed Quaternius Standard clips onto the dressed MPFB adult.

Run using Blender 4.5 LTS in background mode. Inputs are documented in
art/characters/README.md; output is a self-contained GLB with six named actions.
The original files stay intact. No plugin is needed to rebuild from the base .blend.
"""
from pathlib import Path
import argparse
import json
import math
import sys
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--base', default=str(ROOT / 'art/characters/source/office_adult_base.blend'))
parser.add_argument('--animations', default=str(ROOT / 'art/characters/source/quaternius_standard_1_0.glb'))
parser.add_argument('--output', default=str(ROOT / 'game/assets/characters/office_worker.glb'))
parser.add_argument('--blend', default=str(ROOT / 'art/characters/office_worker.blend'))
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
CLIPS = {'idle':'Idle_Loop','walk':'Walk_Loop','run':'Sprint_Loop',
         'crouch_idle':'Crouch_Idle_Loop','crouch_walk':'Crouch_Fwd_Loop','roll':'Roll'}
SOURCE_FPS = 30
BAKE_FPS = 60
# The physical floor is at zero; the visible office carpet is 17 mm higher.
GROUND_HEIGHT = 0.025
BONES = {'Root':'root','pelvis':'DEF-hips','spine_01':'DEF-spine.001',
         'spine_02':'DEF-spine.002','spine_03':'DEF-spine.003','neck_01':'DEF-neck','head':'DEF-head'}
for side, suffix in [('l','L'),('r','R')]:
    for target, source in [('clavicle','shoulder'),('upperarm','upper_arm'),('lowerarm','forearm'),
                           ('hand','hand'),('thigh','thigh'),('calf','shin'),('foot','foot'),('ball','toe')]:
        BONES[f'{target}_{side}'] = f'DEF-{source}.{suffix}'
    for finger in ['index','middle','pinky','ring','thumb']:
        for segment in range(1,4):
            source = f'thumb.{segment:02}' if finger == 'thumb' else f'f_{finger}.{segment:02}'
            BONES[f'{finger}_{segment:02}_{side}'] = f'DEF-{source}.{suffix}'

bpy.ops.wm.open_mainfile(filepath=str(Path(args.base).resolve()))
scene = bpy.context.scene
scene.render.fps = SOURCE_FPS
scene.render.fps_base = 1
scene.frame_set(0)
target = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
target.name = 'OfficeWorkerRig'
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
# Bake the adult morphs and clothing masks at rest, retaining skin vertex groups.
# Helpers and hidden body triangles must not be exported beneath the outfit.
for bone in target.pose.bones:
    bone.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
for obj in meshes:
    evaluated = obj.evaluated_get(depsgraph)
    baked = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
    obj.modifiers.clear()
    obj.data = baked
    skin = obj.modifiers.new('Skin', 'ARMATURE')
    skin.object = target
    assert any(v.groups for v in baked.vertices), f'Skin weights lost: {obj.name}'

# The supplied outfit mask stops near the deltoids, well inside the short
# sleeves. Those hidden arm faces can emerge through the independently skinned
# cloth when the shoulders rotate. Extend only that existing hidden-body mask,
# using the actual sleeve rims in this adult's rest pose rather than a fixed
# height, enlarged clothing, or deleted visible arm geometry.
body = next(o for o in meshes if 'Body' in o.name)
clothes = next(o for o in meshes if 'CasualClothes' in o.name)
edge_faces = {tuple(sorted(edge.vertices)): 0 for edge in clothes.data.edges}
for face in clothes.data.polygons:
    for edge in face.edge_keys:
        edge_faces[tuple(sorted(edge))] += 1
boundary_neighbors = {}
for (first, second), face_count in edge_faces.items():
    if face_count == 1:
        boundary_neighbors.setdefault(first, set()).add(second)
        boundary_neighbors.setdefault(second, set()).add(first)
unvisited = set(boundary_neighbors)
boundary_rings = []
while unvisited:
    pending = [unvisited.pop()]
    ring = []
    while pending:
        vertex = pending.pop()
        ring.append(clothes.matrix_world @ clothes.data.vertices[vertex].co)
        for neighbor in boundary_neighbors[vertex]:
            if neighbor in unvisited:
                unvisited.remove(neighbor)
                pending.append(neighbor)
    boundary_rings.append(ring)

sleeve_mask_report = {}
hidden_faces = set()
for side in ['l', 'r']:
    bone = target.data.bones[f'upperarm_{side}']
    shoulder = target.matrix_world @ bone.head_local
    elbow = target.matrix_world @ bone.tail_local
    arm_axis = (elbow - shoulder).normalized()
    arm_length = (elbow - shoulder).length
    candidates = []
    for ring in boundary_rings:
        center = sum(ring, Vector()) / len(ring)
        along = (center - shoulder).dot(arm_axis)
        radial = (center - shoulder - arm_axis * along).length
        if len(ring) >= 12 and 0.25 * arm_length < along < 0.80 * arm_length and radial < 0.08:
            candidates.append((abs(along - 0.55 * arm_length), ring))
    assert candidates, f'Cannot identify the actual {side} short-sleeve rim'
    rim = min(candidates, key=lambda candidate: candidate[0])[1]
    rim_start = min((point - shoulder).dot(arm_axis) for point in rim)
    # Retain at least 12 mm of skin beneath even the shortest part of the rim.
    # A face is removed only if ALL its vertices are still inside that limit.
    cutoff = rim_start - 0.012
    upperarm_group = body.vertex_groups[f'upperarm_{side}'].index
    removed = []
    for face in body.data.polygons:
        vertices = [body.data.vertices[index] for index in face.vertices]
        if not all(any(group.group == upperarm_group and group.weight > 0.1 for group in vertex.groups) for vertex in vertices):
            continue
        coordinates = [body.matrix_world @ vertex.co - shoulder for vertex in vertices]
        projections = [point.dot(arm_axis) for point in coordinates]
        if min(projections) >= -0.02 and max(projections) < cutoff and all((point - arm_axis * along).length < 0.10 for point, along in zip(coordinates, projections)):
            hidden_faces.add(face.index)
            removed.append(face.index)
    assert removed, f'The {side} sleeve should contain masked arm faces'
    sleeve_mask_report[side] = {'removed_faces_before_reduction': len(removed),
                               'sleeve_rim_min_distance_from_shoulder_m': rim_start,
                               'mask_end_distance_from_shoulder_m': cutoff,
                               'minimum_skin_overlap_below_sleeve_m': 0.012}
mesh_edit = bmesh.new()
mesh_edit.from_mesh(body.data)
mesh_edit.faces.ensure_lookup_table()
bmesh.ops.delete(mesh_edit, geom=[mesh_edit.faces[index] for index in hidden_faces], context='FACES')
mesh_edit.to_mesh(body.data)
mesh_edit.free()
body.data.update()
print('P2_SLEEVE_MASK', json.dumps(sleeve_mask_report), flush=True)

# MPFB wires Alpha on every material, which makes glTF export even skin and
# clothing as BLEND. Transparent sorting then draws back-facing hair over the
# face and the hidden body over clothes. Keep solid surfaces in the depth pass;
# hair/brows use an explicit clip node understood by the glTF exporter.
for obj in meshes:
    cutout = any(part in obj.name for part in ['Hair', 'Eyebrows'])
    for material in obj.data.materials:
        shader = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        alpha = shader.inputs['Alpha']
        incoming = alpha.links[0].from_socket if alpha.links else None
        for link in list(alpha.links):
            material.node_tree.links.remove(link)
        alpha.default_value = 1.0
        if cutout and incoming:
            clip = material.node_tree.nodes.new('ShaderNodeMath')
            clip.operation = 'GREATER_THAN'
            clip.inputs[1].default_value = 0.4
            material.node_tree.links.new(incoming, clip.inputs[0])
            material.node_tree.links.new(clip.outputs[0], alpha)

# A single runtime sample should stay near the 20k-triangle trial budget. Bake
# modest topology reduction at rest; the modifier interpolates the skin groups.
for obj in meshes:
    if len(obj.data.polygons) < 400:
        continue
    skin = obj.modifiers.get('Skin')
    obj.modifiers.remove(skin)
    reduction = obj.modifiers.new('RuntimeTopology', 'DECIMATE')
    reduction.ratio = 0.60
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=reduction.name)
    skin = obj.modifiers.new('Skin', 'ARMATURE')
    skin.object = target

# Use plain cloth for the shirt component; keep the authored denim and normal map.
clothes = next(o for o in meshes if 'CasualClothes' in o.name)
shirt = clothes.data.materials[0].copy()
shirt.name = 'PlainTealCotton'
principled = next(n for n in shirt.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
for link in list(principled.inputs['Base Color'].links):
    shirt.node_tree.links.remove(link)
principled.inputs['Base Color'].default_value = (0.055,0.16,0.17,1)
principled.inputs['Roughness'].default_value = 0.88
clothes.data.materials.append(shirt)
parents = list(range(len(clothes.data.vertices)))
def find(i):
    while parents[i] != i:
        parents[i] = parents[parents[i]]
        i = parents[i]
    return i
for edge in clothes.data.edges:
    a,b = map(find, edge.vertices)
    parents[a] = b
heights = {}
for v in clothes.data.vertices:
    component = find(v.index)
    heights[component] = max(heights.get(component, -math.inf), (clothes.matrix_world @ v.co).z)
for face in clothes.data.polygons:
    if heights[find(face.vertices[0])] > 1.35:
        face.material_index = len(clothes.data.materials) - 1
# A small cloth clearance keeps reduced sleeve edges outside the upper arms
# through the retargeted shoulder rotations, without adding duplicate surfaces.
for vertex in clothes.data.vertices:
    if (clothes.matrix_world @ vertex.co).z > 1.30:
        vertex.co += vertex.normal * 0.004
clothes.data.update()

# Limit runtime texture cost without changing the source pack.
for image in bpy.data.images:
    if image.type == 'IMAGE' and image.size[0] > 0:
        ratio = min(1, 1024 / max(image.size))
        if ratio < 1:
            image.scale(round(image.size[0]*ratio), round(image.size[1]*ratio))
        image.pack()

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(Path(args.animations).resolve()))
source_objects = set(bpy.data.objects) - before
source = next(o for o in source_objects if o.type == 'ARMATURE')
source.animation_data.use_nla = False
source_actions = {a.name.rsplit('|',1)[-1]:a for a in bpy.data.actions}
scene.render.fps = BAKE_FPS
for name in CLIPS.values():
    assert name in source_actions, f'Missing licensed source clip: {name}'
for dst,src in BONES.items():
    assert dst in target.pose.bones and src in source.pose.bones, f'Invalid bone map: {dst} / {src}'
# Local pose axes differ, including the target A-pose versus source T-pose arms.
# Align limb directions at reference, retaining each target bone's axial roll.
reference = {}
rest = {b.name:b.matrix_local.copy() for b in target.data.bones}
for dst,src in BONES.items():
    target_rotation = rest[dst].to_quaternion()
    source_rotation = source.data.bones[src].matrix_local.to_quaternion()
    if dst not in ['Root','pelvis','spine_01','spine_02','spine_03','neck_01','head']:
        target_direction = target_rotation @ Vector((0,1,0))
        source_direction = source_rotation @ Vector((0,1,0))
        target_rotation = target_direction.rotation_difference(source_direction) @ target_rotation
    reference[dst] = source_rotation.inverted() @ target_rotation
height_ratio = target.data.bones['pelvis'].head_local.z / source.data.bones['DEF-hips'].head_local.z
ordered = list(target.data.bones)
target.animation_data_clear()
target.animation_data_create()

def set_source(action_name, frame):
    action = source_actions[action_name]
    source.animation_data.action = action
    source.animation_data.action_slot = action.slots[0]
    scene.frame_set(math.floor(frame), subframe=frame-math.floor(frame))
    bpy.context.view_layer.update()

def retarget():
    desired = {}
    result = {}
    for bone in ordered:
        name = bone.name
        src = BONES[name]
        parent = bone.parent
        if parent:
            rest_local = rest[parent.name].inverted() @ rest[name]
            position = desired[parent.name] @ rest_local.translation
        else:
            rest_local = rest[name]
            position = rest[name].translation.copy()
        if name == 'pelvis':
            difference = source.pose.bones[src].matrix.translation - source.data.bones[src].head_local
            position = rest[name].translation + difference * height_ratio
        rotation = source.pose.bones[src].matrix.to_quaternion() @ reference[name]
        if name == 'Root':
            position = rest[name].translation.copy()
            rotation = rest[name].to_quaternion()
        world = Matrix.Translation(position) @ rotation.to_matrix().to_4x4()
        desired[name] = world
        local = desired[parent.name].inverted() @ world if parent else world
        basis = rest_local.inverted() @ local
        result[name] = (basis.to_translation(), basis.to_quaternion())
    return result

def apply_pose(pose):
    for name,(location,rotation) in pose.items():
        bone = target.pose.bones[name]
        bone.location = location
        bone.rotation_mode = 'QUATERNION'
        bone.rotation_quaternion = rotation
        bone.scale = (1,1,1)
    bpy.context.view_layer.update()

def floor_z():
    graph = bpy.context.evaluated_depsgraph_get()
    minimum = math.inf
    for obj in meshes:
        evaluated = obj.evaluated_get(graph)
        data = evaluated.to_mesh()
        coordinates = np.empty(len(data.vertices)*3, dtype=np.float32)
        data.vertices.foreach_get('co', coordinates)
        coordinates = coordinates.reshape((-1,3))
        row = np.array(evaluated.matrix_world[2])
        minimum = min(minimum, float((coordinates @ row[:3] + row[3]).min()))
        evaluated.to_mesh_clear()
    return minimum

def smoothstep(t):
    t = min(1,max(0,t))
    return t*t*(3-2*t)

set_source(CLIPS['crouch_idle'],0)
crouch_pose = retarget()
report = {'source':'Quaternius Universal Animation Library Standard-1.0 (CC0)',
          'character':'MPFB 2.0.17 + selected MakeHuman system assets (CC0)',
          'target_bones':len(ordered),'clips':{},'height_ratio':height_ratio,
          'sample_rate_fps':BAKE_FPS,'planted_floor_height_m':GROUND_HEIGHT,
          'sleeve_hidden_body_mask':sleeve_mask_report}
created = []
for name,source_name in CLIPS.items():
    source_action = source_actions[source_name]
    start,end = source_action.frame_range
    count = round((end-start) * BAKE_FPS / SOURCE_FPS)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    target.animation_data.action = action
    previous_rotations = {}
    floor_corrections = []
    for frame in range(count+1):
        # Capture each source pose before setting the output animation frame.
        set_source(source_name,start+(end-start)*frame/count)
        pose = retarget()
        if name == 'roll':
            phase = frame/count
            blend = max(1-smoothstep(phase/.16), smoothstep((phase-.67)/.33))
            for bone,(location,rotation) in pose.items():
                reference_location,reference_rotation = crouch_pose[bone]
                pose[bone] = (location.lerp(reference_location,blend), rotation.slerp(reference_rotation,blend))
        scene.frame_set(frame)
        apply_pose(pose)
        minimum = floor_z()
        # Keep planted actions on the floor. Sprint retains its airborne phase.
        correction = (GROUND_HEIGHT-minimum) if name != 'run' else max(0,GROUND_HEIGHT-minimum)
        target.pose.bones['Root'].location.z += correction
        floor_corrections.append(correction)
        for bone in target.pose.bones:
            q = bone.rotation_quaternion.copy()
            if bone.name in previous_rotations and q.dot(previous_rotations[bone.name]) < 0:
                q.negate()
            bone.rotation_quaternion = q
            previous_rotations[bone.name] = q.copy()
            bone.keyframe_insert('location', frame=frame, group=bone.name)
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
    # Blender 4.5 actions use slots. Set sampled keys to linear to avoid overshoot.
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                channelbag = strip.channelbag(slot)
                if channelbag:
                    for curve in channelbag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
    report['clips'][name] = {'source':source_name,'duration':count/BAKE_FPS,'frames':count+1,
                             'floor_correction_range':[min(floor_corrections),max(floor_corrections)]}
    created.append(action)
    print('P2_BAKED',name,count+1,'frames',flush=True)

# Keep exactly the six curated clips, expose them as named NLA tracks for glTF.
target.animation_data.action = None
for action in created:
    track = target.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name,0,action)
    strip.action_slot = action.slots[0]
    track.mute = True
for obj in source_objects:
    bpy.data.objects.remove(obj,do_unlink=True)
for action in list(bpy.data.actions):
    if action not in created:
        bpy.data.actions.remove(action)
# Export -Z as forward for the established Godot movement controller.
orientation = bpy.data.objects.new('GodotForward',None)
scene.collection.objects.link(orientation)
orientation.rotation_euler.z = math.pi
for obj in [target]+meshes:
    if obj.parent is None:
        obj.parent = orientation
for bone in target.pose.bones:
    bone.matrix_basis = Matrix.Identity(4)
scene.frame_set(0)
bpy.context.view_layer.update()
for mesh in meshes:
    mesh.data.calc_loop_triangles()
report['triangles'] = sum(len(o.data.loop_triangles) for o in meshes)
report['meshes'] = len(meshes)
report['textures'] = [{'name':i.name,'size':list(i.size)} for i in bpy.data.images if i.type=='IMAGE' and i.users]
for path in [args.output,args.blend]:
    Path(path).parent.mkdir(parents=True,exist_ok=True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.blend).resolve()),compress=True)
bpy.ops.object.select_all(action='DESELECT')
for obj in [orientation,target]+meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.export_scene.gltf(filepath=str(Path(args.output).resolve()),export_format='GLB',
                         use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',
                         export_force_sampling=True,export_frame_range=False,
                         export_yup=True,export_skins=True,export_morph=False)
report['glb_bytes'] = Path(args.output).stat().st_size
Path(args.output).with_suffix('.json').write_text(json.dumps(report,indent=2))
print('P2_CHARACTER_READY',json.dumps(report),flush=True)
