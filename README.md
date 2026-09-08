# Keizai

Androidで動く、ファンタジー世界の文明を**観察する**ゲーム。

プレイヤーは神として、鉱石・木材・収穫・魔物という4つのダイヤルと、干魃や疫病といった災厄を操るだけ。誰が王になるか、どの組織が興り、いつ袂を分かつかには一切触れられない。それでも人類の側は、環境の変化に応じて権力の均衡を組み替え、必要に迫られて**新しい仕組みを自ら発明していく**。その様子を年代記と系譜図で追いかけるのがこのゲームです。

世界に最初から在るのは、ギルド・家・派閥・政体がそれぞれ1つずつ、計4つの組織だけ。討伐ギルドも、商業ギルドも、魔術師ギルドも、神殿派閥も農民派閥も、**世界がそれを必要としたときに、既存の組織から分派して生まれます**。だからどれだけ枝分かれしても、すべての組織は必ず最初の1つまで遡れます。人物も同様に、必ず始祖まで家系を辿れます。

## 画面

| 画面 | 内容 |
|---|---|
| 世界 | 集落の地図。人口・不満・支配者を一望し、タップで詳細 |
| 年代記 | 起きたことの記録。分派／継承／人物／災厄で絞り込める |
| 系譜 | 組織の分派図と人物の家系図。検索・折りたたみ・「源流へ」で辿る |
| 勢力 | 影響力の順位。開くと「なぜ強いのか」の内訳が出る |
| 神の力 | 4つのダイヤルと7つの災厄・恵み。プレイヤーにできるのはこれだけ |

## 設計

詳細は [`docs/DESIGN.md`](docs/DESIGN.md)。要点だけ:

- **系譜の追跡可能性** — 組織の設立・分派・継承はすべて `HistoryLog.record()` を通り、そこから `GameState.apply()` が状態を書き換える。他の経路から書き換えることはできないので、年代記と系譜が食い違うことがない。系譜に不可欠な出来事は圧縮されない永続領域に残る。
- **権力の算出はデータ駆動** — 「魔物が多いと討伐ギルドが強くなる」は特別扱いではなく、`data/power_profiles/*.tres` が宣言した世界変数の重み付けの一例。新しい組織の類型を足すのに、エンジン側のコード変更は要らない。
- **政治体制は生成される** — 固定パターンから選ぶのではなく、権力基盤×意思決定構造の離散2軸と、世界の状況に応じて漂流する連続5軸から組み立て、そこから体制名と説明文を生成する。ギルドや派閥の思想も同じ仕組み。
- **神の権限の境界** — `GodPowerAPI` には組織も人物も権力値も渡せない。この境界はテストで機械的に検証している。

## 開発

Godot **4.7** 以上（`Dictionary[K,V]` の型付き構文を使うため 4.4 が下限）。

```bash
# エディタで開く
godot --path .

# ヘッドレスのテスト（約3分、22,000件の検証）
godot --headless --path . res://tests/TestRunner.tscn

# 数百年ぶんを一気に回して結果を眺める開発用ツール
godot --headless --path . res://tools/Diagnose.tscn -- --ticks=2400 --seed=7

# 各画面のスクリーンショット（要 xvfb）
xvfb-run -a --server-args="-screen 0 720x1280x24" \
  godot --path . res://tools/Screenshot.tscn -- --out=/tmp/shots
```

テストには系譜の不変条件が含まれます。2万ティック回した世界に対して、すべての組織が種別ごとにただ1つの根へ到達すること、循環がないこと、すべての人物の家系が始祖で終わること、セーブが完全に往復すること、同じシードが同じ歴史を生むことを検証しています。

## Android APK のビルド

必要なもの:

- Godot 4.7 本体と、**同じバージョンの** Android エクスポートテンプレート（エディタの *Editor → Manage Export Templates* から導入）
- JDK 17 以上
- Android SDK の build-tools（`apksigner`, `zipalign`, `aapt2`）と platform-tools（`adb`）
- Godot のエディタ設定で `export/android/android_sdk_path` と `java_sdk_path` を上記に向ける

```bash
# デバッグ版（Godot が自動生成するデバッグ鍵で署名される）
godot --headless --path . --export-debug "Android" build/keizai-debug.apk

# リリース版 — 鍵はリポジトリに置かず環境変数で渡す
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/secure/path/keizai-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=keizai
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
godot --headless --path . --export-release "Android" build/keizai-release.apk
```

リリース鍵は `keytool -genkeypair -v -keystore keizai-release.keystore -alias keizai -keyalg RSA -keysize 2048 -validity 10000` で作成し、**リポジトリの外に置いて必ずバックアップ**してください。これを失うと同じ Play Store の掲載を更新できなくなります。

ビルド結果の実測値:

- 最小 SDK 24（Android 7.0）／ターゲット SDK 36（Android 16）
- arm64-v8a のみ（32bit を含めると 59MB になるため既定では外しています。必要なら `export_presets.cfg` の `architectures/armeabi-v7a` を `true` に）
- 権限要求は**ゼロ**（通信・位置情報・カメラのいずれも使いません）
- デバッグ 32MB／リリース 30MB

**ターゲット SDK は提出時に Google Play の当時の要件を確認してください。** この要件は毎年上がります。

### 未検証の項目

このリポジトリの APK はコンテナ内でビルド・署名検証まで確認済みですが、**実機での起動確認は行っていません**（実行環境に Android 端末もエミュレータもないため）。実機で確かめるべきは、タップ操作の感触、ピンチ操作、長時間放置後の復帰、セーブの読み込み時間です。
