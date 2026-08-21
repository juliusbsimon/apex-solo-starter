#!/usr/bin/env bash
# One-time MACHINE setup for WSL/Linux (Ubuntu/Debian).
# Installs: JDK 21, git, rsync, unzip, curl, and SQLcl (latest) into ~/sqlcl.
# Safe to re-run — re-running updates SQLcl to the latest release.
set -euo pipefail

echo "== apt packages =="
sudo apt-get update -qq
sudo apt-get install -y -qq openjdk-21-jre-headless git rsync zip unzip curl

echo "== SQLcl (latest) -> ~/sqlcl =="
curl -fSL -o /tmp/sqlcl.zip \
  https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip
rm -rf "$HOME/sqlcl"
unzip -q /tmp/sqlcl.zip -d "$HOME"
rm -f /tmp/sqlcl.zip

if ! grep -q 'sqlcl/bin' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/sqlcl/bin:$PATH"' >> "$HOME/.bashrc"
  echo "PATH updated in ~/.bashrc (open a new shell or: source ~/.bashrc)"
fi
export PATH="$HOME/sqlcl/bin:$PATH"

echo "== versions =="
java -version 2>&1 | head -1
sql -V
git --version
rsync --version | head -1

cat <<'NOTE'

Done. Remaining per-machine steps that cannot be scripted:
  - Saved connections live per-OS-user: run `sql /nolog` then
    `connect -save <CONN> -savepwd user/pw@//host:1521/service`
    for each project connection (and CLAUDE_RO) INSIDE WSL.
  - SQLcl must be >= your APEX version for APEXlang (`apex export -exptype apexlang`).
    Re-run this script any time to update SQLcl.
NOTE
