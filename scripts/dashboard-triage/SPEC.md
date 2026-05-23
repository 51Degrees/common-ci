# Dashboard Triage — Design Spec

## Goal

Given the CI dashboard in [`DASHBOARD.md`](../../DASHBOARD.md), find every monitored workflow whose latest run on its tracked branch is in a terminal failure state, get Claude to analyse each one, retry the ones Claude believes are flaky once, and emit a single markdown report.

KISS, DRY. No GitHub writes other than the explicitly-allowed `gh run rerun`.

## Layout

```
scripts/dashboard-triage/
├── SPEC.md            (this file — committed)
├── README.md          (how to run — committed)
├── triage.py          (single-file pipeline — committed)
├── prompts.py         (first- and second-attempt prompt templates — committed)
├── .gitignore         (committed)
├── launch_triage.sh   (per-machine launcher — GITIGNORED, not committed)
└── out/               (gitignored)
    └── report-YYYY-MM-DD-HHMM.md
```

### Per-machine launcher (`launch_triage.sh`, gitignored)

Each runner provides its own thin launcher whose only job is to put a valid `GH_TOKEN` into the environment (and, on CI/remote runners, `ANTHROPIC_API_KEY` too) before invoking `python3 triage.py`. Concrete examples — macOS Keychain, 1Password CLI, `pass`, a GitHub Actions secret — are environment-specific and intentionally out of scope for the committed code.

Sketch:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export GH_TOKEN=$(<command that prints a 51Degrees token>)
exec python3 triage.py "$@"
```

`triage.py` reads `GH_TOKEN` from `os.environ` and exits cleanly if it's missing. The Python never touches secret stores directly — single responsibility per layer.

## Pipeline

```
parse_dashboard → probe_runs → fetch_logs → first_pass_analyse
  → rerun_flaky → poll_reruns → fetch_rerun_logs → second_pass_analyse
  → write_report
```

Each step is its own function in `triage.py`. The single `JobResult` dataclass flows through them, accreting fields.

All log files live under a single `tempfile.TemporaryDirectory()` created at the top of `main()`; the dir is wiped on exit (success or exception).

### 1. `parse_dashboard()`

- Reads the local `DASHBOARD.md` (path = `../../DASHBOARD.md` relative to the script).
- Walks each markdown table row. For each row, extracts:
  - `category` (last `###` heading seen)
  - `repo` (the first `[name](https://github.com/51Degrees/name)` link)
  - `branch` (the back-ticked value in the second cell, typically `main`)
  - `workflows` — every `actions/workflows/<file>.yml/badge.svg` URL in the status cell, deduplicated.
- One row can yield multiple `(repo, branch, workflow)` tuples.

### 2. `probe_runs(jobs)`

- For each tuple, calls `gh api repos/51Degrees/{repo}/actions/workflows/{wf}/runs?branch={br}&per_page=1`.
- Captures from the response: `id`, `status`, `conclusion`, `html_url`, `head_sha`, `head_commit.message`, `actor.login` (or `triggering_actor.login`), `run_started_at` (or `created_at`). All of these flow into the `JobResult` and are used to render the prompt — Claude gets the full picture without having to call GitHub itself.
- Keeps only runs where `status == "completed"` AND `conclusion` is in
  `{"failure", "cancelled", "timed_out", "startup_failure"}`.
- In-progress runs are skipped (no point analysing a build still running).
- API failures for a single workflow log a warning and skip — don't abort the whole pipeline.

### 3. `fetch_logs(failures, tmp_dir)`

- For every failed `JobResult`, the parent script (using `GH_TOKEN`) downloads the run's logs as a zip via:
  ```
  gh api repos/51Degrees/{repo}/actions/runs/{run_id}/logs > <log_dir>/_logs.zip
  ```
  …then extracts it with Python's `zipfile` module into a per-run directory under `tmp_dir` and deletes the zip. (`gh run view --log` / `--log-failed` is unreliable in some `gh` versions — direct API + extract sidesteps that.)
- Records the directory path on `job.log_path`. Inside it: one `.txt` per matrix job, plus per-step subfolders.
- If the download fails or the zip is empty/corrupt, set `log_path = None` and let Claude work from the run URL alone.
- The logs live on local disk, never sent to Anthropic in bulk — Claude only reads slices via Bash (`ls`, `grep -r`, `head`, `tail`).

### 4. `first_pass_analyse(failures)`

- ThreadPoolExecutor with 5 workers — Claude calls are slow but independent.
- For each `JobResult`, runs `claude -p --allowed-tools "Bash WebFetch"` and pipes the formatted `FIRST_PROMPT` via **stdin** (NOT via argv — `--allowed-tools` is a variadic flag and would otherwise consume the positional prompt as additional tool names).
- **No `GH_TOKEN` in the subprocess env.** Claude inherits a sanitised env (`os.environ.copy()` then `pop("GH_TOKEN", None)` and `pop("GITHUB_TOKEN", None)`). `ANTHROPIC_API_KEY` is left in place since `claude` itself needs it to authenticate to the Anthropic API on machines without an interactive Claude Code session.
- `FIRST_PROMPT` contains: run URL, conclusion, repo, workflow file, attempt number = 1, **and the absolute path to the log directory**. Tells Claude:
  - Start with `ls` of the log directory, then `grep`/`head`/`tail` slices. Don't `cat` whole files.
  - Browse public source via `WebFetch` against `raw.githubusercontent.com` if needed.
  - You do not have `gh` auth — do not attempt authenticated API calls.
  - Produce one short paragraph + relevant file links (full GitHub URLs with line numbers when applicable).
  - If you believe the failure is test flakiness rather than a real bug, end your output with the single token `RERUN` on its own line.
- Parser: if the last non-empty line of stdout, stripped, equals `RERUN`, set `job.flagged_rerun = True` and strip that line from the stored analysis.
- Store the analysis text on `job.first_analysis`.

### 5. `rerun_flaky(jobs)`

- For every `job` with `flagged_rerun == True`:
  - `gh run rerun {run_id} --repo 51Degrees/{repo}` (this is the explicit exception to the no-writes rule).
  - `gh run rerun` re-runs the same run id with an incremented attempt number — there is no new run id to look up.

### 6. `poll_reruns(jobs)`

- For every job that was rerun, poll `gh run view {run_id} --repo 51Degrees/{repo} --json status,conclusion,url` every 60 seconds.
- Terminal when `status == "completed"`. Capture `conclusion` as `job.rerun_conclusion` and `url` as `job.rerun_run_url` (it points at the latest attempt).
- Per-job cap: 90 minutes. If exceeded, set `rerun_conclusion = "timed_out_polling"` and move on.

### 7. `fetch_rerun_logs(jobs, tmp_dir)`

- For every rerun that ended in failure, download its log zip the same way as step 3 to a `<dir>-rerun/` directory under `tmp_dir`.
- Records the directory path on `job.rerun_log_path`.

### 8. `second_pass_analyse(jobs)`

- For every job whose rerun did not succeed (`rerun_conclusion != "success"`), invoke Claude again with `SECOND_PROMPT` (attempt = 2, no `RERUN` option mentioned). The prompt references `job.rerun_log_path` so Claude looks at the latest-attempt logs, not the original ones.
- Same tool scope, same env sanitisation, same stdin-piped invocation, same threading.
- Store result on `job.second_analysis`.

### 9. `write_report(jobs)`

- Writes `out/report-YYYY-MM-DD-HHMM.md` (timestamped per invocation — running twice in one day produces two separate files; no overwrite).
- Three sections:
  - **Passed after rerun** — repo, workflow, original run URL, rerun URL. No analysis text needed.
  - **Failed after rerun** — repo, workflow, both run URLs, `second_analysis` text.
  - **Failed, not flagged as flaky** — first-pass failures Claude did not flag for rerun; show `first_analysis`.
- Top of report: timestamp, total monitored, total failed, breakdown.

## Data model

```python
@dataclass
class JobResult:
    category: str
    repo: str
    branch: str
    workflow: str
    run_id: int
    conclusion: str
    run_url: str
    head_sha: str
    head_commit_message: str
    triggered_by: str
    started_at: str

    log_path: str | None = None           # directory of extracted .txt files
    first_analysis: str | None = None
    flagged_rerun: bool = False

    rerun_triggered: bool = False
    rerun_conclusion: str | None = None
    rerun_run_url: str | None = None      # latest-attempt URL after rerun
    rerun_log_path: str | None = None     # directory, same shape as log_path

    second_analysis: str | None = None
```

## Auth

Two independent secrets are needed:

1. **`GH_TOKEN`** — a GitHub PAT scoped to 51Degrees with `actions:read`, `contents:read`, `actions:write` (the last only for `gh run rerun`). Supplied via env var by whatever launcher the runner uses (`launch_triage.sh`, a CI secret, a shell wrapper, etc.). Used only by the parent script for `gh` calls.

2. **Claude CLI authentication** — either:
   - `ANTHROPIC_API_KEY` in the env (CI/remote runners), or
   - An interactive Claude Code session (`claude /login` once, fine for a workstation).

Before launching `claude -p`, the script does:

```python
claude_env = os.environ.copy()
claude_env.pop("GH_TOKEN", None)
claude_env.pop("GITHUB_TOKEN", None)
```

This way `GH_TOKEN` cannot end up in Claude's stdout (and therefore not in the report file), and cannot end up in Anthropic-side conversation transcripts even if Claude tries to read it. `ANTHROPIC_API_KEY` is intentionally **not** stripped — it's the Anthropic API client's own credential.

If `GH_TOKEN` is missing the script exits with a clear error. Claude's auth is checked implicitly: the first `claude -p` invocation either succeeds or returns an error that surfaces in the report as `[claude error: ...]`.

Claude works from:
1. The pre-downloaded log directory on local disk (parent-fetched with `GH_TOKEN`, then Claude reads slices via `ls`/`grep`/`head`/`tail` — never `cat` whole files).
2. `WebFetch` against `raw.githubusercontent.com` for public 51Degrees source files.

The prompt explicitly tells Claude it has no GitHub auth, so attempts at authenticated API calls fail fast rather than degrade silently.

### Note on `claude -p` semantics

`claude -p` is non-interactive only in the sense that there's no stdin TTY for chat — within a single invocation Claude still runs a full tool-use loop, making many `Bash` / `WebFetch` calls (subject to `--allowed-tools`) before producing its final assistant message, which is what arrives on stdout. So a single `claude -p` call per failure is enough for Claude to grep the logs, fetch source files, reason, and respond.

Implementation detail: the prompt is fed to `claude` via stdin (`subprocess.run(..., input=prompt, ...)`). `--allowed-tools` is a variadic argparse flag — passing the prompt as a positional argv would have it consumed as another tool name and trigger `Error: Input must be provided either through stdin or as a prompt argument`.

## Prompts (`prompts.py`)

Two Python f-string templates, exported as module-level constants. Each is rendered with `template.format(**fields)` where `fields` are pulled off the `JobResult`. Keeping them in their own module makes prompt iteration cheap — no `triage.py` edits to retune wording.

### Common context fields (collected by `probe_runs`)

```
repo, branch, workflow, run_url, conclusion,
head_sha, head_commit_message, triggered_by,
started_at, log_path
```

(For the second pass we additionally pass `rerun_run_url`, `rerun_conclusion`, `rerun_log_path`.)

### `FIRST_PROMPT` (attempt 1, may emit `RERUN`)

```
You are triaging a failed CI workflow run for the 51Degrees engineering team.
This is ATTEMPT 1 of analysis.

Run context
-----------
Repository:        51Degrees/{repo}
Branch:            {branch}
Workflow file:     {workflow}
Run URL:           {run_url}
Conclusion:        {conclusion}
Head commit:       {head_sha}
Commit message:    {head_commit_message}
Triggered by:      {triggered_by}
Started at:        {started_at}

The run's logs have been extracted locally to this directory (one .txt
file per workflow job, possibly inside per-step subfolders):
  {log_path}

Your environment
----------------
- You have NO GitHub authentication. Do not attempt authenticated API calls
  (no `gh` auth, no GitHub API tokens). Public-only access is fine.
- Start by listing the log dir: `ls {log_path}` (and `find {log_path} -name '*.txt'`).
  The names tell you which matrix job/step each file belongs to.
- Inspect logs with Bash: prefer `grep -ri "error\|fail\|exception" {log_path}`,
  `tail -200`, `head -200`, `awk`/`sed` slices. Do NOT `cat` whole files -
  they may be large.
- Use WebFetch against raw.githubusercontent.com to read public source
  files in 51Degrees repos when relevant.

Your task
---------
1. Identify the immediate cause of failure from the logs.
2. Decide whether this looks like a FLAKY failure (transient infra issue,
   network hiccup, race condition, timeout with no real cause, runner
   shortage, package mirror outage) or a REAL failure (test regression,
   broken build, missing dependency, code bug, configuration error).
3. Produce a SINGLE concise paragraph (3-5 sentences) describing the cause
   and a remedy. Where relevant, link to specific source files using full
   GitHub URLs with line numbers, e.g.
     https://github.com/51Degrees/{repo}/blob/{head_sha}/path/to/file.cs#L42

Output format
-------------
- Your paragraph, then a blank line.
- If AND ONLY IF you believe this is flakiness that a single rerun is
  likely to clear, end your output with one final line containing nothing
  but the token:
      RERUN
- If the failure is real, OMIT the RERUN token entirely.

Be terse. No preamble, no apologies, no "I would recommend".
```

### `SECOND_PROMPT` (attempt 2, post-rerun, no `RERUN` allowed)

```
You are triaging a failed CI workflow run for the 51Degrees engineering team.
This is ATTEMPT 2 - the workflow has ALREADY been rerun once and still
failed. Do NOT suggest another rerun; this is not flakiness.

Run context
-----------
Repository:            51Degrees/{repo}
Branch:                {branch}
Workflow file:         {workflow}
Original run URL:      {run_url}     (conclusion: {conclusion})
Rerun URL (attempt 2): {rerun_run_url}  (conclusion: {rerun_conclusion})
Head commit:           {head_sha}
Commit message:        {head_commit_message}
Triggered by:          {triggered_by}

The rerun's logs have been extracted locally to this directory (one .txt
file per workflow job, possibly inside per-step subfolders):
  {rerun_log_path}

Your environment
----------------
- You have NO GitHub authentication. Public-only access.
- Start with `ls {rerun_log_path}` to see the log files.
- Inspect logs with Bash slices (`grep -ri`, `tail`, `head`). Do NOT `cat`
  whole files.
- Use WebFetch against raw.githubusercontent.com for public source files.

Your task
---------
Produce a SINGLE concise paragraph (3-5 sentences) covering:
- The most likely ROOT CAUSE (not just the surface symptom).
- A concrete, ACTIONABLE FIX - name files, functions, or config keys.
  Include full GitHub source URLs with line numbers where they help, e.g.
     https://github.com/51Degrees/{repo}/blob/{head_sha}/path#Lnn

Be terse and specific. No preamble, no apologies, no "I would recommend",
no suggestions to rerun.
```

The canonical strings live in `prompts.py`; the spec versions above mirror them for review.

## DRY helpers

Only two helpers, both in `triage.py` (no separate utils file — overkill):

- `gh_json(args: list[str]) -> dict | list` — wraps `subprocess.run(["gh", ...])`, parses stdout as JSON, returns. Used everywhere `gh` is called for structured output.
- `claude_analyse(prompt: str) -> str` — runs `claude -p --allowed-tools "Bash WebFetch"` with the prompt piped via stdin, captures stdout. Used by both first and second pass.

Plus a tiny `log(msg)` that prefixes each stderr line with `[HH:MM:SS +elapsed]` so you can read off per-step duration by subtracting between consecutive lines.

No other abstractions.

## Tool scope for Claude

`--allowed-tools "Bash WebFetch"`. Bash gives Claude `gh` (without auth), `cat`, `grep`, etc. WebFetch lets it pull raw source from `raw.githubusercontent.com`. No `Write`/`Edit` — Claude cannot modify files during analysis.

## What this deliberately does NOT do

- No PR comments, reviews, issue creation, label edits, commits, pushes.
- No retry beyond the one explicit rerun per flagged job per invocation.
- No persistent state between runs — each invocation is a fresh report.
- No notification/email — just writes the `.md`. Open it manually.
- No double-run protection: running the script back-to-back will see any new failures (including reruns from the previous invocation that subsequently failed) and could trigger fresh reruns. Operator's responsibility to keep cadence sane (typically: once per day after the nightly pipeline finishes).

## Operational notes

- Invocation: `./launch_triage.sh` (personal launcher) or directly `GH_TOKEN=... [ANTHROPIC_API_KEY=...] python3 scripts/dashboard-triage/triage.py`.
- Total runtime dominated by the rerun-poll phase (up to ~90 min per rerun, but reruns run in parallel on GitHub).
- Idempotent for the parse/probe/analyse phases; not for the rerun phase (see above).
- Output: `out/report-YYYY-MM-DD-HHMM.md`, one file per invocation, gitignored.
- Progress lines are timestamped to stderr so duration of each phase is visible at a glance.
