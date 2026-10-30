# Serves the 3D companions for the browser playground: playground/ (index.html, sheet.js,
# record.js) over Resources/Companions3D (the page the app loads, the engine, characters, models).
# Never cached, so edits show on reload. Recorded frames (POST /frame/<reel>/<n>.jpg|png) are
# saved under build/companions-3d/<reel>/.
#   python3 companions-3d/serve.py [port]      then open http://localhost:8765/?c=spark
import http.server, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOTS = [os.path.join(HERE, "playground"), os.path.join(HERE, "..", "Resources", "Companions3D")]
# The add-on gallery's companions (D55), from a sidefolk-addons checkout beside this one ($SIDEFOLK_ADDONS_REPO).
ADDONS = os.environ.get("SIDEFOLK_ADDONS_REPO") or os.path.join(HERE, "..", "..", "sidefolk-addons")
if os.path.isdir(os.path.join(ADDONS, "companions")):
    ROOTS[1:1] = sorted(os.path.join(ADDONS, "companions", n) for n in os.listdir(os.path.join(ADDONS, "companions")))
REC = os.path.join(HERE, "..", "build", "companions-3d")

class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        rel = super().translate_path(path)[len(os.getcwd()):].lstrip("/")
        for root in ROOTS:
            full = os.path.join(root, rel)
            if os.path.exists(full): return full
        return os.path.join(ROOTS[-1], rel)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        m = re.fullmatch(r"/frame/([a-z0-9-]{1,40})/(\d{1,6})\.(jpg|png)", self.path)
        if not m:
            self.send_error(404); return
        d = os.path.join(REC, m.group(1)); os.makedirs(d, exist_ok=True)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(os.path.join(d, f"{int(m.group(2)):05d}.{m.group(3)}"), "wb") as f:
            f.write(body)
        self.send_response(204); self.end_headers()

    def log_message(self, *a):
        pass

os.chdir(HERE)
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8765), Handler).serve_forever()
