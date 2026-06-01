#!/usr/bin/env python3
"""Delete all GitHub Actions caches for a repository.

Usage:
    GH_TOKEN=... ./delete_actions_caches.py owner/repo
"""
import json
import os
import sys
import urllib.request
import urllib.error

API = "https://api.github.com"


def request(method, url, token):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            return resp.status, json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} on {method} {url}: {e.read().decode()}")


def main():
    if len(sys.argv) != 2 or "/" not in sys.argv[1]:
        sys.exit("Usage: delete_actions_caches.py owner/repo")

    token = os.environ.get("GH_TOKEN")
    if not token:
        sys.exit("GH_TOKEN environment variable is not set")

    repo = sys.argv[1]
    deleted = 0

    while True:
        _, data = request("GET", f"{API}/repos/{repo}/actions/caches?per_page=100", token)
        caches = data.get("actions_caches", [])
        if not caches:
            break
        for c in caches:
            request("DELETE", f"{API}/repos/{repo}/actions/caches/{c['id']}", token)
            print(f"Deleted cache {c['id']} ({c['key']})")
            deleted += 1

    print(f"Done. Deleted {deleted} cache(s) for {repo}.")


if __name__ == "__main__":
    main()
