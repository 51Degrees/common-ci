#!/usr/bin/env python3
"""51Degrees CI dashboard triage. See SPEC.md for the design."""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from prompts import FIRST_PROMPT, SECOND_PROMPT

ORG = "51Degrees"
SCRIPT_DIR = Path(__file__).resolve().parent
DASHBOARD_PATH = SCRIPT_DIR.parent.parent / "DASHBOARD.md"
OUT_DIR = SCRIPT_DIR / "out"
FAILED_CONCLUSIONS = {"failure", "cancelled", "timed_out", "startup_failure"}
POLL_INTERVAL_S = 60
POLL_TIMEOUT_S = 90 * 60
CLAUDE_WORKERS = 5
CLAUDE_TIMEOUT_S = 600


@dataclass
class JobResult:
    category: str
    repo: str
    branch: str
    workflow: str
    run_id: int = 0
    conclusion: str = ""
    run_url: str = ""
    head_sha: str = ""
    head_commit_message: str = ""
    triggered_by: str = ""
    started_at: str = ""
    log_path: str | None = None
    first_analysis: str | None = None
    flagged_rerun: bool = False
    rerun_triggered: bool = False
    rerun_conclusion: str | None = None
    rerun_run_url: str | None = None
    rerun_log_path: str | None = None
    second_analysis: str | None = None


_START = time.monotonic()


def log(msg: str) -> None:
    elapsed = time.monotonic() - _START
    stamp = dt.datetime.now().strftime("%H:%M:%S")
    print(f"[{stamp} +{elapsed:7.1f}s] {msg}", file=sys.stderr, flush=True)


def require_token() -> None:
    if not os.environ.get("GH_TOKEN"):
        sys.exit("GH_TOKEN not set — run via ./launch_triage.sh")
    anthropic_vars = sorted(k for k in os.environ if k.startswith("ANTHROPIC_"))
    log(f"[env] ANTHROPIC_* vars visible to script: {anthropic_vars or 'none'}")
    model = os.environ.get("ANTHROPIC_MODEL")
    fallback = os.environ.get("ANTHROPIC_MODEL_FALLBACK")
    log(f"[env] claude --model: {model or '(default, no override)'}")
    log(f"[env] claude --model fallback: {fallback or '(none)'}")


def gh_json(args: list[str]) -> dict | list:
    result = subprocess.run(
        ["gh", *args], capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} -> {result.stderr.strip()}")
    return json.loads(result.stdout) if result.stdout.strip() else {}


# ----------------------------- parse -----------------------------

ROW_RE = re.compile(
    r"^\|\s*\[([^\]]+)\]\(https://github\.com/51Degrees/([^)]+)\)\s*\|"
    r"\s*`([^`]+)`\s*\|\s*(.+?)\s*\|\s*$"
)
WORKFLOW_RE = re.compile(r"actions/workflows/([^/]+\.yml)/badge\.svg")
HEADING_RE = re.compile(r"^###\s+(.+?)\s*$")


def parse_dashboard() -> list[JobResult]:
    text = DASHBOARD_PATH.read_text()
    jobs: list[JobResult] = []
    category = ""
    for line in text.splitlines():
        m_h = HEADING_RE.match(line)
        if m_h:
            category = m_h.group(1).strip()
            continue
        m_r = ROW_RE.match(line)
        if not m_r:
            continue
        _, repo, branch, status_cell = m_r.groups()
        for wf in dict.fromkeys(WORKFLOW_RE.findall(status_cell)):
            jobs.append(JobResult(
                category=category, repo=repo.strip(),
                branch=branch.strip(), workflow=wf,
            ))
    return jobs


# ----------------------------- probe -----------------------------

def probe_runs(jobs: list[JobResult]) -> list[JobResult]:
    failed: list[JobResult] = []
    for job in jobs:
        try:
            resp = gh_json([
                "api",
                f"repos/{ORG}/{job.repo}/actions/workflows/"
                f"{job.workflow}/runs?branch={job.branch}&per_page=1",
            ])
        except RuntimeError as e:
            log(f"[probe] skip {job.repo}/{job.workflow}: {e}")
            continue
        runs = resp.get("workflow_runs", []) if isinstance(resp, dict) else []
        if not runs:
            continue
        r = runs[0]
        if r.get("status") != "completed":
            continue
        conclusion = r.get("conclusion") or ""
        if conclusion not in FAILED_CONCLUSIONS:
            continue
        job.run_id = r["id"]
        job.conclusion = conclusion
        job.run_url = r.get("html_url", "")
        job.head_sha = r.get("head_sha", "")
        commit_msg = ((r.get("head_commit") or {}).get("message") or "").strip()
        job.head_commit_message = commit_msg.splitlines()[0] if commit_msg else ""
        actor = r.get("triggering_actor") or r.get("actor") or {}
        job.triggered_by = actor.get("login", "") or "(unknown)"
        job.started_at = r.get("run_started_at") or r.get("created_at", "")
        failed.append(job)
    return failed


# ----------------------------- logs -----------------------------

def fetch_log(job: JobResult, tmp_dir: Path, *, rerun: bool = False) -> str | None:
    """Download the logs zip via the GH API and extract it to a per-run dir.

    Returns the absolute path of the extracted directory. Claude reads files
    from there with `ls`/`grep`/`head`/`tail`.
    """
    suffix = "-rerun" if rerun else ""
    safe_wf = job.workflow.replace("/", "_")
    log_dir = tmp_dir / f"{job.repo}-{safe_wf}-{job.run_id}{suffix}"
    log_dir.mkdir(parents=True, exist_ok=True)
    zip_path = log_dir / "_logs.zip"
    with open(zip_path, "wb") as fp:
        result = subprocess.run(
            ["gh", "api",
             f"repos/{ORG}/{job.repo}/actions/runs/{job.run_id}/logs"],
            stdout=fp, stderr=subprocess.PIPE, check=False,
        )
    if result.returncode != 0 or zip_path.stat().st_size == 0:
        log(f"[log] {job.repo} run {job.run_id}: {result.stderr.decode().strip()}")
        zip_path.unlink(missing_ok=True)
        return None
    try:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(log_dir)
    except zipfile.BadZipFile:
        log(f"[log] {job.repo} run {job.run_id}: bad zip")
        return None
    finally:
        zip_path.unlink(missing_ok=True)
    return str(log_dir)


def fetch_logs(jobs: list[JobResult], tmp_dir: Path) -> None:
    for job in jobs:
        job.log_path = fetch_log(job, tmp_dir)


def fetch_rerun_logs(jobs: list[JobResult], tmp_dir: Path) -> None:
    for job in jobs:
        if job.rerun_triggered and job.rerun_conclusion not in ("success", None):
            job.rerun_log_path = fetch_log(job, tmp_dir, rerun=True)


# ----------------------------- claude -----------------------------

def claude_env() -> dict[str, str]:
    env = os.environ.copy()
    env.pop("GH_TOKEN", None)
    env.pop("GITHUB_TOKEN", None)
    return env


def _run_claude(prompt: str, model: str | None) -> str:
    cmd = ["claude", "-p", "--allowed-tools", "Bash WebFetch"]
    if model:
        cmd += ["--model", model]
    try:
        result = subprocess.run(
            cmd, input=prompt, capture_output=True, text=True,
            env=claude_env(), check=False, timeout=CLAUDE_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        log("[claude] timeout")
        return f"[claude timeout after {CLAUDE_TIMEOUT_S}s]"
    if result.returncode != 0:
        err = (result.stderr.strip() or result.stdout.strip() or "no output")[:400]
        log(f"[claude] rc={result.returncode}: {err}")
        return f"[claude error rc={result.returncode}: {err}]"
    out = result.stdout.strip()
    if not out:
        log(f"[claude] empty stdout; stderr: {result.stderr.strip()[:300]}")
        return "[claude returned empty output]"
    return out


def claude_analyse(prompt: str) -> str:
    model = os.environ.get("ANTHROPIC_MODEL")
    out = _run_claude(prompt, model)
    if _is_claude_error(out):
        log(f"[claude] primary model {model or '(default)'} failed: {out}")
        fallback = os.environ.get("ANTHROPIC_MODEL_FALLBACK")
        if fallback and fallback != model:
            log(f"[claude] retrying with fallback model: {fallback}")
            out = _run_claude(prompt, fallback)
    return out


def _job_fields(job: JobResult) -> dict[str, str]:
    return {
        "repo": job.repo,
        "branch": job.branch,
        "workflow": job.workflow,
        "run_url": job.run_url,
        "conclusion": job.conclusion,
        "head_sha": job.head_sha,
        "head_commit_message": (job.head_commit_message or "")[:200],
        "triggered_by": job.triggered_by or "(unknown)",
        "started_at": job.started_at,
        "log_path": job.log_path or "(log unavailable — work from the run URL only)",
        "rerun_run_url": job.rerun_run_url or "",
        "rerun_conclusion": job.rerun_conclusion or "",
        "rerun_log_path": job.rerun_log_path or "(log unavailable)",
    }


def _strip_rerun_sentinel(out: str) -> tuple[str, bool]:
    lines = out.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    if lines and lines[-1].strip() == "RERUN":
        lines.pop()
        return "\n".join(lines).rstrip(), True
    return out, False


def _is_claude_error(text: str | None) -> bool:
    return bool(text) and text.startswith(("[claude error", "[claude timeout", "[claude returned empty"))


def first_pass_analyse(jobs: list[JobResult]) -> None:
    def analyse(job: JobResult) -> None:
        out = claude_analyse(FIRST_PROMPT.format(**_job_fields(job)))
        cleaned, flagged = _strip_rerun_sentinel(out)
        job.first_analysis = cleaned
        job.flagged_rerun = flagged

    with ThreadPoolExecutor(max_workers=CLAUDE_WORKERS) as pool:
        list(pool.map(analyse, jobs))
    errs = sum(1 for j in jobs if _is_claude_error(j.first_analysis))
    if errs:
        log(f"[pass1] WARNING: {errs}/{len(jobs)} analyses failed (claude returned error/empty)")


def second_pass_analyse(jobs: list[JobResult]) -> None:
    targets = [
        j for j in jobs
        if j.rerun_triggered and j.rerun_conclusion not in ("success", None)
    ]

    def analyse(job: JobResult) -> None:
        job.second_analysis = claude_analyse(SECOND_PROMPT.format(**_job_fields(job)))

    with ThreadPoolExecutor(max_workers=CLAUDE_WORKERS) as pool:
        list(pool.map(analyse, targets))
    errs = sum(1 for j in targets if _is_claude_error(j.second_analysis))
    if errs:
        log(f"[pass2] WARNING: {errs}/{len(targets)} analyses failed (claude returned error/empty)")


# ----------------------------- rerun + poll -----------------------------

def rerun_flaky(jobs: list[JobResult]) -> None:
    for job in jobs:
        if not job.flagged_rerun:
            continue
        result = subprocess.run(
            ["gh", "run", "rerun", str(job.run_id),
             "--repo", f"{ORG}/{job.repo}"],
            capture_output=True, text=True, check=False,
        )
        if result.returncode == 0:
            job.rerun_triggered = True
        else:
            log(f"[rerun] {job.repo} {job.run_id}: {result.stderr.strip()}")


def poll_reruns(jobs: list[JobResult]) -> None:
    pending = [j for j in jobs if j.rerun_triggered]
    if not pending:
        return
    deadline = {id(j): time.time() + POLL_TIMEOUT_S for j in pending}
    while pending:
        time.sleep(POLL_INTERVAL_S)
        still: list[JobResult] = []
        for job in pending:
            if time.time() > deadline[id(job)]:
                job.rerun_conclusion = "timed_out_polling"
                continue
            try:
                data = gh_json([
                    "run", "view", str(job.run_id),
                    "--repo", f"{ORG}/{job.repo}",
                    "--json", "status,conclusion,url",
                ])
            except RuntimeError as e:
                log(f"[poll] {job.repo} {job.run_id}: {e}")
                still.append(job)
                continue
            if isinstance(data, dict) and data.get("status") == "completed":
                job.rerun_conclusion = data.get("conclusion") or "unknown"
                job.rerun_run_url = data.get("url") or job.run_url
            else:
                still.append(job)
        pending = still


# ----------------------------- report -----------------------------

def write_report(jobs: list[JobResult]) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M")
    path = OUT_DIR / f"report-{stamp}.md"

    passed = [j for j in jobs if j.rerun_triggered and j.rerun_conclusion == "success"]
    failed_after = [j for j in jobs if j.rerun_triggered and j.rerun_conclusion != "success"]
    no_rerun = [j for j in jobs if not j.rerun_triggered]

    lines: list[str] = [
        f"# 51Degrees CI dashboard triage — {stamp}",
        "",
        f"- Failed jobs detected: **{len(jobs)}**",
        f"- Passed after rerun: **{len(passed)}**",
        f"- Failed after rerun: **{len(failed_after)}**",
        f"- Real failures (no rerun): **{len(no_rerun)}**",
        "",
    ]

    def hdr(j: JobResult) -> str:
        return f"### [{j.repo}]({j.run_url}) — `{j.workflow}` ({j.conclusion})"

    if passed:
        lines += ["## Passed after rerun", ""]
        for j in passed:
            lines.append(
                f"- **{j.repo}** `{j.workflow}` — "
                f"[original]({j.run_url}) -> [rerun]({j.rerun_run_url})"
            )
        lines.append("")

    if failed_after:
        lines += ["## Failed after rerun", ""]
        for j in failed_after:
            lines += [
                hdr(j),
                f"Rerun: **{j.rerun_conclusion}** — {j.rerun_run_url}",
                f"Commit `{j.head_sha[:8]}` — {j.head_commit_message[:140]}",
                "",
                j.second_analysis or "_(no analysis)_",
                "",
            ]

    if no_rerun:
        lines += ["## Failed, not flagged as flaky", ""]
        for j in no_rerun:
            lines += [
                hdr(j),
                f"Commit `{j.head_sha[:8]}` — {j.head_commit_message[:140]}",
                "",
                j.first_analysis or "_(no analysis)_",
                "",
            ]

    path.write_text("\n".join(lines))
    return path


# ----------------------------- main -----------------------------

def main() -> int:
    require_token()
    if not DASHBOARD_PATH.exists():
        sys.exit(f"DASHBOARD.md not found at {DASHBOARD_PATH}")

    jobs = parse_dashboard()
    log(f"[parse] {len(jobs)} (repo, workflow) tuples")

    failed = probe_runs(jobs)
    log(f"[probe] {len(failed)} failed runs")
    if not failed:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M")
        path = OUT_DIR / f"report-{stamp}.md"
        path.write_text(
            f"# 51Degrees CI dashboard triage — {stamp}\n\nNo failures detected.\n"
        )
        log(f"[report] {path}")
        return 0

    with tempfile.TemporaryDirectory(prefix="dashboard-triage-") as tmp:
        tmp_dir = Path(tmp)
        fetch_logs(failed, tmp_dir)
        with_log = sum(1 for j in failed if j.log_path)
        log(f"[logs] {with_log}/{len(failed)} downloaded")

        first_pass_analyse(failed)
        flagged = [j for j in failed if j.flagged_rerun]
        log(f"[pass1] {len(flagged)}/{len(failed)} flagged for rerun")

        rerun_flaky(failed)
        triggered = [j for j in failed if j.rerun_triggered]
        log(f"[rerun] {len(triggered)} triggered")

        poll_reruns(failed)
        passed = sum(1 for j in triggered if j.rerun_conclusion == "success")
        log(f"[poll] {passed} passed, {len(triggered) - passed} still failed")

        fetch_rerun_logs(failed, tmp_dir)
        second_pass_analyse(failed)
        analysed = sum(1 for j in failed if j.second_analysis)
        log(f"[pass2] {analysed} post-rerun failures analysed")

        path = write_report(failed)

    log(f"[report] {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
