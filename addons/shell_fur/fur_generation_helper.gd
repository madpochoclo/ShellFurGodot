static func update_mmi(layers : int, mmi : MultiMeshInstance, mesh : Mesh, material : Material, blendshape_index : int) -> void:
	var mdt = MeshDataTool.new()
	if mmi.multimesh == null:
		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		mmi.multimesh.color_format = MultiMesh.COLOR_FLOAT
		mmi.multimesh.custom_data_format = MultiMesh.CUSTOM_DATA_NONE
		
	var new_mesh : Mesh = mesh.duplicate(true)
	
	# Blendshape_index of -1 means not to use blendshapes
	if blendshape_index != -1:
		new_mesh = _blendshape_to_vertex_color(new_mesh, material, blendshape_index)
		
	mmi.multimesh.mesh = new_mesh
	
	mmi.multimesh.instance_count = layers
	mmi.multimesh.visible_instance_count = layers
	for surface in new_mesh.get_surface_count():
		mmi.multimesh.mesh.surface_set_material(surface, material)
	
	# We place the layers in 4 loops so Visible Instance Count can be lowered
	# by half and to a quarter and correctly show spread out layers.
	# The LOD system is not implemented yet.
	var index = 0
	for LOD_layer in 4:
		for i in layers / 4:
			mmi.multimesh.set_instance_transform(i, Transform(Basis(), Vector3()))
			var grey = float(i) / float(layers / 4) + float(LOD_layer) * 1.0 / float(layers)
			mmi.multimesh.set_instance_color(index, Color(1.0, 1.0, 1.0, grey))
			index += 1

static func _blendshape_to_vertex_color(mesh: Mesh, material : Material, blendshape_index: int) -> Mesh:
	var mdt = MeshDataTool.new()
	
	var base_mesh_array : PoolVector3Array
	var fur_blend_shape_mesh_array : PoolVector3Array
	for m in mesh.get_surface_count():
		base_mesh_array += mesh.surface_get_arrays(m)[0]
		fur_blend_shape_mesh_array += mesh.surface_get_blend_shape_arrays(m)[blendshape_index][0]

	var compare_array = []
	var compare_array_adjusted = []

	var longest_diff_length = 0.0
	var longest_diff_vec

	for i in base_mesh_array.size():
		var diffvec = fur_blend_shape_mesh_array[i] - base_mesh_array[i]
		compare_array.append(diffvec)

		if abs(diffvec.x) > longest_diff_length:
			longest_diff_length = abs(diffvec.x)
			longest_diff_vec = diffvec
		if abs(diffvec.y) > longest_diff_length:
			longest_diff_length = abs(diffvec.y)
			longest_diff_vec = diffvec
		if abs(diffvec.z) > longest_diff_length:
			longest_diff_length = abs(diffvec.z)
			longest_diff_vec = diffvec

	for i in compare_array.size():
		var newx = vertex_diff_to_vertex_color_value(compare_array[i].x, longest_diff_length)
		var newy = vertex_diff_to_vertex_color_value(compare_array[i].y, longest_diff_length)
		var newz = vertex_diff_to_vertex_color_value(compare_array[i].z, longest_diff_length)
		compare_array_adjusted.append( Vector3(newx, newy, newz))

	material.set_shader_param("blend_shape_multiplier", longest_diff_length)

	mdt.create_from_surface(_multiple_surfaces_to_single(mesh), 0)
	for i in range(mdt.get_vertex_count()):
		mdt.set_vertex_color(i, Color(compare_array_adjusted[i].x, compare_array_adjusted[i].y, compare_array_adjusted[i].z))
	var new_mesh = Mesh.new()
	mdt.commit_to_surface(new_mesh)
	return new_mesh

static func _multiple_surfaces_to_single(mesh : Mesh) -> Mesh:
	var st := SurfaceTool.new()
	
	var merging_mesh = Mesh.new()
	for surface in mesh.get_surface_count():
		st.append_from(mesh, surface, Transform.IDENTITY)
	merging_mesh = st.commit()
	
	return merging_mesh


static func vertex_diff_to_vertex_color_value(var value, var factor) -> float:
	return (value / factor) * 0.5 + 0.5


static func generate_mesh_shells(shell_fur_object : Spatial, parent_object : Spatial, layers : int, material : Material, blendshape_index : int):
	var mdt = MeshDataTool.new()
	var copy_mesh : Mesh = parent_object.mesh.duplicate(true)
	
	if blendshape_index != -1:
		copy_mesh = _blendshape_to_vertex_color(copy_mesh, material, blendshape_index)
	
	var merged_mesh = _multiple_surfaces_to_single(copy_mesh)

	for layer in layers:
		var new_object = MeshInstance.new()
		new_object.name = "fur_layer_" + str(layer)
		shell_fur_object.add_child(new_object)
		# Uncomment to debug whether shells are getting created
		#new_object.set_owner(shell_fur_object.get_tree().get_edited_scene_root())
		mdt.create_from_surface(merged_mesh, 0)
		for i in range(mdt.get_vertex_count()):
			var c = mdt.get_vertex_color(i)
			c.a = float(layer) / float(layers)
			mdt.set_vertex_color(i, c)
		var new_mesh := Mesh.new()
		mdt.commit_to_surface(new_mesh)
		
		new_object.mesh = new_mesh


static func generate_combined(shell_fur_object : Spatial, parent_object : Spatial, material : Material) -> void:
	var st = SurfaceTool.new()
	for child in shell_fur_object.get_children():
		st.append_from(child.mesh, 0, Transform.IDENTITY)
		shell_fur_object.remove_child(child)
	var combined_obj = MeshInstance.new()
	combined_obj.name = "CombinedFurMesh"
	combined_obj.mesh = st.commit()
	shell_fur_object.add_child(combined_obj)
	combined_obj.set_owner(shell_fur_object.get_tree().get_edited_scene_root())
	combined_obj.set_surface_material(0, material)
	combined_obj.set_skin(parent_object.get_skin())
	combined_obj.set_skeleton_path("../../..")