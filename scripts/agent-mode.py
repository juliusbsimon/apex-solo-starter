#!/usr/bin/env python3
"""HUMAN-ONLY switch for agent mode: lets the agent pull, push, update from
the template (and, if you name it, run migrations) through
scripts/agent-run.sh while you are away from the keyboard.

Two ways to switch it, both human-only:

  1. In the Claude Code chat (works from your phone): start a message with
         agent mode on                  8 hours, pull + push + update
         agent mode on 4h pull push     pick the time and what is allowed
         agent mode on 12h all          all = pull push update migrate
         agent mode off
         agent mode status
     A short lead-in is fine ("ok agent mode on", "yes, agent mode off");
     a sentence that only mentions agent mode does nothing.
     The rest of the message (after the first line) still goes to the agent,
     so "agent mode on 4h" + newline + "pull, fix page 10, push" works.
     The UserPromptSubmit hook in .claude/settings.json runs this file with
     --hook. That hook fires only for prompts YOU submit - never for tool
     output, files or web pages the agent reads - which is what keeps an
     injected instruction from switching the mode on.

  2. In a terminal:  python3 scripts/agent-mode.py on 8h pull push
                     python3 scripts/agent-mode.py off | status

The switch is a token file, tmp/.agent-mode (gitignored, local to this
checkout): one key=value per line, read by agent-run.sh on every call.
Time limit: default 8h, max 24h; renew from the chat at any time.
Scopes: pull, push, update (default set) and migrate (only when named).
Promotion to TEST/PROD is never part of agent mode.

The agent is denied any command naming this file or the token
(.claude/settings.json). That is a guardrail against mistakes and injected
instructions, not a sandbox: the agent runs as your OS user.
"""
import datetime as dt
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOKEN = os.path.join(REPO, "tmp", ".agent-mode")
DEFAULT_SCOPES = ["pull", "push", "update"]
ALL_SCOPES = ["pull", "push", "update", "migrate"]
DEFAULT_HOURS = 8
MAX_HOURS = 24
# a short lead-in is fine: "ok agent mode on", "yes, agent mode off"
LEAD_IN = r"(?:(?:ok(?:ay)?|yes|yep|sure|please|pls|now)\b[\s,.!:;-]*)*"
CHAT_RE = re.compile(r"^\s*" + LEAD_IN + r"agent[- ]mode\s+(on|off|status)\b(.*)$", re.I)


def read_token():
    """dict of the token's keys, or None when there is no token."""
    try:
        with open(TOKEN, encoding="utf-8") as f:
            return dict(l.rstrip("\n").split("=", 1) for l in f if "=" in l)
    except OSError:
        return None


def state():
    """('on', token) | ('expired', token) | ('off', None)."""
    t = read_token()
    if not t:
        return "off", None
    try:
        exp = int(t.get("expires", "0"))
    except ValueError:
        exp = 0
    return ("on" if dt.datetime.now().timestamp() < exp else "expired"), t


def fmt_time(epoch):
    return dt.datetime.fromtimestamp(int(epoch)).strftime("%a %H:%M")


def describe():
    s, t = state()
    if s == "on":
        left = int(t["expires"]) - int(dt.datetime.now().timestamp())
        h, m = divmod(left // 60, 60)
        return ("Agent mode is ON: %s allowed until %s (%dh%02dm left), switched on from %s."
                % (", ".join(t.get("scopes", "").split()), fmt_time(t["expires"]), h, m,
                   t.get("by", "?")))
    if s == "expired":
        return "Agent mode EXPIRED at %s (it is off)." % fmt_time(t.get("expires", 0))
    return "Agent mode is OFF."


def parse_on_args(words):
    """['4h','pull','push'] -> (hours, scopes) or raise ValueError."""
    hours, scopes = DEFAULT_HOURS, []
    for w in words:
        w = w.strip().lower().strip(",.;")
        if not w:
            continue
        m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins)?", w)
        if m:
            n = float(m.group(1))
            hours = n / 60 if (m.group(2) or "h").startswith("m") else n
        elif w == "all":
            scopes = list(ALL_SCOPES)
        elif w in ALL_SCOPES:
            scopes.append(w)
        elif w in ("for", "and", "with", "to", "+", "please", "pls", "thanks", "now"):
            continue
        else:
            raise ValueError("unknown word '%s' (allowed: a duration like 4h, %s, all)"
                             % (w, ", ".join(ALL_SCOPES)))
    if not 0 < hours <= MAX_HOURS:
        raise ValueError("duration must be more than 0 and at most %dh" % MAX_HOURS)
    scopes = [s for s in ALL_SCOPES if s in (scopes or DEFAULT_SCOPES)]
    return hours, scopes


def switch_on(words, by):
    hours, scopes = parse_on_args(words)
    now = dt.datetime.now()
    exp = int((now + dt.timedelta(hours=hours)).timestamp())
    os.makedirs(os.path.dirname(TOKEN), exist_ok=True)
    with open(TOKEN, "w", encoding="utf-8") as f:
        f.write("expires=%d\nscopes=%s\nby=%s\nstarted=%s\n"
                % (exp, " ".join(scopes), by, now.isoformat(timespec="minutes")))
    return describe()


def switch_off():
    try:
        os.remove(TOKEN)
    except FileNotFoundError:
        pass
    return "Agent mode is OFF."


def hook():
    """Claude Code hook (UserPromptSubmit and SessionStart). Never fails the
    prompt: any error just means no extra context."""
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    event = data.get("hook_event_name", "")
    prompt = data.get("prompt") or ""
    out = {}
    ctx = ""
    m = CHAT_RE.match(prompt.splitlines()[0]) if (event == "UserPromptSubmit" and prompt) else None
    if m:
        verb, rest = m.group(1).lower(), m.group(2)
        try:
            if verb == "on":
                msg = switch_on(rest.split(), "chat")
            elif verb == "off":
                msg = switch_off()
            else:
                msg = describe()
        except ValueError as e:
            msg = "Agent mode NOT changed: %s. %s" % (e, describe())
        out["systemMessage"] = msg
        ctx = ("The human just typed an agent mode command. Result: %s "
               "Acknowledge it in one line, then do anything else the message asks. "
               "Follow the 'Agent mode' section of CLAUDE.md." % msg)
    else:
        s, t = state()
        if s == "on":
            ctx = describe() + " Use scripts/agent-run.sh as described in CLAUDE.md 'Agent mode'."
        elif s == "expired":
            ctx = describe() + " Pushes, pulls and updates are human-only again."
            switch_off()  # say it once, then forget the token
    if ctx:
        out["hookSpecificOutput"] = {"hookEventName": event, "additionalContext": ctx}
    if out:
        print(json.dumps(out))
    return 0


def main(argv):
    if argv[:1] == ["--hook"]:
        try:
            return hook()
        except Exception:  # a broken hook must never block the human's prompt
            return 0
    verb = (argv[:1] or ["status"])[0].lower()
    try:
        if verb == "on":
            print(switch_on(argv[1:], "terminal"))
        elif verb == "off":
            print(switch_off())
        elif verb == "status":
            print(describe())
        else:
            print("usage: agent-mode.py on [4h] [pull push update migrate | all] | off | status",
                  file=sys.stderr)
            return 2
    except ValueError as e:
        print("not changed: %s" % e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
