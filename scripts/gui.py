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
import re
import glob
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
HOST = "127.0.0.1"

# On Windows the repo's PowerShell scripts are used; elsewhere the bash ones.
WIN = os.name == "nt"
PS = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
GIT_CMDS = {"gitstatus": ["git", "status"], "gitdiff": ["git", "diff", "--stat"]}
SAFE = re.compile(r"^[A-Za-z0-9_.$#:@-]{1,128}$")


def list_apps():
    """Every dir under apex/, with its app id from deployments/*.json."""
    apps = []
    for d in sorted(glob.glob(os.path.join(REPO, "apex", "*"))):
        if not os.path.isdir(d):
            continue
        app_id = None
        for j in sorted(glob.glob(os.path.join(d, "deployments", "*.json"))):
            try:
                m = re.search(r'"id"\s*:\s*(\d+)', open(j).read())
                if m:
                    app_id = m.group(1)
                    break
            except OSError:
                pass
        apps.append({"app": os.path.basename(d), "id": app_id})
    return apps


def default_conn():
    """The stamped connection name, read from the pull script."""
    f = os.path.join(REPO, "scripts", "pull.ps1" if WIN else "pull.sh")
    try:
        m = re.search(r'Conn\s*=\s*"([^"]+)"' if WIN
                      else r'CONN="\$\{1:-([^}"]+)\}"', open(f).read())
        return m.group(1) if m else None
    except OSError:
        return None


def build_cmd(cid, req):
    """argv for pull/validate/push, honouring an app selection. Returns
    (argv, None) or (None, error). No selection = stamped defaults."""
    app = (req.get("app") or "").strip()
    ws = (req.get("ws") or "").strip()
    if not app:  # single-app path: exactly the scripts' own defaults
        base = {"pull": "pull", "validate": "apex-validate",
                "push": "push", "push-backup": "push"}[cid]
        argv = (PS + ["scripts\\%s.ps1" % base]) if WIN \
            else ["bash", "scripts/%s.sh" % base]
        if cid == "push-backup":
            argv.append("-Backup" if WIN else "-backup")
        return argv, None
    for v in (app, ws):
        if v and not SAFE.match(v):
            return None, "invalid characters in app/workspace"
    if not os.path.isdir(os.path.join(REPO, "apex", app)):
        return None, "no such app dir: apex/" + app
    app_id = next((a["id"] for a in list_apps() if a["app"] == app), None)
    conn = default_conn()
    if cid == "validate":
        return ((PS + ["scripts\\apex-validate.ps1", "-App", app]) if WIN
                else ["bash", "scripts/apex-validate.sh", app]), None
    if not conn:
        return None, "could not read the stamped connection from the pull script"
    if not app_id:
        return None, "no app id found in apex/%s/deployments/*.json" % app
    if cid == "pull":
        return ((PS + ["scripts\\pull.ps1", "-Conn", conn,
                       "-AppId", app_id, "-App", app]) if WIN
                else ["bash", "scripts/pull.sh", conn, app_id, app]), None
    # push / push-backup
    if WIN:
        argv = PS + ["scripts\\push.ps1"]
        if cid == "push-backup":
            argv.append("-Backup")
        argv += ["-Conn", conn, "-App", app, "-AppId", app_id]
        if ws:
            argv += ["-Workspace", ws]
    else:
        argv = ["bash", "scripts/push.sh"]
        if cid == "push-backup":
            argv.append("-backup")
        argv += [conn, app, app_id]
        if ws:
            argv.append(ws)
    return argv, None

def draft_message():
    """Subject + body drafted from git status, in the repo's commit style
    (feat(p53): ... / db(mig): ... / chore(apex): ...). A draft, not a
    decision: it lands in the message box for the human to edit."""
    # -uall: list untracked FILES, not collapsed "dir/" entries
    out = subprocess.run(["git", "status", "--porcelain", "-uall"], cwd=REPO,
                         stdout=subprocess.PIPE).stdout.decode()
    pages, migs, dbf, other = [], [], [], []
    lines = [l for l in out.splitlines() if l.strip()]
    for l in lines:
        st, path = l[:2].strip() or "M", l[3:].strip().strip('"')
        m = re.search(r"apex/[^/]+/pages/p0*(\d+)(?:-([\w-]+))?\.apx$", path)
        if m:
            pages.append((st, m.group(1), m.group(2) or ""))
        elif re.search(r"db/migrations/.+\.sql$", path):
            migs.append((st, os.path.basename(path)))
        elif path.startswith("db/"):
            dbf.append((st, path))
        else:
            other.append((st, path))
    verb = {"A": "add", "M": "update", "D": "remove", "R": "rename", "??": "add"}
    if pages and not (migs or dbf):
        nums = sorted({p[1] for p in pages}, key=int)
        tag = ",".join("p" + n for n in nums[:3]) + ("..." if len(nums) > 3 else "")
        v = verb.get(pages[0][0], "update")
        slug = pages[0][2] if len(pages) == 1 else "%d pages" % len(nums)
        subject = "feat(%s): %s %s" % (tag, v, slug)
    elif migs and not pages:
        subject = "db(mig): %s %s" % (verb.get(migs[0][0], "add"),
                                      ", ".join(m[1] for m in migs[:2]))
    elif dbf and not pages:
        subject = "db: update " + ", ".join(os.path.basename(f[1]) for f in dbf[:2])
    elif lines:
        subject = "chore(apex): update %d files" % len(lines)
    else:
        return ""
    files = ["%s %s" % (verb.get(l[:2].strip() or "M", "update"), l[3:].strip())
             for l in lines[:12]]
    if len(lines) > 12:
        files.append("... and %d more" % (len(lines) - 12))
    return subject + "\n\n" + "\n".join(files)


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


# RAW string: the JS below contains \n and regex escapes that must reach
# the browser verbatim - a plain """ string turns \n into a real newline
# INSIDE a JS string literal and the whole page dies with a syntax error.
PAGE = r"""<!doctype html><meta charset="utf-8">
<title>apex-solo-starter</title>
<style>
 body{font:14px system-ui;margin:0;padding:12px;background:#111;color:#ddd}
 button{margin:2px;padding:8px 14px;font-size:14px;cursor:pointer}
 button:disabled{opacity:.35;cursor:default}
 #out{background:#000;padding:10px;height:60vh;overflow:auto;
      white-space:pre-wrap;font:12px monospace;margin-top:10px}
 #out div{min-height:1em}
 .ln{color:#9d9}.sep{color:#6cf}.err{color:#f66}.wrn{color:#fc3}.ok{color:#4f4;font-weight:bold}
 #send,#msg{width:50%%;padding:6px;font:13px monospace;background:#000;color:#ddd;border:1px solid #444}
 .warn{color:#fa0} select{font:12px monospace;width:60%%}
 #yn{display:none} #yn button{padding:4px 18px}
 small.meta{color:#888;font-weight:normal}
</style>
<h3>%(repo)s <small class=meta id=conn></small> <small class=warn id=st></small></h3>
<div id=approw hidden style="margin-bottom:6px">
 app: <select id=appsel style="width:auto"></select>
 workspace override (only if it differs): <input id=wsin size=14>
</div>
<div>
 <button class=act onclick="run('pull')">Pull</button>
 <button class=act onclick="run('validate')">Validate</button>
 <button class=act onclick="run('push')">Push</button>
 <button class=act onclick="run('push-backup')">Push + backup</button>
 <button class=act onclick="run('gitstatus')">Git status</button>
 <button class=act onclick="run('gitdiff')">Git diff</button>
 <button onclick="post('/stop',{})" style="color:#f66">Stop</button>
 <button onclick="out.innerHTML='';out.appendChild(tail)" title="clears the display only">Clear</button>
</div>
<div style="margin-top:6px">
 <select id=migs multiple size=4></select>
 <button onclick="migs()" title="re-read db/migrations (files in applied-*.txt ledgers are hidden)">&#8635;</button>
 <small class=meta id=migmeta></small><br>
 admin conn (optional): <input id=adm size=18>
 <button class=act onclick="migrate()">Run migration(s)</button>
 <button class=act onclick="refreshGrants()" title="promptless db/refresh-claude-ro-grants.sql as the admin conn">Refresh RO grants</button>
</div>
<div style="margin-top:6px">
 <input id=msg placeholder="commit message (empty = draft one for me)">
 <button onclick="draftMsg()">Draft msg</button>
 <button class=act onclick="commitpush()">Commit &amp; push to git</button>
</div>
<div id=out></div>
<div style="margin-top:6px">
 <span id=yn>answer:
  <button onclick="answer('y')" style="color:#4f4">Yes</button>
  <button onclick="answer('n')" style="color:#f66">No</button></span>
 <input id=send placeholder="reply to a prompt here (y / N / password) then Enter">
</div>
<script>
let n=0,pending='',wasRunning=false,t0=0,lastOut=Date.now();
const out=document.getElementById('out'), st=document.getElementById('st'),
      send=document.getElementById('send'), yn=document.getElementById('yn');
function cls(l){
  if(/^────/.test(l))return 'sep';
  if(/IMPORT DID NOT|error|failed|aborted|ORA-\d|PLS-\d/i.test(l))return 'err';
  if(/warning|STOP:|NOTE:/i.test(l))return 'wrn';
  if(/successful|^Imported\.|no Builder changes|passed/i.test(l))return 'ok';
  return 'ln';}
function addLine(l){const d=document.createElement('div');
  d.className=cls(l);d.textContent=l;out.insertBefore(d,tail);}
const tail=document.createElement('div');tail.className='ln';out.appendChild(tail);
function feed(text){
  pending+=text;const parts=pending.split('\n');pending=parts.pop();
  parts.forEach(addLine);tail.textContent=pending;}
async function post(u,b){const r=await fetch(u,{method:'POST',
  headers:{'Content-Type':'application/json'},body:JSON.stringify(b)});
  return r.json();}
function appsel(){const e=document.getElementById('appsel');
  return e&&!e.parentElement.hidden?e.value:'';}
async function run(id){
  const b={id};
  if(['pull','validate','push','push-backup'].includes(id)){
    b.app=appsel();b.ws=document.getElementById('wsin').value;}
  const r=await post('/run',b);if(!r.ok)alert(r.err);}
async function migrate(){
  const files=[...document.getElementById('migs').selectedOptions].map(o=>o.value);
  if(!files.length){alert('pick migration file(s) first');return;}
  const r=await post('/run',{id:'migrate',files,admin:document.getElementById('adm').value});
  if(!r.ok)alert(r.err);}
async function draftMsg(){
  const r=await (await fetch('/draft')).json();
  const msg=document.getElementById('msg');
  if(!r.msg){st.textContent='nothing to commit';return false;}
  msg.value=r.msg.split('\n')[0];msg.title=r.msg;msg.focus();
  st.textContent='message drafted - edit if needed, then Commit & push';
  return true;}
async function commitpush(){
  const m=document.getElementById('msg').value.trim();
  if(!m){await draftMsg();return;}   // first click drafts, second commits
  const full=document.getElementById('msg').title||'';
  const body=(full&&full.split('\n')[0]===m)?full:m; // keep drafted body if subject untouched
  const r=await post('/run',{id:'commitpush',msg:body});if(!r.ok)alert(r.err);}
async function refreshGrants(){
  const r=await post('/run',{id:'refresh-grants',admin:adm.value});
  if(!r.ok)alert(r.err);}
async function answer(a){await post('/send',{line:a});}
// remember the admin conn across reloads (localhost page, harmless value)
const adm=document.getElementById('adm');
try{adm.value=localStorage.getItem('adm')||'';}catch(e){}
adm.addEventListener('change',()=>{try{localStorage.setItem('adm',adm.value);}catch(e){}});
send.addEventListener('keydown',async e=>{
  if(e.key==='Enter'){await post('/send',{line:send.value});send.value='';}});
function elapsed(){const s=Math.floor((Date.now()-t0)/1000);
  return Math.floor(s/60)+':'+String(s%%60).padStart(2,'0');}
async function tick(){
  const r=await (await fetch('/out?since='+n)).json();
  if(r.next<n){n=0;out.innerHTML='';out.appendChild(tail);pending='';}
  if(r.chunks.length){
    const nearBottom=out.scrollHeight-out.scrollTop-out.clientHeight<48;
    feed(r.chunks.join(''));n=r.next;
    if(nearBottom)out.scrollTop=out.scrollHeight;}
  if(wasRunning&&!r.running)migs();
  if(!wasRunning&&r.running)t0=Date.now();
  wasRunning=r.running;
  const lastBits=(out.lastChild&&out.lastChild.previousSibling?
    out.lastChild.previousSibling.textContent:'')+' '+pending;
  const waiting=r.running&&/\[y\/N\]\s*$/i.test(lastBits.slice(-80));
  yn.style.display=waiting?'inline':'none';
  send.style.outline=waiting?'2px solid #fa0':'';
  if(waiting&&document.activeElement!==send)send.focus();
  send.placeholder=waiting?'the script is waiting - answer here (y / N) then Enter'
    :'reply to a prompt here (y / N / password) then Enter';
  document.querySelectorAll('button.act').forEach(b=>b.disabled=r.running);
  if(r.chunks.length)lastOut=Date.now();
  // always show the clock while a script runs, plus silence since the last
  // output - a long quiet validate and a stuck prompt must look different
  const quiet=Math.floor((Date.now()-lastOut)/1000);
  const clock=r.running?('  '+elapsed()+(quiet>=15?'  (no output for '+quiet+'s)':'')):'';
  st.textContent=(waiting?'waiting for your answer below'
    :r.running?('running: '+r.label)
    :(r.exit===null?'idle':(r.exit===0?'done (ok)':'done (EXIT '+r.exit+')')))+clock;
  setTimeout(tick,500);}
async function migs(){const r=await (await fetch('/migrations')).json();
  const s=document.getElementById('migs');s.innerHTML='';
  r.files.forEach(f=>{const o=document.createElement('option');
    o.value=o.textContent=f;s.appendChild(o);});
  document.getElementById('migmeta').textContent=
    r.applied?r.applied+' already applied (hidden)':'';}
async function apps(){const r=await (await fetch('/apps')).json();
  if(r.conn)document.getElementById('conn').textContent='conn: '+r.conn;
  if(r.apps.length<2)return;
  const row=document.getElementById('approw'),sel=document.getElementById('appsel');
  sel.innerHTML='';
  r.apps.forEach(a=>{const o=document.createElement('option');
    o.value=a.app;o.textContent=a.app+(a.id?' (app '+a.id+')':' (no id!)');
    sel.appendChild(o);});
  row.hidden=false;}
apps();migs();tick();
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
        elif self.path.startswith("/draft"):
            self._json({"msg": draft_message()})
        elif self.path.startswith("/apps"):
            self._json({"apps": list_apps(), "conn": default_conn()})
        elif self.path.startswith("/migrations"):
            applied = set()
            for led in glob.glob(os.path.join(REPO, "db/migrations/applied-*.txt")):
                try:
                    applied.update(x.strip() for x in open(led))
                except OSError:
                    pass
            files = sorted(os.path.basename(f) for f in
                           glob.glob(os.path.join(REPO, "db/migrations/*.sql"))
                           if os.path.basename(f) not in applied)
            self._json({"files": files, "applied": len(applied)})
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
            if cid in GIT_CMDS:
                ok = start(GIT_CMDS[cid], cid)
            elif cid in ("pull", "validate", "push", "push-backup"):
                argv, err = build_cmd(cid, req)
                if err:
                    return self._json({"ok": False, "err": err})
                label = cid + (" " + req.get("app") if req.get("app") else "")
                ok = start(argv, label)
            elif cid == "refresh-grants":
                admin = (req.get("admin") or "").strip()
                if not admin or not SAFE.match(admin):
                    return self._json({"ok": False,
                        "err": "enter the admin connection name first"})
                argv = (PS + ["scripts\\refresh-ro-grants.ps1", "-Admin", admin]) \
                    if WIN else ["bash", "scripts/refresh-ro-grants.sh", admin]
                ok = start(argv, "refresh RO grants")
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
                line = req.get("line", "")
                p.stdin.write((line + "\n").encode())
                p.stdin.flush()
                # echo it like a terminal would (password-style prompts excepted),
                # so the output no longer ends in "[y/N]" and the status moves on
                with lock:
                    state["chunks"].append(("*" * len(line) if len(line) > 3 else line) + "\n")
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


class Server(ThreadingHTTPServer):
    # HTTPServer sets SO_REUSEADDR, which on WINDOWS lets a second process
    # bind the same port too: two launchers answer one URL at random, each
    # with its own "one run at a time" guard - so two pushes could overlap.
    allow_reuse_address = (os.name != "nt")

    def server_bind(self):
        if os.name == "nt":  # refuse to share the port with anything
            import socket
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def repo_lock():
    """One launcher per repo, whatever the port. An OS file lock: released
    automatically when the process exits or crashes - no stale lock files."""
    os.makedirs(os.path.join(REPO, "tmp"), exist_ok=True)
    f = open(os.path.join(REPO, "tmp", ".gui.lock"), "a+")
    try:
        if os.name == "nt":
            import msvcrt
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        f.seek(0)
        other = f.read().strip() or "another port"
        sys.exit("A launcher for this repo is already running (%s). "
                 "Use that browser tab, or stop it with Ctrl+C first." % other)
    f.seek(0); f.truncate(); f.write("http://%s:%d" % (HOST, PORT)); f.flush()
    return f  # keep the handle open: closing it releases the lock


if __name__ == "__main__":
    _lock = repo_lock()
    try:
        srv = Server((HOST, PORT), H)
    except OSError:
        sys.exit("Port %d is in use - probably a launcher for ANOTHER repo. "
                 "Start this one on a different port:  python3 scripts/gui.py %d"
                 % (PORT, PORT + 1))
    print("apex-solo-starter launcher on http://%s:%d  (repo: %s)" % (HOST, PORT, REPO))
    print("HUMAN-ONLY. Ctrl+C stops it. See the file header before tunneling.")
    srv.serve_forever()
