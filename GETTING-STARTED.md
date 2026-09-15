# Getting started — for developers new to Git and GitHub

You build APEX apps in App Builder. This starter adds one habit on top: keeping
a copy of your application as text files, with a full history of every change.
This page assumes you have **never used Git** — read it once, and the
[RUNBOOK](RUNBOOK.md) afterwards will make sense.

## The idea in four sentences

**Git** is a program that keeps a history of a folder: every time you tell it
"save this state" (a *commit*), it remembers exactly what every file looked
like, forever. The folder it watches is called a **repository** ("repo").
**GitHub** is a website that holds an online copy of your repo, so it survives
your laptop and can be shared. Your APEX app becomes files via this starter's
`pull` script — Git does the remembering from there.

## One-time setup (per person)

1. **Get a GitHub account** at github.com (free), and ask to be added to the
   team's repositories if they are private.

2. **Install Git itself.** (The project's setup scripts install everything
   else, but they live inside the repo — and you need Git to get the repo.)

   **Windows** — open PowerShell and run:

   ```
   winget install Git.Git
   ```

   Close and reopen PowerShell afterwards so `git` is found. Then allow local
   scripts to run (one time):

   ```
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

   **WSL** (Linux inside Windows — recommended) — if you don't have WSL yet,
   run `wsl --install` in PowerShell **as administrator**, reboot, and open
   the "Ubuntu" app it installed. Then, in that Ubuntu window:

   ```
   sudo apt update && sudo apt install -y git
   ```

   **Check it worked:** `git --version` prints a version number in either case.

3. **Introduce yourself to Git** (it stamps your name on your work):

   ```
   git config --global user.name  "Your Name"
   git config --global user.email "you@example.com"
   ```

4. **The rest of the tools come later** — after you clone your project
   (next section), run `./scripts/setup-prereqs.sh` (WSL: installs Java,
   SQLcl, everything) or `.\scripts\check-prereqs.ps1` (Windows: checks and
   tells you the install command for anything missing).

## Starting a project from this template

1. On this repo's GitHub page, click the green **Use this template** button →
   *Create a new repository* → name it after your app → **Private** → Create.
   You now have your own online repo with these files in it.
2. **Clone it** — this copies the online repo to a folder on your machine:

   ```
   cd ~/dev                      # or wherever you keep projects
   git clone https://github.com/<you>/<your-repo>.git
   cd <your-repo>
   ```

   The first push/pull asks you to sign in to GitHub in a browser — normal.
   That is Git Credential Manager logging you in with a token it stores and
   renews itself, so prefer it when the browser window works.

   **If no browser opens** (common in WSL, or on a server): either point WSL
   at the Windows credential manager —

   ```
   git config --global credential.helper \
     "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
   ```

   — or use a **personal access token (PAT)**: GitHub → Settings → Developer
   settings → *Fine-grained tokens* → generate one scoped to **just this
   repository** with Contents: read/write, then paste it when git asks for a
   password (the username is your GitHub name). Treat the token like a
   password: it goes into the prompt, never into a file in the repo, and it
   expires — regenerating it is normal, not a sign something broke.
3. Run `./init.sh` (WSL) or `.\init.ps1` (Windows) and answer its prompts.
4. Follow the steps it prints. In short: **save the database connection**
   (inside WSL if that's where you work) → optionally create the agent's
   read-only account (`db/create-claude-ro.sql`, run as admin — it prompts
   for a password) → **first pull** (`./scripts/pull.sh`) → **first commit
   and push** → pull again to confirm `git status` comes back clean →
   **run `./scripts/apex-validate.sh`** (old apps often export with
   Builder-side errors that must be fixed before the workflow opens up).
   The same list lives in RUNBOOK §2 "Setup at a glance" if the terminal
   output has scrolled away.

## If you'd rather click than type

Two launchers run the exact same scripts, so nothing below stops being true —
they just save the typing:

- `python3 scripts/gui.py` — starts a small control panel in your browser at
  `http://localhost:8765`: buttons for pull, validate, push, migrations, and
  commit-and-push, with the output streaming on the page. When a script asks
  a question (the push safety check does), type the answer in the input line
  at the bottom of the page.
- `bash scripts/menu.sh` — the same choices as a numbered menu in the
  terminal (WSL/Linux).

The Git commands below are still worth learning: the launchers cover the
daily loop, and the terminal is what's left when something unusual happens.

## The five commands that are 95% of Git

Run these from the project folder. In order of how often you'll use them:

```
git status                    # "what has changed since my last save?"
git add -A                    # "include everything changed in the next save"
git commit -m "what I did"    # "save this state, labeled"
git push                      # "send my saves to GitHub"
git pull                      # "fetch saves made elsewhere (other PC, web edits)"
```

Your daily APEX loop, in full:

```
./scripts/pull.ps1            # or pull.sh - refresh the files from App Builder
git status                    # see which pages/components changed
git add -A
git commit -m "feat(p12): timesheet approval flow"
git push
```

That's it. Build in App Builder as usual; do the block above at every natural
stopping point (end of a feature, end of the day).

## Reading what changed

- `git diff` before you commit shows exact line-by-line changes — this is how
  you review your own work (press `q` to leave the viewer).
- On GitHub, the repo page → *Commits* shows the history; click any commit to
  see what it changed. Click any file → *History* for just that file's story.

## When something goes wrong

| Situation | What to do |
|---|---|
| "I committed with the wrong message" | `git commit --amend -m "better message"` (only if you haven't pushed yet) |
| "I changed files and regret it" (not yet committed) | `git restore <file>` — puts back the last committed version |
| "push was rejected: fetch first" | Someone (or you, via the GitHub website) changed the online copy. `git pull --rebase`, then `git push`. |
| "I'm lost, is my stuff saved?" | `git status`. Clean = everything committed. Then `git push` and it's on GitHub too. |
| "Permission denied" running `./init.sh` or a script | `chmod +x init.sh scripts/*.sh` — happens on WSL when the repo was pushed from Windows. |
| "No such file or directory" on a command you pasted | You copied the prompt too. Paste only what comes **after** the `$` (or `>`). |
| "I broke a page in App Builder and want yesterday's version" | Find yesterday's commit on GitHub, open the page's file, copy what you need — or ask a teammate before using bigger hammers. |

The one rule that keeps you safe: **commit and push before trying anything
risky.** A pushed commit can always be recovered; work that was never
committed cannot.

## Words you'll hear

| Word | Meaning |
|---|---|
| repo | The project folder Git watches (plus its entire history) |
| commit | One saved state, with a message; also the act of saving |
| push / pull | Send your commits to GitHub / fetch commits from GitHub |
| clone | Copy an online repo to your machine the first time |
| branch | A parallel line of history. Solo projects live on one branch: `main` |
| diff | The line-by-line difference between two states |
| origin | Git's name for "the GitHub copy of this repo" |

## Where you are now, and what's next

If you followed this page, you have: the tools installed, your project cloned
from the template, `init` run, and (per its printed steps) a saved SQLcl
connection and a first commit. **That covers the RUNBOOK's §1 and §2** — you
do not need to repeat them.

Continue in the [RUNBOOK](RUNBOOK.md) at:

- **§2.5** — the read-only agent account (recommended, one-time)
- **§3 — the daily loop** — this is the part you'll live in
- **§5 — troubleshooting** — when something looks wrong

The one rule to carry with you: **edit in one place at a time** — either in
App Builder (then pull), or in the files (then push). Never both between
pulls. The RUNBOOK explains why.
