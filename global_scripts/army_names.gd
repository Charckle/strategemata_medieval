extends RefCounted

## Random nicknames for mobile armies. Two templates:
##   "<Adjective> <Noun>"   e.g. Red Lance
##   "<Person>'s <Host>"    e.g. Aldric's Host

const ADJECTIVES := [
	"Red", "Black", "White", "Iron", "Steel", "Golden", "Silver", "Crimson",
	"Ashen", "Pale", "Dark", "Bright", "Broken", "Swift", "Grim", "Bold",
	"Fierce", "Silent", "Wild", "Noble", "Ragged", "Storm", "Winter", "Summer",
]

const NOUNS := [
	"Lance", "Host", "Company", "Band", "Guard", "Spears", "Wolves", "Ravens",
	"Crows", "Lions", "Hounds", "Hawks", "Blades", "Shields", "March", "Column",
	"Circle", "Order", "Knights", "Levy", "Retinue", "Companions", "Outriders", "Wardens",
]

const PERSONS := [
	# English
	"Aldric", "Godwin", "Eadric", "Wulfric", "Oswald", "Harold", "Edmund", "Cuthbert",
	# German
	"Dietrich", "Gottfried", "Hartmann", "Wolfram", "Berthold", "Siegmund", "Conrad", "Otto",
	# Italian
	"Cosimo", "Lorenzo", "Bartolo", "Niccolo", "Orlando", "Jacopo", "Marco", "Guido",
	# Spanish
	"Rodrigo", "Alvaro", "Diego", "Fernando", "Gonzalo", "Lope", "Ramiro", "Sancho",
]

const HOST_WORDS := [
	"Host", "Men", "Band", "Company", "Lance", "Guard", "Spears", "Retinue",
]

const REROLL_ATTEMPTS := 5


static func max_name_length() -> int:
	var longest := 0
	for adj in ADJECTIVES:
		for noun in NOUNS:
			longest = maxi(longest, ("%s %s" % [adj, noun]).length())
	for person in PERSONS:
		for host in HOST_WORDS:
			longest = maxi(longest, ("%s's %s" % [person, host]).length())
	# Room for uniqueness suffix " 99".
	return longest + 3


static func roll_candidate(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.5:
		var adj := str(ADJECTIVES[rng.randi() % ADJECTIVES.size()])
		var noun := str(NOUNS[rng.randi() % NOUNS.size()])
		return "%s %s" % [adj, noun]
	var person := str(PERSONS[rng.randi() % PERSONS.size()])
	var host := str(HOST_WORDS[rng.randi() % HOST_WORDS.size()])
	return "%s's %s" % [person, host]


static func mint_unique(used: Dictionary, rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var candidate := ""
	for _i in REROLL_ATTEMPTS:
		candidate = roll_candidate(rng)
		if not used.has(candidate):
			return candidate
	if candidate == "":
		candidate = roll_candidate(rng)
	return uniquify_with_suffix(candidate, used)


static func uniquify_with_suffix(base: String, used: Dictionary) -> String:
	var cleaned := sanitize(base)
	if cleaned == "":
		cleaned = "Host"
	if not used.has(cleaned):
		return cleaned
	var n := 2
	var max_len := max_name_length()
	while n < 10000:
		var with_num := "%s %d" % [cleaned, n]
		if with_num.length() > max_len:
			var room := max_len - str(n).length() - 1
			if room < 1:
				room = 1
			with_num = "%s %d" % [cleaned.substr(0, room).rstrip(" "), n]
		if not used.has(with_num):
			return with_num
		n += 1
	return "%s %d" % [cleaned.substr(0, maxi(1, max_len - 5)), n]


static func sanitize(raw: String) -> String:
	var s := raw.strip_edges()
	# Collapse internal whitespace runs.
	var parts := s.split(" ", false)
	s = " ".join(parts)
	var max_len := max_name_length()
	if s.length() > max_len:
		s = s.substr(0, max_len).strip_edges()
	return s


static func is_valid_custom(raw: String) -> bool:
	return sanitize(raw) != ""
