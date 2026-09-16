#!/usr/bin/env python3
"""HUMAN-ONLY web launcher for the workflow scripts.

Run from anywhere in the project:   python3 scripts/gui.py
then open the printed URL. Stdlib only - no installs.

It is a launcher, not a reimplementation: every button runs the same
script you would type (pull.sh, push.sh, migrate.sh...), streams its
output to the page, and forwards what you type into the input line to
the script's stdin - so the push drift prompt works as documented.
The server only runs commands from the fixed table below; the page
cannot ask it to run anything else.

Binds to 127.0.0.1 by default. If you expose it (e.g. a Cloudflare
tunnel: `cloudflared tunnel --url http://localhost:8765`), anyone who
reaches the URL can PUSH YOUR APP - put access control (Cloudflare
Access) in front, never a bare public tunnel.
"""
import json
import os
import glob
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
HOST = "127.0.0.1"

# The whole attack/typo surface: ids the page may run, nothing else.
# On Windows the repo's PowerShell scripts are used; elsewhere the bash ones.
WIN = os.name == "nt"
PS = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
COMMANDS = {
    "pull":        PS + [r"scripts\pull.ps1"]           if WIN else ["bash", "scripts/pull.sh"],
    "validate":    PS + [r"scripts\apex-validate.ps1"]  if WIN else ["bash", "scripts/apex-validate.sh"],
    "push":        PS + [r"scripts\push.ps1"]           if WIN else ["bash", "scripts/push.sh"],
    "push-backup": PS + [r"scripts\push.ps1", "-Backup"] if WIN else ["bash", "scripts/push.sh", "-backup"],
    "gitstatus":   ["git", "status"],
    "gitdiff":     ["git", "diff", "--stat"],
    # "migrate" and "commitpush" build their argv below, with checks
}

state = {"proc": None, "chunks": [], "exit": None, "label": ""}
lock = threading.Lock()


def reader(proc):
    # bufsize=0 + os.read: return whatever bytes are available NOW.
    # A buffered read(256) would wait for a full 256 bytes, holding short
    # output (exactly the [y/N] prompts) invisible until the process died.
    while True:
        chunk = os.read(proc.stdout.fileno(), 4096)
        if not chunk:
            break
        with lock:
            state["chunks"].append(chunk.decode("utf-8", "replace"))
    proc.wait()
    with lock:
        state["exit"] = proc.returncode
        state["proc"] = None


def start(argv, label):
    with lock:
        if state["proc"] is not None:
            return False
        # APPEND-ONLY: the page remembers how many chunks it has read, so
        # resetting this list here would strand every open page at an index
        # past the end - output would look frozen until a full reload.
        state["chunks"].append("\n──────── $ " + " ".join(argv) + "\n")
        state["exit"] = None
        state["label"] = label
        state["proc"] = subprocess.Popen(
            argv, cwd=REPO, stdin=subprocess.PIPE, bufsize=0,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    threading.Thread(target=reader, args=(state["proc"],), daemon=True).start()
    return True


PAGE = """<!doctype html><meta charset="utf-8">
<title>apex-solo-starter</title>
<style>
 body{font:14px system-ui;margin:0;padding:12px;background:#111;color:#ddd}
 button{margin:2px;padding:8px 14px;font-size:14px;cursor:pointer}
 #out{background:#000;color:#0f0;padding:10px;height:60vh;overflow:auto;
      white-space:pre-wrap;font:12px monospace;margin-top:10px}
 #send,#msg{width:50%%;padding:6px;font:13px monospace}
 .warn{color:#fa0} select{font:12px monospace;width:60%%}
</style>
<h3>%(repo)s <small class=warn id=st></small></h3>
<div>
 <button onclick="run('pull')">Pull</button>
 <button onclick="run('validate')">Validate</button>
 <button onclick="run('push')">Push</button>
 <button onclick="run('push-backup')">Push + backup</button>
 <button onclick="run('gitstatus')">Git status</button>
 <button onclick="run('gitdiff')">Git diff</button>
 <button onclick="post('/stop',{})" style="color:#f66">Stop</button>
</div>
<div style="margin-top:6px">
 <select id=migs multiple size=4></select>
 <button onclick="migs()" title="re-read db/migrations">&#8635;</button><br>
 admin conn (optional): <input id=adm size=18>
 <button onclick="migrate()">Run migration(s)</button>
</div>
<div style="margin-top:6px">
 <input id=msg placeholder="commit message">
 <button onclick="commitpush()">Commit &amp; push to git</button>
</div>
<div id=out></div>
<div style="margin-top:6px">
 <input id=send placeholder="reply to a prompt here (y / N / password) then Enter">
</div>
<script>
let n=0;
const out=document.getElementById('out'), st=document.getElementById('st'),
      send=document.getElementById('send');
async function post(u,b){const r=await fetch(u,{method:'POST',
  headers:{'Content-Type':'application/json'},body:JSON.stringify(b)});
  return r.json();}
async function run(id){const r=await post('/run',{id});if(!r.ok)alert(r.err);}
async function migrate(){
  const files=[...document.getElementById('migs').selectedOptions].map(o=>o.value);
  if(!files.length){alert('pick migration file(s) first');return;}
  const r=await post('/run',{id:'migrate',files,admin:document.getElementById('adm').value});
  if(!r.ok)alert(r.err);}
async function commitpush(){
  const m=document.getElementById('msg').value.trim();
  if(!m){alert('commit message first');return;}
  const r=await post('/run',{id:'commitpush',msg:m});if(!r.ok)alert(r.err);}
document.getElementById('send').addEventListener('keydown',async e=>{
  if(e.key==='Enter'){await post('/send',{line:e.target.value});e.target.value='';}});
let wasRunning=false;
async function tick(){
  const r=await (await fetch('/out?since='+n)).json();
  if(r.next<n){n=0;out.textContent='';}   // server restarted: start over
  if(r.chunks.length){out.textContent+=r.chunks.join('');n=r.next;
    out.scrollTop=out.scrollHeight;}
  if(wasRunning&&!r.running)migs();       // a run just finished: new files?
  wasRunning=r.running;
  // a trailing question means the script is blocked on the input line below
  const waiting=r.running&&/\[y\/N\]\s*$/i.test(out.textContent.slice(-80));
  send.style.outline=waiting?'2px solid #fa0':'';
  send.placeholder=waiting?'the script is waiting - answer here (y / N) then Enter'
    :'reply to a prompt here (y / N / password) then Enter';
  st.textContent=waiting?'waiting for your answer below'
    :r.running?('running: '+r.label)
    :(r.exit===null?'idle':(r.exit===0?'done (ok)':'done (EXIT '+r.exit+')'));
  setTimeout(tick,500);}
async function migs(){const r=await (await fetch('/migrations')).json();
  const s=document.getElementById('migs');s.innerHTML='';
  r.files.forEach(f=>{const o=document.createElement('option');
    o.value=o.textContent=f;s.appendChild(o);});}
migs();tick();
</script>"""


class H(BaseHTTPRequestHandler):
    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/out"):
            since = int(self.path.split("since=")[-1]) if "since=" in self.path else 0
            with lock:
                self._json({"chunks": state["chunks"][since:],
                            "next": len(state["chunks"]),
                            "running": state["proc"] is not None,
                            "exit": state["exit"], "label": state["label"]})
        elif self.path.startswith("/migrations"):
            files = sorted(os.path.basename(f) for f in
                           glob.glob(os.path.join(REPO, "db/migrations/*.sql")))
            self._json({"files": files})
        else:
            body = (PAGE % {"repo": os.path.basename(REPO)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"] or 0)) or "{}")
        if self.path == "/run":
            cid = req.get("id", "")
            if cid in COMMANDS:
                ok = start(COMMANDS[cid], cid)
            elif cid == "migrate":
                files, bad = [], []
                for f in req.get("files", []):
                    p = os.path.join("db/migrations", os.path.basename(f))
                    (files if os.path.isfile(os.path.join(REPO, p)) else bad).append(p)
                if bad or not files:
                    return self._json({"ok": False, "err": "bad file selection"})
                admin = req.get("admin", "").strip()
                if WIN:
                    argv = PS + [r"scripts\migrate.ps1", "-File", ",".join(files)]
                    if admin:
                        argv += ["-Admin", admin]
                else:
                    argv = ["bash", "scripts/migrate.sh"] + files
                    if admin:
                        argv.append(admin)
                ok = start(argv, "migrate")
            elif cid == "commitpush":
                msg = req.get("msg", "").strip()
                if not msg:
                    return self._json({"ok": False, "err": "empty message"})
                def seq():  # three plain git calls, shell-free on any OS
                    for argv in (["git", "add", "-A"],
                                 ["git", "commit", "-m", msg],
                                 ["git", "push"]):
                        with lock:
                            state["chunks"].append("$ " + " ".join(argv) + "\n")
                        r = subprocess.run(argv, cwd=REPO, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT)
                        with lock:
                            state["chunks"].append(r.stdout.decode("utf-8", "replace"))
                        if r.returncode != 0:
                            break
                    with lock:
                        state["exit"] = r.returncode
                        state["proc"] = None
                with lock:
                    if state["proc"] is not None:
                        return self._json({"ok": False, "err": "something is already running"})
                    state["chunks"].append("\n──────── commit + push\n")
                    state["exit"] = None
                    state["label"] = "commit+push"
                    state["proc"] = True  # marks busy; seq() clears it
                threading.Thread(target=seq, daemon=True).start()
                ok = True
            else:
                return self._json({"ok": False, "err": "unknown command"})
            self._json({"ok": ok, "err": None if ok else "something is already running"})
        elif self.path == "/send":
            with lock:
                p = state["proc"]
            if p and p.stdin:
                p.stdin.write((req.get("line", "") + "\n").encode())
                p.stdin.flush()
            self._json({"ok": True})
        elif self.path == "/stop":
            with lock:
                p = state["proc"]
            if p:
                p.terminate()
            self._json({"ok": True})
        else:
            self._json({"ok": False, "err": "?"}, 404)

    def log_message(self, *a):  # quiet
        pass


if __name__ == "__main__":
    print("apex-solo-starter launcher on http://%s:%d  (repo: %s)" % (HOST, PORT, REPO))
    print("HUMAN-ONLY. Ctrl+C stops it. See the file header before tunneling.")
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()
