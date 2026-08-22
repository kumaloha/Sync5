class_name Music
extends AudioStreamPlayer

## 音乐接线 v1(2026-08-18 用户:「提前接入音乐, 有现成的, 直接每关播放不同的就行」)。
## 四场地 × 变体池:每段进场挑本场地的一首 8 秒循环段(120 BPM, assets/audio)。
## v1 = 简单循环:不做拍对齐、不做换段不断鼓(那是 1.1 的账, TODO 音乐节);
## 首个瞬态按素材 README 的声明(0.000s)先信, 波形复核也归 1.1。
## ⚠ 循环点在运行时设(LOOP_FORWARD 到 8.000s), 不动 .import —— 素材是用户的地盘。
## ⚠ 探针静音:纯表现, 探针的帧预算与日志都不该为它买单(盲注特写同一条)。

## ⚑ v2(2026-08-19 晚, META 资产循环拍板「买了就想玩」):**每场馆免费第一首,
## 其余六首是「唱片」资产**(data/assets.json 的 track 出口)。v1 曾把十首全开着轮播 ——
## 现在轮播池 = 免费首曲 + 已购唱片, 买了下一次进那个场馆就轮得到新歌。
const VENUES := [
	["01_small_bar_minimal_deep_house", "02_small_bar_nu_disco_lounge"],
	["03_club_filter_house", "04_club_acid_house", "05_club_disco_house"],
	["06_theater_electro_funk_talkbox", "07_theater_synth_funk_show"],
	["08_stadium_electro_rock_anthem", "09_stadium_big_french_electro", "10_stadium_cosmic_disco_anthem"],
]

var _section := -1


func _init() -> void:
	volume_db = -8.0


## 这一段能轮到哪些曲目:免费首曲 + 这个场馆里已解锁的。**纯函数**(owned 由调用方给),
## 测试直测这一层(t_asset)—— 播放器本体 headless 测不了。
static func track_pool(section_idx: int, owned: Array) -> Array:
	var venue: Array = VENUES[clampi(section_idx, 0, VENUES.size() - 1)]
	var out: Array = [venue[0]]
	for i in range(1, venue.size()):
		if owned.has(String(venue[i])):
			out.append(String(venue[i]))
	return out


## 段首拍调(编排器)。同段重复调不重启 —— 段中商店回来还是这一首。
## 变体用普通 randi 挑:纯表现, 不碰共享种子流(与截图探针的纪律同源)。
func play_section(section_idx: int) -> void:
	if SaveState.is_probe():
		return
	if section_idx == _section and playing:
		return
	_section = section_idx
	volume_db = -8.0   # 首页点唱机把音量收小过, 进局要拉回来
	var pool := track_pool(section_idx, SaveState.owned_tracks())
	_play_loop(String(pool[randi() % pool.size()]))


## 首页点唱机(META 资产「turntable」):免费首曲 + 已购唱片攒成一张歌单, 随机放一首,
## 音量收小 —— 首页是氛围不是演出。没买点唱机时 _open_home 根本不会调到这里。
func play_home() -> void:
	if SaveState.is_probe():
		return
	var owned := SaveState.owned_tracks()
	var pool: Array = []
	for v in range(VENUES.size()):
		pool += track_pool(v, owned)
	_section = -1
	volume_db = -14.0
	_play_loop(String(pool[randi() % pool.size()]))


## 拍首下拍(编排器在**钟起步的那一刻**调):把循环拉回 0.000s 的首 kick。
## ⚑ 这就是「节奏卡到我们的秒数」的实现(用户拍板, TODO 音乐节):拍长一律偶数秒
## ⇒ 8s 拍 = 4 小节 · 6s 脸 = 3 小节 · 教学 10/12s = 5/6 小节, 任何拍都在小节边界收束;
## 真正会漂的是拍与拍**之间**(结算动画/商店/特写时长不定), 所以每拍起步归零一次,
## kick 永远落在拍首。段切换也由此不断拍:新段第一拍照样从 kick 起。
## ⚠ 中途 seek 是一次硬切, 靠首瞬态遮蔽 —— 10 首实测首 kick ≤0.4ms 且无渐入
## (2026-08-19 波形量测, 声明≠测量那条纪律), 所以不需要淡入淡出补偿。
func sync_beat() -> void:
	if playing:
		seek(0.0)


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
