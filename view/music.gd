class_name Music
extends AudioStreamPlayer

## 音乐接线 v1(2026-08-18 用户:「提前接入音乐, 有现成的, 直接每关播放不同的就行」)。
## 四场地 × 变体池:每段进场挑本场地的一首 8 秒循环段(120 BPM, assets/audio)。
## v1 = 简单循环:不做拍对齐、不做换段不断鼓(那是 1.1 的账, TODO 音乐节);
## 首个瞬态按素材 README 的声明(0.000s)先信, 波形复核也归 1.1。
## ⚠ 循环点在运行时设(LOOP_FORWARD 到 8.000s), 不动 .import —— 素材是用户的地盘。
## ⚠ 探针静音:纯表现, 探针的帧预算与日志都不该为它买单(盲注特写同一条)。

const VENUES := [
	["01_small_bar_minimal_deep_house", "02_small_bar_nu_disco_lounge"],
	["03_club_filter_house", "04_club_acid_house", "05_club_disco_house"],
	["06_theater_electro_funk_talkbox", "07_theater_synth_funk_show"],
	["08_stadium_electro_rock_anthem", "09_stadium_big_french_electro", "10_stadium_cosmic_disco_anthem"],
]

var _section := -1


func _init() -> void:
	volume_db = -8.0


## 段首拍调(编排器)。同段重复调不重启 —— 段中商店回来还是这一首。
## 变体用普通 randi 挑:纯表现, 不碰共享种子流(与截图探针的纪律同源)。
func play_section(section_idx: int) -> void:
	if SaveState.is_probe():
		return
	if section_idx == _section and playing:
		return
	_section = section_idx
	var pool: Array = VENUES[clampi(section_idx, 0, VENUES.size() - 1)]
	_play_loop(String(pool[randi() % pool.size()]))


## 回首页:停 —— 首页静音是现状(首页音景是 1.1 商业化之后的口味题)。
func stop_music() -> void:
	stop()
	_section = -1


func _play_loop(track: String) -> void:
	var st = load("res://assets/audio/%s.wav" % track)
	if st == null:
		return
	if st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.mix_rate * 8.0)
	stream = st
	play()
