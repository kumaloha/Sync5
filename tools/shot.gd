class_name Shot
extends RefCounted

## 截图探针共用的骨架(2026-08-09 收口)。
##
## 8 个 `*_sheet.gd` 加 `shoot/faceshot/glass` 原本各抄一份同样的三段样板:
## ① 定画布(`set_content_scale_size` + 可选纯色底)· ② 挂 `view/phrase.tscn`
## · ③ 存图并打印 `saved _shot_X.png` 那一行。这里只收这三段 —— **排帧不收**:
## 每个探针在第几帧摆什么状态是它自己的实验设计(draft_sheet 一路交错着
## 改 run 状态和截图, home_sheet 中途换 section_idx), 拿一张表硬套只会
## 把差异挤进参数里, 比抄写更贵。
##
## 语义逐字照抄原实现:画布尺寸、底色、文件名格式、打印文本一律不变,
## 验收 = 每个探针的产物与改前目视/逐字节一致。
##
## ⚠ 截图探针要 NON-headless 跑:`godot --path . --script res://tools/xxx.gd`


## 定画布。`bg` 给 Color 就铺一块同尺寸的纯色底(不给就是透明/场景自己的底)。
static func canvas(tree: SceneTree, w: int, h: int, bg = null) -> void:
	tree.get_root().set_content_scale_size(Vector2i(w, h))
	if bg != null:
		var r := ColorRect.new()
		r.color = bg
		r.size = Vector2(w, h)
		tree.get_root().add_child(r)


## 定画布 + 挂主场景, 返回它。竖屏 720×1280 是本作唯一的分辨率。
static func stage(tree: SceneTree, w := 720, h := 1280, path := "res://view/phrase.tscn") -> Node:
	canvas(tree, w, h)
	var s: Node = load(path).instantiate()
	tree.get_root().add_child(s)
	return s


## 存图到根目录的 `_shot_<name>.png` 并打印那一行。
static func save(tree: SceneTree, name: String) -> void:
	tree.get_root().get_texture().get_image().save_png("res://_shot_%s.png" % name)
	print("saved _shot_%s.png" % name)
