extends RefCounted

## Place-name pool for generated maps. Mixed European flavours; unique picks per seed.

const NAMES := [
	# English
	"Ashford", "Redmere", "Stonehaven", "Blackwater", "Hartfield", "Willowmere",
	"Oxenford", "Greyhaven", "Marshwick", "Thornhill", "Brightwell", "Ravenscar",
	"Coldbrook", "Westmarch", "Kingsford", "Elmstead",
	# German
	"Eisenbach", "Waldheim", "Königsfeld", "Steinburg", "Rosenheim", "Bergthal",
	"Neustadt", "Hochburg", "Falkenstein", "Grünwald", "Dornbach", "Silberbach",
	"Wolfshagen", "Klarenthal", "Mühlheim", "Aschenburg",
	# French
	"Valmont", "Rochefort", "Clairvaux", "Bellevue", "Montclair", "Beaulieu",
	"Chateauroux", "Verneuil", "Riviere", "Saint-Loup", "Boisvert", "Lyonnet",
	"Castelnau", "Fontenay", "Marignac", "Hautefort",
	# Italian
	"Monterosso", "Castelnuovo", "Bellavista", "Valdorno", "Roccaforte", "Pietralba",
	"Monteverde", "San Pietro", "Collalto", "Fiorenza", "Torrenova", "Belpasso",
	"Orvieto", "Castelforte", "Rivoli", "Montelupo",
	# Spanish
	"Valverde", "Peñaalta", "Rivera", "Villanueva", "Montealto", "San Remo",
	"Castellar", "Riodulce", "Alborada", "Piedras", "Vallehermoso", "Torreluna",
	"Fuenteclara", "Sierra Blanca", "Navahonda", "Camposeco",
	# Hungarian
	"Várhegy", "Kiskút", "Nagyfalu", "Erdővár", "Kisvárad", "Hegyköz",
	"Széphalom", "Patak", "Újhely", "Berek", "Tótvár", "Kővágó",
	"Alsómező", "Felsővár", "Zöldmező", "Sárkányvár",
	# Bohemian
	"Hradec", "Litomyšl", "Kutná", "Plzeňský", "Morava", "Vltava",
	"Karlštejn", "Tábor", "Budějovice", "Znojmo", "Olomouc", "Jihlava",
	"Pardubice", "Mělník", "Beroun", "Rakovník",
]


static func pick_names(count: int, seed_value: int) -> PackedStringArray:
	var want := maxi(0, count)
	var out: PackedStringArray = PackedStringArray()
	if want == 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else randi()
	var pool: Array = NAMES.duplicate()
	## Fisher–Yates
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in want:
		if i < pool.size():
			out.append(str(pool[i]))
		else:
			out.append("%s %d" % [str(pool[i % pool.size()]), 2 + int(i / pool.size())])
	return out
