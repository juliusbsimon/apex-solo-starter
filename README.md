   # apex-solo-starter

   Project scaffold for single-developer Oracle APEX 26.1 apps: APEXlang
   source control in Git, pull/push scripts (PowerShell + bash), validation
   gates, agent guardrails, and a read-only DB account for AI-assisted editing.

   ## Quick start
   1. **Use this template** → create your project repo → clone it
   2. `./init.sh` (or `.\init.ps1`) — answers five prompts, stamps the project
   3. Save your SQLcl connection, run `./scripts/pull.sh`, commit the baseline

   Fresh machine? `./scripts/setup-prereqs.sh` (WSL/Linux) or
   `.\scripts\check-prereqs.ps1` (Windows) first.

   Full documentation: **[RUNBOOK.md](RUNBOOK.md)**
