"""Prints IOS_SIM=<udid> and WATCH_SIM=<udid> for the newest available iPhone and Apple Watch simulators."""
import json
import re
import subprocess

def run(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout

devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "available", "-j"))["runtimes"]
types = json.loads(run("xcrun", "simctl", "list", "devicetypes", "-j"))["devicetypes"]

def version(runtime_id):
    m = re.search(r"(\d+)-(\d+)", runtime_id)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

def pick(platform, preferred):
    candidates = []
    for runtime, devs in devices.items():
        if platform not in runtime:
            continue
        for d in devs:
            score = 0
            for i, name in enumerate(preferred):
                if d["name"].startswith(name):
                    score = len(preferred) - i
                    break
            candidates.append((version(runtime), score, d["udid"]))
    if candidates:
        return max(candidates)[2]
    # No device yet: create one on the newest runtime.
    rts = sorted([r for r in runtimes if platform in r["identifier"]], key=lambda r: version(r["identifier"]))
    if not rts:
        return ""
    rt = rts[-1]
    kind = "iPhone" if platform == "iOS" else "Apple Watch"
    dts = [t for t in types if t["name"].startswith(kind)]
    for name in preferred:
        match = [t for t in dts if t["name"].startswith(name)]
        if match:
            return run("xcrun", "simctl", "create", "Leaf " + kind, match[-1]["identifier"], rt["identifier"]).strip()
    return run("xcrun", "simctl", "create", "Leaf " + kind, dts[-1]["identifier"], rt["identifier"]).strip() if dts else ""

ios = pick("iOS", ["iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone"])
watch = pick("watchOS", ["Apple Watch Series 11 (46mm)", "Apple Watch Series 11", "Apple Watch Series 10 (46mm)", "Apple Watch Ultra", "Apple Watch"])
print(f"IOS_SIM={ios}")
print(f"WATCH_SIM={watch}")
