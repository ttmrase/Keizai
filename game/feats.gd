class_name Feats
extends RefCounted

## The things a history can be remembered for, kept across every world.
##
## A world left to itself can run a thousand years without the reader ever
## wanting anything from it. These give the reader something to want: the first
## dynasty to fall, a family that lasts five centuries, all four ruptures seen,
## a god who calls nothing down for two hundred years. Most cannot be made to
## happen — only invited, by turning the world toward them — which is the point.
##
## Only the list lives here. The oracle watches for them, because some need a
## memory of the world (how long since the last rupture, which calamities have
## been called) that belongs in the save.

const ALL := [
	{"id": "first_branch", "title": "最初の分家", "glyph": &"split",
		"text": "家が初めて割れ、分家が立つ"},
	{"id": "new_god", "title": "新しき神", "glyph": &"altar",
		"text": "原始の信仰から、新たな信仰が生まれる"},
	{"id": "dynasty", "title": "王朝交代", "glyph": &"crown",
		"text": "王家が別の家に移る"},
	{"id": "regime", "title": "政変", "glyph": &"banner",
		"text": "統治のかたちが覆る"},
	{"id": "refounding", "title": "国の興亡", "glyph": &"keep",
		"text": "国が倒れ、新たな国が興る"},
	{"id": "excommunication", "title": "破門", "glyph": &"altar",
		"text": "信仰が家を世から締め出す"},
	{"id": "assassination", "title": "暗殺", "glyph": &"candle",
		"text": "国の長が刃に倒れる"},
	{"id": "capital_seizure", "title": "王都制圧", "glyph": &"claw",
		"text": "武を持つ者が王都を押さえる"},
	{"id": "uprising", "title": "民衆蜂起", "glyph": &"unrest",
		"text": "民が立ち上がる"},
	{"id": "four_ruptures", "title": "四つの破局", "glyph": &"flame",
		"text": "どの世界ででも、四つの事件をすべて見届ける"},
	{"id": "extinction", "title": "絶えた血", "glyph": &"candle",
		"text": "貴族家が一つ絶える"},
	{"id": "centenarian", "title": "百寿", "glyph": &"sparkle",
		"text": "百歳まで生きる者が現れる"},
	{"id": "five_centuries", "title": "五百年の家", "glyph": &"keep",
		"text": "興ってから五百年続く家が現れる"},
	{"id": "millennium", "title": "千年の歴史", "glyph": &"scroll",
		"text": "一つの世界で千年を見届ける"},
	{"id": "great_population", "title": "大いなる繁栄", "glyph": &"people",
		"text": "世の人口が2万に達する"},
	{"id": "faiths_divided", "title": "割れた祈り", "glyph": &"altar",
		"text": "三つ以上の信仰が同時に地を分け合う"},
	{"id": "duke", "title": "公爵家", "glyph": &"seal",
		"text": "家格の頂、公爵に叙される家が現れる"},
	{"id": "great_house", "title": "大家族", "glyph": &"tree",
		"text": "一つの家に存命の者が25人を数える"},
	{"id": "first_prophecy", "title": "神託成就", "glyph": &"sun",
		"text": "神託を初めて成就させる"},
	{"id": "ten_prophecies", "title": "神託の主", "glyph": &"sun",
		"text": "神託を通算10度成就させる"},
	{"id": "bold_prophecy", "title": "大いなる予言", "glyph": &"sun",
		"text": "神威100以上を授かる神託を成就させる"},
	{"id": "failed_prophecy", "title": "外れた神託", "glyph": &"scroll",
		"text": "神託が外れる。神とて未来は見えない"},
	{"id": "seven_calamities", "title": "七つの災厄", "glyph": &"drought",
		"text": "一つの世界で、七つの災厄と恵みをすべて下す"},
	{"id": "wrath", "title": "怒れる神", "glyph": &"flame",
		"text": "十年のうちに四度、災厄を下す"},
	{"id": "idle_god", "title": "見守る神", "glyph": &"pause",
		"text": "二百年のあいだ何も下さず、ただ見守る"},
	{"id": "golden_peace", "title": "百年の泰平", "glyph": &"wheat",
		"text": "事件も政変も国の興亡もない百年が続く"},
	{"id": "many_worlds", "title": "幾つもの世界", "glyph": &"map",
		"text": "三つ目の世界を興す"},
]

const INCIDENT_FEATS := [&"excommunication", &"assassination", &"capital_seizure", &"uprising"]


static func find(id: String) -> Dictionary:
	for feat in ALL:
		if feat["id"] == id:
			return feat
	return {}
