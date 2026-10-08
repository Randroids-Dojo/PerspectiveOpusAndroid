#!/usr/bin/env python3
"""Run the exported self-test on an available Android device through ADB."""

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path


PACKAGE = "app.toyboxes.perspectiveopus.selftest"
LAUNCHER = f"{PACKAGE}/com.godot.game.GodotAppLauncher"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Connected wireless or USB ADB serial")
    parser.add_argument("--adb", default=str(Path.home() / "Library/Android/sdk/platform-tools/adb"))
    parser.add_argument("--mode", choices=("flow", "full"), default="full")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--profile", action="store_true")
    parser.add_argument("--install", action="store_true", help="Install the existing self-test APK first")
    parser.add_argument("--output", type=Path, default=Path("/tmp/opus-pixel-campaign"))
    args = parser.parse_args()
    if not 0.25 <= args.speed <= 8:
        parser.error("Speed must be between 0.25 and 8.")
    root = Path(__file__).resolve().parent.parent
    adb = [args.adb, "-s", args.serial]

    def run(*command: str, input_text: str | None = None) -> str:
        result = subprocess.run(adb + list(command), input=input_text, text=True,
                                capture_output=True, timeout=30, check=True)
        return result.stdout.strip()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    log_path = args.output.with_suffix(".log")
    report_path = args.output.with_name(args.output.name + "-report.json")
    logger = None
    try:
        if run("get-state") != "device":
            raise RuntimeError("The requested ADB device is not connected.")
        if re.search(r"\bmode=pinned\b", run("shell", "dumpsys", "activity", "activities")):
            raise RuntimeError("Picture-in-picture is active. Close video playback before running the device checks.")
        if args.install:
            print(run("install", "--no-incremental", "-r", "--user", "0",
                      str(root / "build/PerspectiveOpus-selftest.apk")), flush=True)
        run("shell", "am", "force-stop", "--user", "0", PACKAGE)
        run("shell", "run-as", PACKAGE, "rm", "-f", "files/selftest_report.json")
        config = {"mode": args.mode, "speed": args.speed, "profile": args.profile}
        run("shell", f"run-as {PACKAGE} sh -c 'mkdir -p files && cat > files/selftest_config.json'",
            input_text=json.dumps(config))
        print(run("shell", "am", "start", "-W", "--user", "0", "-n", LAUNCHER), flush=True)
        pid = run("shell", "pidof", PACKAGE).split()[0]
        with log_path.open("w") as stream:
            logger = subprocess.Popen(adb + ["logcat", f"--pid={pid}", "-v", "threadtime", "-T", "1"],
                                      stdout=stream, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + (650 if args.mode == "full" else 90) / args.speed
            next_update = 0.0
            while time.monotonic() < deadline:
                log = log_path.read_text(errors="replace")
                if "SELFTEST REPORT user://selftest_report.json" in log:
                    break
                if re.search(r"SELFTEST FAIL|SCRIPT ERROR|FATAL EXCEPTION", log):
                    raise RuntimeError(f"The exported self-test failed. See {log_path}.")
                focus = run("shell", "dumpsys", "window")
                current = next((line for line in focus.splitlines() if "mCurrentFocus=" in line), "")
                if PACKAGE + "/" not in current:
                    raise RuntimeError("The device foreground changed. Test stopped without touching the other app.")
                if re.search(r"\bmode=pinned\b", run("shell", "dumpsys", "activity", "activities")):
                    raise RuntimeError("Picture-in-picture started during the test. This run is not an isolated device check.")
                if time.monotonic() >= next_update:
                    lines = [line for line in log.splitlines() if "SELFTEST " in line]
                    print(lines[-1] if lines else "Waiting for the renderer and test runner...", flush=True)
                    next_update = time.monotonic() + 30
                time.sleep(2)
            else:
                raise RuntimeError(f"The exported self-test timed out. See {log_path}.")
            # Let Godot release its audio server and finish logging before collecting the receipt.
            time.sleep(1)
        logger.terminate()
        logger.wait(timeout=5)
        logger = None
        report = json.loads(run("exec-out", "run-as", PACKAGE, "cat", "files/selftest_report.json"))
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        expected = 25 if args.mode == "full" else 42
        if (report["mode"] != args.mode or report["fails"] or report["passes"] != expected
                or (args.profile and not report["frames"])):
            raise RuntimeError(f"Unexpected test report. See {report_path}.")
        print(f"PASS: {report['passes']} checks on {report['adapter']} ({report['renderer']}).", flush=True)
        print(f"Report: {report_path}\nLog: {log_path}", flush=True)
        return 0
    except (subprocess.SubprocessError, OSError, ValueError, RuntimeError, IndexError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    finally:
        try:
            if logger is not None:
                logger.terminate()
                logger.wait(timeout=5)
            # Stop only our separate QA package, including after a foreground conflict.
            subprocess.run(adb + ["shell", "am", "force-stop", "--user", "0", PACKAGE],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        except (subprocess.SubprocessError, OSError):
            pass


if __name__ == "__main__":
    raise SystemExit(main())
