class_name NameGenerator
extends RefCounted

## Procedural names for people and places. Every draw comes from a named RNG
## stream so a given world seed always produces the same cast of characters.

const _HEAD := ["ア", "エ", "オ", "カ", "ケ", "コ", "サ", "セ", "ソ", "タ", "テ", "ト",
	"ナ", "ネ", "ノ", "ハ", "ヘ", "ホ", "マ", "メ", "モ", "ラ", "レ", "ロ",
	"ヴァ", "グ", "ジ", "ダ", "バ", "ザ", "イ", "ウ", "ク", "シ", "ヒ", "ミ"]

const _MID := ["ル", "ラ", "リ", "レ", "ロ", "ン", "ド", "ダ", "ディ", "ミ", "マ", "ム",
	"ナ", "ニ", "ヌ", "シ", "ス", "セ", "ティ", "ト", "ヴィ", "ガ", "ギ", "グ",
	"ベ", "ボ", "ザ", "ジ", "ズ", "デ"]

const _TAIL_F := ["ア", "イ", "ナ", "ネ", "リア", "ミ", "ラ", "ーヌ", "エル", "シア", "ーナ", "ヤ"]
const _TAIL_M := ["ス", "ド", "ン", "ク", "ル", "オ", "ム", "ウス", "イン", "アル", "ガ", "ズ"]

const _PLACE_SUFFIX := ["丘", "谷", "川", "港", "塞", "野", "森", "峠", "湖", "岬", "泉", "門"]


static func given_name(sex: String) -> String:
	var rng := RngService.stream(&"naming")
	var name: String = _HEAD[rng.randi_range(0, _HEAD.size() - 1)]
	if rng.randf() < 0.65:
		name += _MID[rng.randi_range(0, _MID.size() - 1)]
	var tail := _TAIL_F if sex == "f" else _TAIL_M
	name += tail[rng.randi_range(0, tail.size() - 1)]
	return name


static func family_stem() -> String:
	var rng := RngService.stream(&"naming")
	var stem: String = _HEAD[rng.randi_range(0, _HEAD.size() - 1)]
	stem += _MID[rng.randi_range(0, _MID.size() - 1)]
	if rng.randf() < 0.5:
		stem += _MID[rng.randi_range(0, _MID.size() - 1)]
	return stem


static func house_name() -> String:
	return family_stem() + "家"


static func place_name() -> String:
	var rng := RngService.stream(&"naming")
	var stem: String = _HEAD[rng.randi_range(0, _HEAD.size() - 1)] + _MID[rng.randi_range(0, _MID.size() - 1)]
	return stem + _PLACE_SUFFIX[rng.randi_range(0, _PLACE_SUFFIX.size() - 1)]
