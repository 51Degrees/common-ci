# Dashboard Triage

Agentic pipeline that scans every workflow listed in
[`DASHBOARD.md`](../../DASHBOARD.md), finds the failed ones, asks Claude to
analyse each failure, retries flaky-looking ones once, and writes a single
markdown report.

See [`SPEC.md`](SPEC.md) for the full design.

## Requirements

- Python 3.10+
- `gh` CLI on `PATH`
- `claude` CLI on `PATH`, authenticated by **one** of:
  - `ANTHROPIC_API_KEY` in the env (recommended for CI / remote
    runners — no interactive login possible there), or
  - A valid Claude Code session on the machine (`claude /login` once
    locally — fine for a workstation).
- A GitHub token in the `GH_TOKEN` env var, scoped to 51Degrees with at
  least:
  - `actions:read`
  - `contents:read`
  - `actions:write` — needed only by `gh run rerun`

The token is **never** passed to Claude (see [`SPEC.md`](SPEC.md), "Auth"),
so a leak surface is the parent script + your shell history only.

## Running

The script reads `GH_TOKEN` (and `ANTHROPIC_API_KEY`, if you're using
that to authenticate Claude) from the environment. Anything that puts
valid values there works:

```bash
GH_TOKEN=ghp_xxx ANTHROPIC_API_KEY=sk-ant-xxx \
    python3 scripts/dashboard-triage/triage.py
```

(Omit `ANTHROPIC_API_KEY` if the `claude` CLI is already logged in via
`claude /login` on that machine.)

You will likely want to wrap that in a local launcher that resolves the
token from whatever secret store your machine uses (macOS Keychain,
1Password CLI, `pass`, CI secret, etc.). Such launchers are
**environment-specific and not committed** — `launch_triage.sh` is in
`.gitignore`. Drop your own copy beside the Python script if you want a
one-command invocation.

Sketch of a local launcher (do not check in):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export GH_TOKEN=$(<command that prints the token>)
exec python3 triage.py "$@"
```

Total runtime is dominated by the rerun-poll phase — up to ~90 minutes
per flagged job, although reruns execute in parallel on GitHub.

The report is written to:

```
scripts/dashboard-triage/out/report-YYYY-MM-DD-HHMM.md
```

Each invocation gets its own timestamped file — re-running mid-day will
not overwrite an earlier report. The `out/` directory is gitignored.

Progress lines on stderr are timestamped (`[HH:MM:SS +elapsed]`) so you
can read off per-step duration by subtracting between consecutive lines.

## What it does (and deliberately does not do)

### Does

- Read `DASHBOARD.md` locally
- Read public GitHub Actions API data to find failed runs
- Download each failed run's logs zip via the API and extract to a
  tempdir
- Invoke `claude -p` per failure to produce a one-paragraph analysis
- Trigger ONE `gh run rerun` per Claude-flagged-flaky job
- Poll until reruns finish, then run a second-pass analysis on the ones
  that still failed
- Write a markdown report

### Does NOT

- Post any comments, reviews, issues, or labels to GitHub
- Commit or push anything
- Rerun any job more than once per invocation
- Send `GH_TOKEN` to Anthropic — `GH_TOKEN` and `GITHUB_TOKEN` are
  stripped from the environment before each `claude -p` call
  (`ANTHROPIC_API_KEY`, if set, is passed through unchanged because
  `claude` itself needs it to authenticate to the Anthropic API)
- Send full failure logs to Anthropic in bulk — Claude only reads the
  slices it needs via `ls`/`grep`/`head`/`tail` on the local tempdir

## Files

| File | Purpose | Committed |
| ---- | ------- | --------- |
| `SPEC.md` | Design spec | yes |
| `README.md` | This file | yes |
| `triage.py` | Single-file pipeline | yes |
| `prompts.py` | First-pass and second-pass prompt templates | yes |
| `.gitignore` | Hides `out/`, `__pycache__/`, and `launch_triage.sh` | yes |
| `launch_triage.sh` | Per-machine launcher (token resolver, Python pin) | **no — gitignored** |
| `out/report-*.md` | Generated reports | no |

## Tuning

Constants live at the top of `triage.py`:

- `POLL_INTERVAL_S` (default 60) — rerun poll interval
- `POLL_TIMEOUT_S` (default 5400) — max wait per rerun
- `CLAUDE_WORKERS` (default 5) — concurrent `claude -p` calls
- `CLAUDE_TIMEOUT_S` (default 600) — per-call cap
- `FAILED_CONCLUSIONS` — which run conclusions count as "failed"

Prompt wording lives in `prompts.py`. Edit that file to retune analysis
behaviour without touching the pipeline code.
