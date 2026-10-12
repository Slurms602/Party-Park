class_name Dressing
## Kenney's CC0 props (assets/props/*, licence in each folder), shared by every map: the board's palms, the alleys' arcades...

static var _scenes := {}


static func prop(parent: Node3D, path: String, pos: Vector3, yaw := 0.0, s := 1.0, solid := false) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load("res://assets/props/%s.glb" % path)
	var n: Node3D = _scenes[path].instantiate()
	n.position = pos
	n.rotation_degrees.y = yaw
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	if solid:
		var box := _bounds(n)
		var body := StaticBody3D.new()
		body.transform = n.transform
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.shape.size = box.size
		cs.position = box.get_center()
		body.add_child(cs)
		parent.add_child(body)
	return n


static func _bounds(n: Node3D) -> AABB:
	## The prop's mesh bounds in its own space (before its scale).
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != n:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		out = xf * mi.get_aabb() if first else out.merge(xf * mi.get_aabb())
		first = false
	return out
