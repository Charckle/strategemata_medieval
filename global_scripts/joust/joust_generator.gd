extends RefCounted
class_name JoustGenerator

const KNIGHT_FIRST_NAMES := [
	"Aldric", "Baldwin", "Conrad", "Dietrich", "Edmund", "Fulk",
	"Godfrey", "Heinrich", "Ivo", "Joscelin", "Konrad", "Lambert",
	"Manfred", "Norbert", "Oswald", "Percival", "Raimund", "Siegfried",
	"Tancred", "Ulrich", "Volkmar", "Wulfric", "Roderick", "Gunther",
	"Lothar", "Bertrand", "Cedric", "Drogo", "Eustace", "Florian",
	"Gerold", "Hartmut", "Ingram", "Jasper", "Karel", "Ludovic",
]

const KNIGHT_EPITHETS := [
	"the Bold", "the Brave", "the Just", "the Stern", "the Fierce",
	"the Quiet", "the Red", "the Black", "the Fair", "the Grim",
	"the Young", "the Old", "the Swift", "the Strong", "the Wise",
	"the Unbowed", "the Ironclad", "the Relentless", "the Scarred",
	"the Pious", "the Unyielding",
]

const FALLBACK_ORIGINS := [
	"Ashburn", "Blackmoor", "Crossford", "Dunhaven", "Elmcrest",
	"Fernhollow", "Greystone", "Hawkridge", "Ironvale", "Kingsbridge",
	"Longbarrow", "Millhaven", "Northgate", "Oakshield", "Ravensfield",
	"Stonewall", "Thornbury", "Whitecliff", "Wyverncrest", "Goldhill",
]

const HORSE_NAMES := [
	"Thunder", "Shadow", "Storm", "Ember", "Frost", "Blaze",
	"Midnight", "Phantom", "Ironhoof", "Tempest", "Dustdevil",
	"Charger", "Warhammer", "Avalanche", "Brimstone", "Cobalt",
	"Fury", "Ghost", "Havoc", "Rampart", "Sentinel", "Titan",
	"Vanguard", "Windrunner", "Ashfall", "Bramble", "Copper",
	"Dagger", "Eclipse", "Flint", "Granite", "Horizon",
]

const HORSE_COLORS := [
	"grey", "black", "bay", "chestnut", "white", "roan",
	"dappled", "palomino", "sorrel", "dun", "piebald",
]

const LANCE_MATERIALS := ["ash", "pine", "oak"]

static var _used_names: Dictionary = {}


static func reset_name_pool() -> void:
	_used_names.clear()


## Fresh entropy each call (same pattern as Heraldry.random_heraldry / merchants).
static func _rng(rng: RandomNumberGenerator = null) -> RandomNumberGenerator:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	return r


static func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]


static func _stat(rng: RandomNumberGenerator, low: int = 3, high: int = 9) -> int:
	var roll := rng.randi_range(1, 5) + rng.randi_range(1, 5)
	return clampi(roll, low, high)


static func generate_horse(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _rng(rng)
	var name := str(_pick(r, HORSE_NAMES))
	var color := str(_pick(r, HORSE_COLORS))
	var sex := "stallion" if r.randf() > 0.3 else "mare"
	var stamina := _stat(r, 3, 9)
	return {
		"name": "%s the %s %s" % [name, color, sex],
		"speed": _stat(r, 3, 9),
		"steadiness": _stat(r, 3, 9),
		"stamina": stamina,
		"temperament": r.randi() % 4,
		"current_stamina": float(stamina),
	}


static func _armor_piece(rng: RandomNumberGenerator, base_protection: int, w_lo: float, w_hi: float) -> Dictionary:
	return {
		"protection": clampi(base_protection + rng.randi_range(-2, 2), 1, 10),
		"quality": _stat(rng, 3, 9),
		"weight": snappedf(rng.randf_range(w_lo, w_hi), 0.1),
	}


static func generate_armor(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _rng(rng)
	return {
		"helm": _armor_piece(r, 6, 3.0, 6.0),
		"pauldrons": _armor_piece(r, 5, 2.0, 5.0),
		"breastplate": _armor_piece(r, 7, 5.0, 10.0),
		"shield": {
			"protection": _stat(r, 4, 9),
			"quality": _stat(r, 3, 9),
			"weight": snappedf(r.randf_range(3.0, 7.0), 0.1),
		},
	}


static func generate_lance(lance_type: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _rng(rng)
	return {
		"lance_type": lance_type,
		"quality": _stat(r, 3, 8),
		"material": str(_pick(r, LANCE_MATERIALS)),
		"broken": false,
	}


static func generate_knight_name(origin: String = "", rng: RandomNumberGenerator = null) -> String:
	var r := _rng(rng)
	for _i in 100:
		var first := str(_pick(r, KNIGHT_FIRST_NAMES))
		var name: String
		if r.randf() < 0.3:
			name = "Sir %s %s" % [first, _pick(r, KNIGHT_EPITHETS)]
		else:
			var org := origin
			if org == "":
				org = str(_pick(r, FALLBACK_ORIGINS))
			name = "Sir %s of %s" % [first, org]
		if not _used_names.has(name):
			_used_names[name] = true
			return name
	return "Sir %s of %s" % [
		_pick(r, KNIGHT_FIRST_NAMES),
		_pick(r, FALLBACK_ORIGINS),
	]


static func generate_knight(
	lance_type: int,
	name: String = "",
	province_name: String = "",
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var r := _rng(rng)
	if name == "":
		name = generate_knight_name(province_name, r)
	return {
		"name": name,
		"province_name": province_name,
		"strength": _stat(r, 3, 9),
		"skill": _stat(r, 3, 9),
		"endurance": _stat(r, 3, 9),
		"courage": _stat(r, 3, 9),
		"personality": r.randi() % 4,
		"horse": generate_horse(r),
		"armor": generate_armor(r),
		"lance": generate_lance(lance_type, r),
		"injuries": [],
		"score": 0,
		"disqualified": false,
		"withdrawn": false,
	}


static func mark_name_used(name: String) -> void:
	if name != "":
		_used_names[name] = true


static func generate_npc_from_provinces(
	lance_type: int,
	province_names: Array,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var r := _rng(rng)
	var pname := ""
	if not province_names.is_empty():
		pname = str(_pick(r, province_names))
	return generate_knight(lance_type, "", pname, r)
