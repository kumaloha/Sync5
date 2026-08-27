class_name Music
extends AudioStreamPlayer

## 音乐接线 v1(2026-08-18 用户:「提前接入音乐, 有现成的, 直接每关播放不同的就行」)。
## 四场地 × 变体池:每段进场挑本场地的一首 8 秒循环段(120 BPM, assets/audio)。
## v1 = 简单循环:不做拍对齐、不做换段不断鼓(那是 1.1 的账, TODO 音乐节);
## 首个瞬态按素材 README 的声明(0.000s)先信, 波形复核也归 1.1。
## ⚠ 循环点在运行时设(LOOP_FORWARD 到 8.000s), 不动 .import —— 素材是用户的地盘。
## ⚠ 探针静音:纯表现, 探针的帧预算与日志都不该为它买单(盲注特写同一条)。

## ⚑ 2026-08-24 局外 build 删除:「唱片」资产连同曲池收口一起退役, 十首全开轮播
## (回到 v1 的口径 —— 曲目是内容, 不再是商品)。
const VENUES := [
	["01_small_bar_minimal_deep_house", "02_small_bar_nu_disco_lounge"],
	["03_club_filter_house", "04_club_acid_house", "05_club_disco_house"],
	["06_theater_electro_funk_talkbox", "07_theater_synth_funk_show"],
	["08_stadium_electro_rock_anthem", "09_stadium_big_french_electro", "10_stadium_cosmic_disco_anthem"],
]

var _run_track := ""


func _init() -> void:
	volume_db = -8.0


## 全部曲目(2026-08-25 用户:「一局的音乐不要换来换去, 不同局可以换」——
## 一局开局抽一首用到底, 局间随机换;08-17「四段四场馆」的换曲弧作废, 场馆分组仅存档案)。
static func track_pool() -> Array:
	var out: Array = []
	for v in VENUES:
		out += v
	return out


## 新的一局:清掉本局曲目, 下一次 play_section 重抽(编排器在开局三步旁边调)。
func new_run() -> void:
	_run_track = ""


## 段首拍调(编排器)。一局一首:同一局里重复调**不换曲不重启**(段中商店/段切换回来
## 还是这一首);变体用普通 randi 挑 —— 纯表现, 不碰共享种子流(截图探针纪律同源)。
func play_section(_section_idx: int) -> void:
	if SaveState.is_probe():
		return
	if _run_track != "" and playing:
		return
	if _run_track == "":
		var pool := track_pool()
		_run_track = String(pool[randi() % pool.size()])
	volume_db = -8.0
	_play_loop(_run_track)


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


## 回首页:停 —— 首页静音是现状。⚠ 不清 _run_track:回首页 ≠ 新局
## (新局的清曲在 new_run, 由开局三步旁边调)。
func stop_music() -> void:
	stop()


## 结算音效(2026-08-25 用户放入 assets/defeat.mp3 / victory.mp3):一次性短音,
## 不循环不走拍对齐;mp3 的编码延迟对 one-shot 无所谓(循环才忌讳)。
## 打断循环曲直接播;下一局 play_section 会自己把音量与曲目复位。探针静音同纪律。
func play_jingle(win: bool) -> void:
	if SaveState.is_probe():
		return
	var path := "res://assets/victory.mp3" if win else "res://assets/defeat.mp3"
	if not ResourceLoader.exists(path):
		return
	stop()
	_phase_loop = false   # jingle 不是 8s 循环, 别被相位回绕截断
	var st = load(path)
	if st is AudioStreamMP3:
		st.loop = false
	stream = st
	volume_db = -6.0
	play()


func _play_loop(track: String) -> void:
	# ⚑ 2026-08-24 wav→ogg(用户批, 包 −13MB):优先 ogg;wav 兜底只为导入空窗/回滚期,
	# 二者时长都是样本级 8.0000s, 循环语义一致。
	var st = null
	if ResourceLoader.exists("res://assets/audio/%s.ogg" % track):
		st = load("res://assets/audio/%s.ogg" % track)
	elif ResourceLoader.exists("res://assets/audio/%s.wav" % track):
		st = load("res://assets/audio/%s.wav" % track)
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		# ⚠⚠ 不用流自带 loop(2026-08-27 真人报「尾巴到开头没咬住」):vorbis 编码
		# 结构性垫料(实测 afinfo:352800 有效 + 128 priming + 416 尾垫 = 353344 帧)
		# 让自然循环周期变 8.0123s, 每圈漂 12ms。改由 _process 按**相位**精确回绕
		# (素材尾→头是连续设计, 8.000s 整点 seek 无爆音);loop 仍开着当兜底
		# (万一某帧没赶上, 宁可 12ms 缝也不要静音)。
		st.loop = true
		st.loop_offset = 0.0
		_phase_loop = true
	elif st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.mix_rate * 8.0)
		stream = st
	play()


## ogg 相位回绕(见上):每帧盯播放头, 过 8.000s 就精确扣回一个周期。
## WAV 路径不需要(loop_end 是样本级精确的), _phase_loop 只在 ogg 路径置位。
const LOOP_LEN := 8.0
var _phase_loop := false

func _process(_delta: float) -> void:
	if not _phase_loop or not playing:
		return
	var pos := get_playback_position()
	if pos >= LOOP_LEN:
		seek(pos - LOOP_LEN)
