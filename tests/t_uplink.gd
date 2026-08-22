extends RefCounted

# --- 回传簿记(core/uplink.gd)+ 配置校验 ---
#
# ⚠ 不测 view/beacon.gd 的网络:headless 没有端点, 测出来的只会是超时。
# Beacon 刻意薄(队列 + 一个 HTTPRequest), 厚的簿记全在 Uplink 静态函数里, 这里直测。
# 目录用 user://tape_test_uplink, 测完清掉 —— 绝不碰真的 tape/(真人日志无价)。

const TDIR := "user://tape_test_uplink"


func run(t) -> void:
	# ---- 配置面:缺省关;开着但没 url 是测试期红灯 ----
	t.check(not Uplink.enabled(), "upload ships OFF until the user deploys an endpoint")
	t.eq(DB.validate_tape({"enabled": true, "to_file": true, "dir": "user://tape",
		"max_events": 100, "mute": [],
		"upload": {"enabled": true, "url": ""}}) != "", true,
		"enabled without url is a validation error (silent no-op family)")
	t.eq(DB.validate_tape({"enabled": true, "to_file": true, "dir": "user://tape",
		"max_events": 100, "mute": [],
		"upload": {"enabled": false, "url": "", "batch_max": 3, "retry_seconds": 30.0}}), "",
		"the shipped shape validates clean")
	t.eq(DB.validate_tape({"enabled": true, "to_file": true, "dir": "user://tape",
		"max_events": 100, "mute": [],
		"upload": {"enabled": true, "url": "ftp://x"}}) != "", true,
		"non-http(s) url is rejected")

	# ---- 簿记面:pending 排除在写的那局 · mark_sent 搬进 sent/ 不删 ----
	var real_dir: String = Tape.dir
	Tape.dir = TDIR
	DirAccess.make_dir_recursive_absolute(TDIR)
	for name in ["run_20260819a.jsonl", "run_20260819b.jsonl", "run_20260819c.jsonl"]:
		var f := FileAccess.open(TDIR + "/" + name, FileAccess.WRITE)
		f.store_line("{\"e\":\"run\"}")
		f.close()
	var pend := Uplink.pending(TDIR + "/run_20260819c.jsonl")
	t.eq(pend.size(), 2, "active run's file is excluded from pending")
	t.eq(String(pend[0]), "run_20260819a.jsonl", "oldest first (timestamped names sort)")
	t.check(Uplink.mark_sent("run_20260819a.jsonl"), "mark_sent moves the file")
	t.check(FileAccess.file_exists(TDIR + "/sent/run_20260819a.jsonl"),
		"sent file is kept under sent/, not deleted (local analysis still owns it)")
	t.check(not FileAccess.file_exists(TDIR + "/run_20260819a.jsonl"),
		"moved out of the pending scan")
	t.eq(Uplink.pending(TDIR + "/run_20260819c.jsonl").size(), 1, "pending shrinks after send")
	t.check(Uplink.read_file("run_20260819b.jsonl").size() > 0, "read_file returns the body")

	# ---- 元数据面:头齐全, 探针的 install_id 恒 probe(服务端兜底过滤靠它)----
	var heads := Uplink.headers("run_x.jsonl")
	t.eq(heads.size(), 5, "five metadata headers")
	t.check(String(heads[1]).begins_with("X-Sync5-Install: probe"),
		"probes stamp install_id=probe (server-side fallback filter)")
	t.eq(SaveState.install_id(), "probe", "probe never mints a real install id")

	# ---- 清场:只删自己建的测试目录 ----
	var d := DirAccess.open(TDIR)
	if d != null:
		for f2 in d.get_files():
			d.remove(String(f2))
		if DirAccess.open(TDIR + "/sent") != null:
			for f3 in DirAccess.open(TDIR + "/sent").get_files():
				DirAccess.open(TDIR + "/sent").remove(String(f3))
			d.remove("sent")
	DirAccess.open("user://").remove(TDIR.get_file())
	Tape.dir = real_dir
