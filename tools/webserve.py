#!/usr/bin/env python3
"""网页版本地 HTTPS 服务(2026-08-12:手机浏览器强升 https,纯 http 打不开)。

    python3 tools/webserve.py [端口=8765]

- 服务 build/web(先跑 Web 导出);
- 证书自签,缺了就用 openssl 现生成(SAN 带本机局域网 IP + 127.0.0.1),
  存 build/cert/(build/ 不入库,证书不会被提交);
- 手机首次访问会提示"连接不是私密的" —— Safari:显示详细信息→访问此网站;
  Chrome:高级→继续前往。点过一次就记住了。
- 换了 WiFi/IP 后删掉 build/cert/ 重跑(SAN 里的 IP 变了)。
"""
import http.server
import os
import socket
import ssl
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, 'build', 'web')
CERTDIR = os.path.join(ROOT, 'build', 'cert')
CRT = os.path.join(CERTDIR, 'server.crt')
KEY = os.path.join(CERTDIR, 'server.key')


def lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))          # 不真发包,只为拿路由源地址
        return s.getsockname()[0]
    except OSError:
        return '127.0.0.1'
    finally:
        s.close()


def ensure_cert(ip: str) -> None:
    if os.path.exists(CRT) and os.path.exists(KEY):
        return
    os.makedirs(CERTDIR, exist_ok=True)
    subprocess.run([
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
        '-keyout', KEY, '-out', CRT, '-days', '825', '-nodes',
        '-subj', '/CN=Sync5 LAN',
        '-addext', 'subjectAltName=IP:%s,IP:127.0.0.1,DNS:localhost' % ip,
    ], check=True, capture_output=True)
    print('自签证书已生成 → %s' % CERTDIR)


class NoCacheHandler(NoCacheHandler):
    """禁缓存(2026-08-18):一天十个包的迭代节奏下, 手机浏览器按启发式缓存 88MB 的
    pck 会连续给用户端上陈旧版本 ——「改了但手机上变化不大」的头号嫌疑。
    no-cache = 每次都回源验证(有 Last-Modified, 未变仍 304, 流量不吃亏)。"""

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache, must-revalidate')
        super().end_headers()


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    if not os.path.exists(os.path.join(WEB, 'index.html')):
        sys.exit('缺 build/web/index.html —— 先跑 Web 导出(见 STATUS.md 增量快照)')
    ip = lan_ip()
    ensure_cert(ip)
    os.chdir(WEB)
    httpd = http.server.ThreadingHTTPServer(('0.0.0.0', port),
        NoCacheHandler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CRT, KEY)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    print('https://%s:%d  (手机同 WiFi 直开;首次点"继续访问")' % (ip, port))
    httpd.serve_forever()


if __name__ == '__main__':
    main()
