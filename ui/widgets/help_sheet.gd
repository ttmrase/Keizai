class_name HelpSheet
extends RefCounted

## 「この画面の読み方」— what the open screen is showing and how to work it.
##
## Every screen here is dense on purpose: it is a window onto a society, and a
## society is a lot. What was missing was a legend. This is one per screen, in
## the same place on all of them, plus the three-step loop the whole game turns
## on — so that "what am I looking at?" and "what do I do?" each have an answer
## one tap away.

const LOOP := [
	{"glyph": &"sparkle", "title": "① 未来を告げる",
		"text": "「神の力」で神託を下す。「この家が王座に就く」「このギルドが天下を取る」——世界が自分で決めることを、先に言い当てる。"},
	{"glyph": &"sun", "title": "② 世を傾ける",
		"text": "神が触れられるのは鉱石・木材・収穫・魔物の四つの理と、七つの災厄と恵みだけ。それで人の世を告げた未来へ傾ける。"},
	{"glyph": &"scroll", "title": "③ 見届ける",
		"text": "時を進め、地図と年代記で成り行きを追う。当たれば神威が満ち、もっと大きく世を揺らせるようになる。"},
]

## What is on every screen, whichever is open.
const ALWAYS := [
	{"glyph": &"sparkle", "title": "✦ の数字と三つの点",
		"text": "神威（災厄を下す力）と、いま告げている神託の数。タップすると神の力へ。"},
	{"glyph": &"play", "title": "時の速さ",
		"text": "止める・一倍・二倍・四倍。大事件が起きると時は自動で止まる（設定で切れる）。"},
	{"glyph": &"wheat", "title": "五つの棒",
		"text": "魔物・不満・収穫・鉱石・木材のいまの水準。矢印は増えているか減っているか。"},
	{"glyph": &"scroll", "title": "下の一行",
		"text": "いちばん新しい出来事。タップするとその出来事の主役へ飛ぶ。"},
	{"glyph": &"flame", "title": "タブの印",
		"text": "「事件」の赤い印は破局が近いしるし。「神の力」の金の印は、まだ未来を告げていないしるし。"},
]

const PAGES := {
	"map": {"title": "世界の読み方", "rows": [
		{"glyph": &"map", "title": "色分け",
			"text": "上のボタンで、土地を何で塗り分けるかを選ぶ。支配家・信仰・国・不満・産業。同じ色は同じ家（信仰・国）。"},
		{"glyph": &"keep", "title": "城と旗",
			"text": "城の大きさは人口。旗と盾はその地を治める家の紋章。冠が載っているのが王都。"},
		{"glyph": &"flame", "title": "炎と枯れ木",
			"text": "炎は不満が高い町、枯れ木は飢えている町。放っておくと蜂起や政変の火種になる。"},
		{"glyph": &"sparkle", "title": "光る輪",
			"text": "神託で名指しした家の領地。告げた未来の主役がどこにいるかの目印。"},
		{"glyph": &"swords", "title": "剣と赤い道",
			"text": "交差した剣は近ごろ戦いのあった町。赤い破線の道は戦の前線、紫の破線は国と国の境。国が割れると王都の冠も二つになる。"},
		{"glyph": &"unrest", "title": "兆しの帯",
			"text": "地図の上の一行は、いま起きそうなこと。タップするとそれを見られる画面へ飛ぶ。"},
		{"glyph": &"play", "title": "操作",
			"text": "ドラッグで移動、ピンチで拡大。町をタップすると詳細が開き、地名も改められる。"},
	]},
	"chronicle": {"title": "年代記の読み方", "rows": [
		{"glyph": &"scroll", "title": "一行と札",
			"text": "出生・婚姻・死没は印つきの一行。分家・政変・事件のような転機は色つきの札で目立たせてある。"},
		{"glyph": &"tree", "title": "名前を追う",
			"text": "人や家の名が出てくる記事はタップできる。その人・その家の系譜が開く。"},
		{"glyph": &"banner", "title": "絞り込み",
			"text": "上のボタンで種類を絞る。「家・氏で絞る」は一つの家、または一つの氏（建国の家から出たすべての家）の記事だけを追う。側近家の出来事は数が多いので別枠。"},
		{"glyph": &"crown", "title": "時代",
			"text": "「時代」は五十年ごとの章。その半世紀が何の時代だったかに名前が付き、要点がまとめられる。"},
	]},
	"lineage": {"title": "系譜の読み方", "rows": [
		{"glyph": &"tree", "title": "四つの図",
			"text": "「組織」はギルド・派閥・国・信仰の分かれ方。「家」は貴族家の分家図。「人物」は血のつながり。どれも最初のひとつまで辿れる。「偉人」は後の世に名を残した者の殿堂。"},
		{"glyph": &"laurel", "title": "偉人",
			"text": "統治・武・信仰・富と技・変革・家門の六つの分野。長く治めた・組織で活躍した、くらいでは載らない。多くは死後、成したことが続いたと分かってから列せられる。札の月桂冠が印。タップでその人の系図へ。"},
		{"glyph": &"seal", "title": "色と紋",
			"text": "札の左端の色は生まれた家。同じ模様の紋章は同じ氏の家。冠の印はいま役職にある人。"},
		{"glyph": &"keep", "title": "氏（うじ）",
			"text": "建国の家々だけが氏を興す。その後に生まれた家はみな分かれ元の氏を名乗り、「ネシ氏コド家」「ネシ氏コド・名」と書かれる。宗家（氏を興した家）の者だけが「ネシ・名」。札では氏が名前の前に小さく出る。「家」の「氏」ボタンで一つの氏だけを描ける。"},
		{"glyph": &"people", "title": "長押し",
			"text": "人物を長押しすると、その人の直系ときょうだいだけの系図が開く。「源流へ」で一番上の祖へ飛ぶ。"},
		{"glyph": &"bars", "title": "家格の根拠",
			"text": "家を選ぶと、その家格が何でできているかが一覧で出る：現任の要職、歴任（摂政 三代 など）、家職、跡目家の順位、外戚、武功、氏の長者、所領、家の古さ、叙勲、そして汚点。合計が家格を決める。"},
		{"glyph": &"split", "title": "分かれた理由",
			"text": "家を選ぶと、なぜ本家から分かれたのかが当時の言葉で出る。「この家の家系図」でその家だけの図へ。"},
	]},
	"relations": {"title": "関係の読み方", "rows": [
		{"glyph": &"web", "title": "家と家の線",
			"text": "緑の線は友好、赤の線は反目。婚姻・信仰・争いの積み重ねで変わっていく。"},
		{"glyph": &"keep", "title": "大きな円と小さな円",
			"text": "大きな円は貴族家、そのまわりの小さな円は仕える側近家。側近家からの線の色は忠誠の厚さ。"},
		{"glyph": &"dagger", "title": "紫の破線（遺恨）",
			"text": "恨む家から恨まれる家へ、矢じり付きの破線。太いほど深い。家督争い・継承争いに敗れた、跡目の順位を越された、戦後に所領を与えられた、政争で陥れられた——原因の出来事ごとに生まれ、数十年かけて薄れる（当主が替わると少し薄れる）。家を選ぶと「遺恨：誰に・なぜ・いつから」が出る。"},
		{"glyph": &"play", "title": "操作",
			"text": "家をタップすると、その家の縁だけが明るくなる。ドラッグで移動、ピンチで拡大。"},
	]},
	"incidents": {"title": "事件の読み方", "rows": [
		{"glyph": &"swords", "title": "戦",
			"text": "体制が倒れるとき、旧体制を支える地方が多ければ（あるいは力ずくの交代なら）国は割れて内戦になる。棒は戦況（中央の線が開戦時）、その下に両陣営の力の内訳・疲弊・最近の戦い。終われば勝者が家・ギルド・信仰を裁く。"},
		{"glyph": &"dagger", "title": "政争",
			"text": "宮廷で家が家を陥れる、武力によらない争い。多くは遺恨から（とくに家督・継承争いの）。仕掛け→工作→決着と数季〜数年かけて進み、家格・役職・長との近さ・味方・議席・信仰・富・気質・評判・体制の性格・運で決まる。内訳は仕掛けた側から見た数字。負けた側は左遷（役職を解かれる）や降格（家職・跡目の順位・叙勲を失い、汚点が残る）、重ければ当主が隠居。露見すれば仕掛けた側が罰を受ける。どの結果でも遺恨は深まる。"},
		{"glyph": &"unrest", "title": "兆し",
			"text": "いま世界で起きそうなことの一覧。差し迫ったものほど上。タップするとそれを見られる画面へ飛ぶ。「国が割れかねない」は、いま体制が倒れれば内戦になるというしるし。"},
		{"glyph": &"flame", "title": "四つの破局",
			"text": "破門・暗殺・王都制圧・民衆蜂起。めったに起きないが、起きると世界が塗り替わる。棒は機運、その下は「まだ足りないもの」。"},
		{"glyph": &"sun", "title": "神の出番",
			"text": "足りないものを理と災厄で満たしてやれば、破局は近づく。逆に遠ざけることもできる。戦も同じ：飢え・魔物・鉱石は、どちらの陣営が何でできているかによって効き方が違う。"},
	]},
	"power": {"title": "勢力の読み方", "rows": [
		{"glyph": &"crown", "title": "いちばん上の札",
			"text": "いまの国のかたち。誰が長で、議場をどの派閥が占め、誰が体制に迫っているか。"},
		{"glyph": &"bars", "title": "順位と棒",
			"text": "力の強い順。棒の長さが力、折れ線はここ数十年の推移、▲▼は直近十年の伸び。"},
		{"glyph": &"sparkle", "title": "✦の印",
			"text": "神託で名指しした組織。"},
		{"glyph": &"seal", "title": "要職",
			"text": "国の札に、長以外の座（摂政・財務官・元帥・執政補佐・聖職顧問、戦時は総大将と参謀）と跡目家の順位が出る。座ごとに就ける家格の下限があり、同じ家から三代続けば家職（世襲）になる。摂政が家職になれば摂関政治。王家が絶えると跡目家が順位どおりに継ぐ。"},
		{"glyph": &"play", "title": "タップ",
			"text": "行を開くと「なぜ強いのか」の内訳が出る。そこに並ぶ理（鉱石・魔物…）が、神の動かせるところ。"},
	]},
	"god": {"title": "神の力の使い方", "rows": [
		{"glyph": &"sparkle", "title": "神託",
			"text": "三つの未来から一つを選んで告げる。★が多いほど難しく、当たったときの神威も大きい。外れても失うものはない。同時に三つまで。"},
		{"glyph": &"sun", "title": "世界の理",
			"text": "四つのつまみを左右になぞる。それぞれの下に「上げると／下げると力を増す組織」が出る。"},
		{"glyph": &"flame", "title": "災厄と恵み",
			"text": "二度押すと下る。世界全体に及び、神威を費やす。神威は年に少しずつ、神託が当たると大きく満ちる。"},
		{"glyph": &"scroll", "title": "史録",
			"text": "これまでに見届けた出来事の記録。どの世界で見たものも残る。"},
	]},
}


static func open(host: Control, tab: String, margins: Vector4 = Vector4.ZERO) -> Sheet:
	var page: Dictionary = PAGES.get(tab, PAGES["map"])
	var sheet := Sheet.open(host, page["title"], "", margins)
	for row in page["rows"]:
		sheet.body.add_child(_row(row, Palette.ACCENT))
	sheet.body.add_child(_heading("いつも出ているもの"))
	for row in ALWAYS:
		sheet.body.add_child(_row(row, Palette.TEXT_MUTED))
	sheet.body.add_child(_heading("この遊びの流れ"))
	for row in LOOP:
		sheet.body.add_child(_row(row, Palette.TEXT_MUTED))
	return sheet


static func _heading(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap)
	var rule := ColorRect.new()
	rule.color = Color(Palette.ACCENT, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Palette.ACCENT)
	box.add_child(label)
	return box


static func _row(entry: Dictionary, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := GlyphIcon.make(entry["glyph"], colour, 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.custom_minimum_size = Vector2(30, 34)
	row.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 1)
	row.add_child(words)
	var title := Label.new()
	title.text = entry["title"]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Palette.TEXT)
	words.add_child(title)
	var text := Label.new()
	text.text = entry["text"]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	words.add_child(text)
	return row
