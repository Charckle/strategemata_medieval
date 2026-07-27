extends RefCounted
class_name JoustBracket

## Knockout bracket. Knights are Dictionaries; matches are Dictionaries.


static func next_power_of_two(n: int) -> int:
	if n <= 1:
		return 2
	var p := 1
	while p < n:
		p *= 2
	return p


static func round_name(total_rounds: int, round_idx: int) -> String:
	var remaining := total_rounds - round_idx
	match remaining:
		1:
			return "FINAL"
		2:
			return "SEMI-FINAL"
		3:
			return "QUARTER-FINAL"
	return "ROUND %d" % (round_idx + 1)


static func total_rounds_for(count: int) -> int:
	var n := count
	var c := 0
	while n > 1:
		n = n / 2
		c += 1
	return c


static func build(knights: Array) -> Dictionary:
	var n := knights.size()
	if n < 2 or (n & (n - 1)) != 0:
		push_error("JoustBracket.build: need power-of-2 knights, got %d" % n)
		return {}
	var shuffled := knights.duplicate()
	shuffled.shuffle()
	var first_round: Array = []
	for i in range(0, shuffled.size(), 2):
		first_round.append({
			"knight_a": shuffled[i],
			"knight_b": shuffled[i + 1],
			"round_number": 0,
			"match_number": i / 2,
			"winner": null,
			"loser": null,
			"finished": false,
		})
	return {
		"knights": shuffled,
		"rounds": [first_round],
		"current_round": 0,
		"total_rounds": total_rounds_for(n),
	}


static func advance(bracket: Dictionary) -> bool:
	## Returns true if a new round was created; false if champion decided.
	var rounds: Array = bracket.get("rounds", [])
	var cur := int(bracket.get("current_round", 0))
	if cur < 0 or cur >= rounds.size():
		return false
	var current_matches: Array = rounds[cur]
	var winners: Array = []
	for m in current_matches:
		if m == null or not (m is Dictionary) or m.get("winner") == null:
			return false
		winners.append(m["winner"])
	if winners.size() == 1:
		return false
	var next_round: Array = []
	var next_idx := cur + 1
	for i in range(0, winners.size(), 2):
		next_round.append({
			"knight_a": winners[i],
			"knight_b": winners[i + 1],
			"round_number": next_idx,
			"match_number": i / 2,
			"winner": null,
			"loser": null,
			"finished": false,
		})
	rounds.append(next_round)
	bracket["rounds"] = rounds
	bracket["current_round"] = next_idx
	return true


static func champion(bracket: Dictionary):
	var rounds: Array = bracket.get("rounds", [])
	if rounds.is_empty():
		return null
	var final_round: Array = rounds[rounds.size() - 1]
	if final_round.size() == 1 and final_round[0] is Dictionary:
		return final_round[0].get("winner", null)
	return null
