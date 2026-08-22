#!/usr/bin/env python3
"""Tape 回传的参考接收端(1.1, 2026-08-19)。

客户端 = view/beacon.gd(POST 纯 JSONL 包体, 元数据在 X-Sync5-* 头)。
落盘 = ./tape_inbox/<install_id>/<file>,**按 (install_id, 文件名) 去重**:
客户端 mark_sent 失败时会重传同一个文件, 重复上传必须无害(core/uplink.gd 的契约)。

用法:
    python3 tools/tapeserver.py [端口]          # 默认 8766, 明文 HTTP
生产部署放在任何能跑 python 的盒子上, 前面套 HTTPS(nginx/caddy)即可;
它没有任何依赖, 一个文件拷走就能跑。

⚠ 只收不发:响应体永远为空, 200 = 已落盘(或早已有同名文件)。
⚠ install_id == "probe" 的包直接丢弃(探针闸的服务端兜底, core/save.gd 有账)。
⚠ **没有认证与限流** —— 它是试玩期的参考端, 公网部署前套 HTTPS 反代 + 至少一个共享 token 头
(2026-08-21 审查点名);局域网/朋友试玩可以直接用。
"""
import http.server
import os
import re
import sys

# ⚠ 收件箱挂在**运行目录**下, 不是脚本目录 —— 这个文件的定位是「拷走就能跑」,
# 部署机上它不该反向往自己旁边写(第一版是脚本相对, 结果本地一测就写进了仓库根)。
ROOT = os.path.join(os.getcwd(), "tape_inbox")
SAFE = re.compile(r"^[A-Za-z0-9_.-]+$")
MAX_BODY = 8 * 1024 * 1024  # 单局日志 2000 事件封顶, 8MB 是余量很大的哨兵


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        install = self.headers.get("X-Sync5-Install", "")
        fname = self.headers.get("X-Sync5-File", "")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_response(400); self.end_headers(); return
        if install == "probe":
            self.send_response(200)  # 收到但不落盘 —— 客户端别再重试
            self.end_headers()
            return
        # 2026-08-21 审查:SAFE 放行 "." / "..", 配 os.path.join 可越出 inbox 新建文件。
        # 三道门:字符白名单 · 拒绝纯点名 · realpath 容器检查(任何一道不过都是 400)。
        if not (SAFE.match(install) and SAFE.match(fname)) or not (0 < length <= MAX_BODY) \
                or install in (".", "..") or fname in (".", "..") or not fname.endswith(".jsonl"):
            self.send_response(400)
            self.end_headers()
            return
        d = os.path.join(ROOT, install)
        path = os.path.join(d, fname)
        root_real = os.path.realpath(ROOT)
        if os.path.commonpath([root_real, os.path.realpath(path)]) != root_real:
            self.send_response(400); self.end_headers(); return
        body = self.rfile.read(length)
        os.makedirs(d, exist_ok=True)
        if not os.path.exists(path):  # 去重:同名 = 重传, 保留第一份
            with open(path, "wb") as f:
                f.write(body)
        self.send_response(200)
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[tapeserver] %s\n" % (fmt % args))


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
    os.makedirs(ROOT, exist_ok=True)
    print(f"[tapeserver] listening on :{port}, inbox = {os.path.abspath(ROOT)}")
    http.server.ThreadingHTTPServer(("", port), Handler).serve_forever()
