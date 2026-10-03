class_name PlateSet
extends RefCounted

# The pre-rendered plates of the archive hall (docs/art/PLATE_CONTRACT.md): reads plates/shots.json,
# loads each plate's textures, knows the projection every plate was rendered with, and picks which
# three plates texture the proxy for a given camera. The shader (render/psx/plate_projection) and
# PlateSet.project must agree: tests/render/test_plates.gd pins it.
#
# Files per plate: plates/<dir>/beauty.png (beauty_m.png on mobile and the web), depth.png (RG8:
# 16-bit linear view depth), key.png and glow.png (L8). `dir` is the entry's "dir", else its id, else
# the id with ':' replaced by '_' (colons are not portable in file names). A `variant` entry ("dusk")
# shares its base plate's pose and depth. depth/key/glow are imported as Images (never
# VRAM-compressed: a compressed depth is garbage); key and glow are kept at half size.

const SHOTS_PATH := "res://assets/archive/plates/shots.json"
const PLATE_DIR := "res://assets/archive/plates/"
const ROLES := ["shot", "cover"]
# Bytes per pixel of the formats plates end up in (for the memory budget).
const BYTES_PER_PIXEL := {Image.FORMAT_L8: 1.0, Image.FORMAT_R8: 1.0, Image.FORMAT_RG8: 2.0, Image.FORMAT_LA8: 2.0, Image.FORMAT_RGB8: 3.0, Image.FORMAT_RGBA8: 4.0,
	Image.FORMAT_DXT1: 0.5, Image.FORMAT_RGTC_R: 0.5, Image.FORMAT_ETC: 0.5, Image.FORMAT_ETC2_RGB8: 0.5, Image.FORMAT_ETC2_R11: 0.5,
	Image.FORMAT_DXT5: 1.0, Image.FORMAT_BPTC_RGBA: 1.0, Image.FORMAT_ETC2_RGBA8: 1.0, Image.FORMAT_ASTC_4x4: 1.0, Image.FORMAT_RGTC_RG: 1.0, Image.FORMAT_ETC2_RG11: 1.0}

# Normalised entries: {id, variant, mode, focus, role, transform, fov_v_deg, near, far, size, dir}.
var plates: Array[Dictionary] = []
var errors: Array[String] = []
var wide_id := "wide"
var mobile := false
var _textures: Dictionary = {}   # "<id>|<variant>" -> {beauty, depth, key, glow, key_image, depth_image}

static var _cache: Dictionary = {}

static func available() -> bool:
	return FileAccess.file_exists(SHOTS_PATH)

# Mobile and the web draw the 1280-wide beauty copy.
static func is_mobile_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web")

# The shared, loaded set (textures are loaded once per process).
static func shared(load_mobile: bool) -> PlateSet:
	if not _cache.has(load_mobile):
		var plate_set := PlateSet.new()
		plate_set.mobile = load_mobile
		plate_set.read(SHOTS_PATH)
		plate_set.load_textures()
		_cache[load_mobile] = plate_set
	return _cache[load_mobile]

# ---- shots.json --------------------------------------------------------------------------------

func read(path: String) -> bool:
	plates.clear()
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("%s is missing" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	errors = validate(parsed)
	if not errors.is_empty():
		return false
	for entry: Dictionary in parsed["shots"]:
		plates.append(normalise(entry))
	var anchors := StageLight.anchors()
	wide_id = str(anchors.get("camera_wide", "wide"))
	return true

# Every rule of the contract a shots.json must keep. Empty = valid.
static func validate(parsed: Variant) -> Array[String]:
	var out: Array[String] = []
	if not parsed is Dictionary or not (parsed as Dictionary).get("shots") is Array:
		out.append("shots.json: expected {\"version\": 1, \"shots\": [...]}")
		return out
	if int(parsed.get("version", 0)) != 1:
		out.append("shots.json: version must be 1")
	var seen := {}
	for entry: Variant in parsed["shots"]:
		if not entry is Dictionary:
			out.append("shots.json: every shot is an object")
			continue
		var id := str(entry.get("id", ""))
		var label := "shot '%s'" % id
		if id.is_empty():
			out.append("a shot has no id")
		var key := "%s|%s" % [id, str(entry.get("variant", ""))]
		if seen.has(key):
			out.append("%s: duplicate (id, variant)" % label)
		seen[key] = true
		if str(entry.get("role", "")) not in ROLES:
			out.append("%s: role must be one of %s" % [label, ROLES])
		if not _vec(entry.get("position"), 3):
			out.append("%s: position must be [x, y, z]" % label)
		var basis: Variant = entry.get("basis")
		if not (basis is Array and (basis as Array).size() == 3 and (basis as Array).all(func(c: Variant) -> bool: return _vec(c, 3))):
			out.append("%s: basis must be three columns [[xx,xy,xz],[yx,yy,yz],[zx,zy,zz]]" % label)
		else:
			var b := _basis(basis)
			var unit := absf(b.x.length() - 1.0) < 0.002 and absf(b.y.length() - 1.0) < 0.002 and absf(b.z.length() - 1.0) < 0.002
			var square := absf(b.x.dot(b.y)) < 0.002 and absf(b.y.dot(b.z)) < 0.002 and absf(b.z.dot(b.x)) < 0.002
			if not unit or not square or b.determinant() < 0.0:
				out.append("%s: basis must be orthonormal and right-handed" % label)
			elif absf(b.x.y) > 0.01:
				out.append("%s: no roll may be baked into a plate (the x axis must be level)" % label)
		var fov := float(entry.get("fov_v_deg", 0.0))
		if fov <= 1.0 or fov >= 170.0:
			out.append("%s: fov_v_deg out of range" % label)
		var near := float(entry.get("near", 0.0))
		var far := float(entry.get("far", 0.0))
		if near <= 0.0 or far <= near:
			out.append("%s: need 0 < near < far" % label)
		if not _vec(entry.get("size"), 2) or int(entry["size"][0]) < 16 or int(entry["size"][1]) < 16:
			out.append("%s: size must be [W, H]" % label)
		elif str(entry.get("role", "")) == "shot" and int(entry["size"][0]) > 2048:
			out.append("%s: a shot plate is at most 2048 px wide" % label)
		if not entry.get("focus", []) is Array:
			out.append("%s: focus must be a list of ids" % label)
		if str(entry.get("role", "")) == "shot" and str(entry.get("mode", "")) not in CameraDirector.MODES:
			out.append("%s: mode '%s' is not a camera mode" % [label, entry.get("mode", "")])
	return out

static func _vec(value: Variant, n: int) -> bool:
	return value is Array and (value as Array).size() == n and (value as Array).all(func(x: Variant) -> bool: return x is float or x is int)

static func _basis(columns: Array) -> Basis:
	return Basis(Vector3(columns[0][0], columns[0][1], columns[0][2]), Vector3(columns[1][0], columns[1][1], columns[1][2]), Vector3(columns[2][0], columns[2][1], columns[2][2]))

static func normalise(entry: Dictionary) -> Dictionary:
	var p: Array = entry["position"]
	var size: Array = entry["size"]
	var focus: Array = []
	for id in entry.get("focus", []):
		focus.append(str(id))
	focus.sort()
	return {
		"id": str(entry["id"]), "variant": str(entry.get("variant", "")), "mode": str(entry.get("mode", "")),
		"focus": focus, "role": str(entry["role"]),
		"transform": Transform3D(_basis(entry["basis"]), Vector3(p[0], p[1], p[2])),
		"fov_v_deg": float(entry["fov_v_deg"]), "near": float(entry["near"]), "far": float(entry["far"]),
		"size": Vector2i(int(size[0]), int(size[1])), "dir": _resolve_dir(entry),
	}

static func _resolve_dir(entry: Dictionary) -> String:
	var candidates: Array[String] = []
	if entry.has("dir"):
		candidates.append(str(entry["dir"]))
	var id := str(entry.get("id", ""))
	var variant := str(entry.get("variant", ""))
	if variant.is_empty():
		candidates.append_array([id, id.replace(":", "_")])
	else:
		candidates.append_array(["%s_%s" % [id.replace(":", "_"), variant], "%s@%s" % [id, variant]])
	for dir in candidates:
		if ResourceLoader.exists(PLATE_DIR + dir + "/beauty.png"):
			return dir
	return candidates[0]

# ---- projection (the shader's, exactly) ------------------------------------------------------------

static func aspect(plate: Dictionary) -> float:
	var size: Vector2i = plate["size"]
	return float(size.x) / float(size.y)

static func tan_half_v(plate: Dictionary) -> float:
	return tan(deg_to_rad(float(plate["fov_v_deg"])) * 0.5)

# Where a world point lands in a plate: Vector3(pixel x, pixel y (0 = top row), view depth).
# A point behind the plate's camera returns a negative depth.
static func project(plate: Dictionary, world: Vector3) -> Vector3:
	var q: Vector3 = (plate["transform"] as Transform3D).affine_inverse() * world
	var z := -q.z
	if z <= 0.0:
		return Vector3(0, 0, z)
	var tv := tan_half_v(plate)
	var ndc := Vector2(q.x / (z * tv * aspect(plate)), q.y / (z * tv))
	var size: Vector2i = plate["size"]
	return Vector3((ndc.x * 0.5 + 0.5) * size.x, (0.5 - ndc.y * 0.5) * size.y, z)

# 16-bit linear depth as stored in depth.png (R high byte, G low byte).
static func decode_depth(r8: int, g8: int, near: float, far: float) -> float:
	return lerpf(near, far, float(r8 * 256 + g8) / 65535.0)

# The camera pose that reproduces a plate exactly (DioramaCamera form). `roll_deg` is added at runtime.
static func pose_of(plate: Dictionary, roll_deg: float, distance: float = 10.0) -> Dictionary:
	var xf: Transform3D = plate["transform"]
	var forward := -xf.basis.z.normalized()
	var look_at := xf.origin + forward * distance
	return {
		"look_at": look_at, "distance": distance,
		"pitch_deg": rad_to_deg(asin(clampf(-forward.y, -1.0, 1.0))),
		"yaw_deg": rad_to_deg(atan2(-forward.x, -forward.z)),
		"roll_deg": roll_deg, "fov": float(plate["fov_v_deg"]), "plate": str(plate["id"]), "plate_aspect": aspect(plate),
	}

# ---- lookup and choice ---------------------------------------------------------------------------

func base_plates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for plate in plates:
		if str(plate["variant"]).is_empty():
			out.append(plate)
	return out

func find(id: String, variant: String = "") -> Dictionary:
	for plate in plates:
		if plate["id"] == id and plate["variant"] == variant:
			return plate
	return {}

func wide() -> Dictionary:
	return find(wide_id)

# The role:"shot" plate a presentation entry asks for (mode + focus, order-insensitive), or {}.
func shot_for(mode: String, focus_ids: Array) -> Dictionary:
	var focus: Array = []
	for id in focus_ids:
		focus.append(str(id))
	focus.sort()
	for plate in base_plates():
		if plate["role"] == "shot" and plate["mode"] == mode and plate["focus"] == focus:
			return plate
	return {}

func variants() -> Array[String]:
	var out: Array[String] = []
	for plate in plates:
		if not str(plate["variant"]).is_empty() and plate["variant"] not in out:
			out.append(plate["variant"])
	return out

# True when a camera sits at a plate's centre of projection looking its way (roll does not matter).
static func is_exact(plate: Dictionary, camera_xf: Transform3D) -> bool:
	var xf: Transform3D = plate["transform"]
	return xf.origin.distance_to(camera_xf.origin) < 0.01 and xf.basis.z.normalized().dot(camera_xf.basis.z.normalized()) > 0.99995

static func _score(plate: Dictionary, camera_xf: Transform3D) -> float:
	var xf: Transform3D = plate["transform"]
	return xf.basis.z.normalized().dot(camera_xf.basis.z.normalized()) - 0.04 * xf.origin.distance_to(camera_xf.origin)

# Up to three plates for a camera: [own or closest, wide, best cover], each {"plate", "exact"}.
func choose(camera_xf: Transform3D) -> Array[Dictionary]:
	var bases := base_plates()
	var chosen: Array[Dictionary] = []
	var used := {}
	var own := {}
	for plate in bases:
		if is_exact(plate, camera_xf):
			own = plate
			break
	if own.is_empty():
		var best := -INF
		for plate in bases:
			if plate["id"] == wide_id:
				continue
			var score := _score(plate, camera_xf)
			if score > best:
				best = score
				own = plate
	if not own.is_empty():
		chosen.append({"plate": own, "exact": is_exact(own, camera_xf)})
		used[own["id"]] = true
	var wide_plate := wide()
	if not wide_plate.is_empty() and not used.has(wide_id):
		chosen.append({"plate": wide_plate, "exact": is_exact(wide_plate, camera_xf)})
		used[wide_id] = true
	var cover := {}
	var best_cover := -INF
	for role in ["cover", "shot"]:
		for plate in bases:
			if used.has(plate["id"]) or plate["role"] != role:
				continue
			var score := _score(plate, camera_xf)
			if score > best_cover:
				best_cover = score
				cover = plate
		if not cover.is_empty():
			break
	if not cover.is_empty() and chosen.size() < 3:
		chosen.append({"plate": cover, "exact": is_exact(cover, camera_xf)})
	return chosen

# ---- textures ------------------------------------------------------------------------------------

func load_textures() -> void:
	for plate in plates:
		var dir: String = PLATE_DIR + str(plate["dir"]) + "/"
		var files := {}
		var beauty_path := dir + ("beauty_m.png" if mobile and ResourceLoader.exists(dir + "beauty_m.png") else "beauty.png")
		files["beauty"] = load(beauty_path) as Texture2D if ResourceLoader.exists(beauty_path) else null
		if str(plate["variant"]).is_empty():
			var depth_image := _image(dir + "depth.png")
			if depth_image != null:
				if depth_image.get_format() != Image.FORMAT_RG8:
					depth_image.convert(Image.FORMAT_RG8)   # R and G are kept byte for byte
				files["depth_image"] = depth_image
				files["depth"] = ImageTexture.create_from_image(depth_image)
		var key_image := _half(_image(dir + "key.png"))
		files["key_image"] = key_image
		files["key"] = ImageTexture.create_from_image(key_image) if key_image != null else null
		var glow_image := _half(_image(dir + "glow.png"))
		files["glow"] = ImageTexture.create_from_image(glow_image) if glow_image != null else null
		if files["beauty"] == null or (str(plate["variant"]).is_empty() and not files.has("depth")) or files["key"] == null or files["glow"] == null:
			errors.append("plate '%s%s' is missing files in %s" % [plate["id"], "@" + str(plate["variant"]) if not str(plate["variant"]).is_empty() else "", dir])
		_textures["%s|%s" % [plate["id"], plate["variant"]]] = files
	# variants share their base plate's depth
	for plate in plates:
		if not str(plate["variant"]).is_empty():
			var base: Dictionary = _textures.get("%s|" % plate["id"], {})
			var own: Dictionary = _textures["%s|%s" % [plate["id"], plate["variant"]]]
			own["depth"] = base.get("depth")
			own["depth_image"] = base.get("depth_image")

static func _image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	var image: Image = null
	if resource is Image:
		image = (resource as Image).duplicate() as Image
	elif resource is Texture2D:
		image = (resource as Texture2D).get_image()
	if image != null and image.is_compressed():
		image.decompress()
	return image

static func _half(image: Image) -> Image:
	if image == null:
		return null
	if image.get_format() != Image.FORMAT_R8:
		image.convert(Image.FORMAT_R8)
	image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	return image

func textures(plate: Dictionary, variant: String = "") -> Dictionary:
	if not variant.is_empty():
		var own: Dictionary = _textures.get("%s|%s" % [plate["id"], variant], {})
		if not own.is_empty():
			return own
	return _textures.get("%s|" % plate["id"], {})

func has_variant(plate: Dictionary, variant: String) -> bool:
	return variant.is_empty() or _textures.has("%s|%s" % [plate["id"], variant])

# GPU bytes of every plate texture as loaded (each texture counted once).
func memory_bytes() -> int:
	var seen := {}
	var total := 0.0
	for files: Dictionary in _textures.values():
		for slot in ["beauty", "depth", "key", "glow"]:
			var texture: Texture2D = files.get(slot)
			if texture == null or seen.has(texture.get_rid()):
				continue
			seen[texture.get_rid()] = true
			total += texture_bytes(texture)
	return int(total)

static func texture_bytes(texture: Texture2D) -> float:
	var format := -1
	if texture is ImageTexture:
		format = (texture as ImageTexture).get_format()
	elif texture is CompressedTexture2D:
		# the GPU format is not exposed; the import says whether it is a VRAM (4 bpp RGB) texture
		var import_file := texture.resource_path + ".import"
		var vram := FileAccess.file_exists(import_file) and FileAccess.get_file_as_string(import_file).contains("\"vram_texture\": true")
		format = Image.FORMAT_ETC2_RGB8 if vram else Image.FORMAT_RGB8
	return float(texture.get_width() * texture.get_height()) * float(BYTES_PER_PIXEL.get(format, 4.0))

# ---- CPU light queries ---------------------------------------------------------------------------

# How much of the light at a world point comes from the sun (key.png of the wide plate, or of the
# variant), 0 where the wide camera does not see the point. Used for actors' sun shadows.
func key_at(world: Vector3, variant: String = "") -> float:
	var plate := wide()
	if plate.is_empty():
		return 0.0
	var files := textures(plate, variant)
	var depth_image: Image = files.get("depth_image")
	var key_image: Image = files.get("key_image")
	if depth_image == null or key_image == null:
		return 0.0
	var at := project(plate, world)
	var size: Vector2i = plate["size"]
	if at.z <= 0.0 or at.x < 0.0 or at.y < 0.0 or at.x >= size.x or at.y >= size.y:
		return 0.0
	var dx := clampi(int(at.x * depth_image.get_width() / size.x), 0, depth_image.get_width() - 1)
	var dy := clampi(int(at.y * depth_image.get_height() / size.y), 0, depth_image.get_height() - 1)
	var rg := depth_image.get_pixel(dx, dy)
	var stored := decode_depth(roundi(rg.r * 255.0), roundi(rg.g * 255.0), float(plate["near"]), float(plate["far"]))
	if at.z > stored + 0.35:
		return 0.0
	var kx := clampi(int(at.x * key_image.get_width() / size.x), 0, key_image.get_width() - 1)
	var ky := clampi(int(at.y * key_image.get_height() / size.y), 0, key_image.get_height() - 1)
	return key_image.get_pixel(kx, ky).r
