#!/usr/bin/env python3
"""Look at the GitHub Actions build for this repo from a machine with no Xcode.

The macOS CI job is the only place the iPhone, watch and widget code is compiled and the UI is screenshotted, so
this is the feedback loop for any change to Leaf/, LeafWatch/, LeafWidgets/ or LiveActivityShared/.

    python3 scripts/ci.py status            latest runs and their steps (re-run until "completed")
    python3 scripts/ci.py wait              poll until the newest run finishes, then print the status
    python3 scripts/ci.py errors [run_id]   compiler / test errors from a run (default: newest)
    python3 scripts/ci.py log [run_id]      save the full log to .ci/job.log
    python3 scripts/ci.py shots [run_id]    save the simulator screenshots from the log into .ci/shots/

Set GITHUB_REPO (default norvodesigns/leaf) and optionally GITHUB_TOKEN to raise the API rate limit.
Stdlib only. Output goes under .ci/ (git-ignored).
"""
import base64, json, os, re, subprocess, sys, time

REPO = os.environ.get("GITHUB_REPO", "norvodesigns/leaf")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".ci")


def api(path, raw=False):
    cmd = ["curl", "-sSL"]
    if os.environ.get("GITHUB_TOKEN"):
        cmd += ["-H", f"Authorization: Bearer {os.environ['GITHUB_TOKEN']}"]
    cmd.append(f"https://api.github.com/repos/{REPO}/{path}")
    out = subprocess.run(cmd, capture_output=True).stdout
    return out if raw else json.loads(out or b"{}")


def newest_run():
    runs = api("actions/runs?per_page=1").get("workflow_runs", [])
    return runs[0] if runs else None


def status():
    run = newest_run()
    if not run:
        print("no runs found")
        return None
    print(run["id"], run["head_sha"][:7], run["status"], run["conclusion"], run["created_at"], run["updated_at"])
    for job in api(f"actions/runs/{run['id']}/jobs").get("jobs", []):
        print("  job", job["id"], job["name"], job["status"], job["conclusion"])
        for step in job["steps"]:
            print("    ", step["number"], step["name"], step["status"], step["conclusion"])
    return run


def job_log(run_id=None):
    run_id = run_id or (newest_run() or {}).get("id")
    jobs = api(f"actions/runs/{run_id}/jobs").get("jobs", [])
    if not jobs:
        sys.exit("no jobs for that run yet")
    log = api(f"actions/jobs/{jobs[0]['id']}/logs", raw=True).decode("utf-8", "replace")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "job.log")
    open(path, "w").write(log)
    return path, log


def shots_from_ref(outdir):
    """CI also pushes the JPEGs to the hidden ref refs/ci/screenshots, for machines that can reach github.com but
    not the storage that serves job logs. Returns how many were written."""
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    ref = "refs/ci/screenshots"
    if subprocess.run(["git", "fetch", "-q", "origin", f"+{ref}:{ref}"], cwd=root).returncode != 0:
        return 0
    git = lambda *a: subprocess.run(["git", *a], cwd=root, capture_output=True)
    print(git("log", "-1", "--format=%s", ref).stdout.decode().strip())
    names = git("ls-tree", "--name-only", ref).stdout.decode().split()
    for name in names:
        open(os.path.join(outdir, name), "wb").write(git("show", f"{ref}:{name}").stdout)
    return len(names)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    arg = sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "status":
        status()
    elif cmd == "wait":
        for _ in range(120):
            run = newest_run()
            if run and run["status"] == "completed":
                break
            time.sleep(30)
        status()
    elif cmd == "log":
        path, log = job_log(arg)
        print("saved", path, len(log))
    elif cmd == "errors":
        _, log = job_log(arg)
        seen = []
        for line in log.splitlines():
            if re.search(r"error:|Failing tests|✘| failed", line) and "grep -E" not in line:
                text = re.sub(r"^\S+Z ", "", line).strip()
                if text not in seen:
                    seen.append(text)
        print("\n".join(seen[:80]) if seen else "no errors found in the log")
    elif cmd == "shots":
        path, log = job_log(arg)
        outdir = os.path.join(OUT, "shots")
        os.makedirs(outdir, exist_ok=True)
        count = 0
        for m in re.finditer(r"=====BEGIN (\S+)=====\n(.*?)\n[^\n]*=====END \1=====", log, re.S):
            name, body = m.group(1), m.group(2)
            lines = [re.sub(r"^\S+Z ", "", l).strip() for l in body.splitlines()]
            open(os.path.join(outdir, name + ".jpg"), "wb").write(base64.b64decode("".join(lines)))
            count += 1
        if count == 0:
            count = shots_from_ref(outdir)
        print(f"wrote {count} screenshots to {outdir}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
