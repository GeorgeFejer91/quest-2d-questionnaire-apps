#!/usr/bin/env python3
"""Bridge LSL control markers into Quest Android app-chain intents."""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


QUESTIONNAIRE_PACKAGE = "org.questquestionnaire.questionnaires2d"
QUESTIONNAIRE_ACTIVITY = "org.questquestionnaire.questionnaires2d.MainActivity"
BROKER_ACTIVITY = "org.questquestionnaire.questionnaires2d.QuestChainBrokerActivity"
RUN_ACTION = "org.questquestionnaire.questionnaires2d.RUN"
BROKER_ACTION = "org.questquestionnaire.questionnaires2d.BROKER"
DEVICE_FILES_DIR = f"/sdcard/Android/data/{QUESTIONNAIRE_PACKAGE}/files"
DEVICE_BROKER_DIR = f"{DEVICE_FILES_DIR}/ChainBroker"

EXTRA_MAP = {
    "sessionId": "mq.sessionId",
    "invocationId": "mq.invocationId",
    "experimentId": "mq.experimentId",
    "scenarioId": "mq.scenarioId",
    "trialId": "mq.trialId",
    "triggerId": "mq.triggerId",
    "triggerSource": "mq.triggerSource",
    "triggerTimestampUtc": "mq.triggerTimestampUtc",
    "triggerTimestampUnixMs": "mq.triggerTimestampUnixMs",
    "chainId": "mq.chainId",
    "chainStepId": "mq.chainStepId",
    "chainStepIndex": "mq.chainStepIndex",
    "participantId": "mq.participantId",
    "participantName": "mq.participantName",
    "language": "mq.language",
    "finishBehavior": "mq.finishBehavior",
    "callerPackage": "mq.callerPackage",
    "callerActivity": "mq.callerActivity",
    "nextPackage": "mq.nextPackage",
    "nextActivity": "mq.nextActivity",
}

PASSIVE_TRIGGER_ALLOWED_KEYS = {
    "schemaVersion",
    "command",
    "sessionId",
    "invocationId",
    "experimentId",
    "scenarioId",
    "trialId",
    "chainId",
    "triggerId",
    "triggerSource",
    "triggerTimestampUtc",
    "triggerTimestampUnixMs",
}

PASSIVE_TRIGGER_MQ_TO_COMMAND_KEY = {
    extra: key
    for key, extra in EXTRA_MAP.items()
    if key in PASSIVE_TRIGGER_ALLOWED_KEYS
}


def load_pylsl():
    try:
        from pylsl import StreamInlet, resolve_stream  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "pylsl is not installed. Run: python -m pip install pylsl"
        ) from exc
    return StreamInlet, resolve_stream


def resolve_adb(requested: str) -> str:
    if requested:
        path = Path(requested)
        if path.exists():
            return str(path)
        raise SystemExit(f"ADB not found: {requested}")

    candidates = [
        shutil.which("adb"),
        r"C:\Program Files\Meta Quest Developer Hub\resources\bin\adb.exe",
        r"C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe",
    ]
    android_home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if android_home:
        candidates.append(str(Path(android_home) / "platform-tools" / "adb.exe"))
        candidates.append(str(Path(android_home) / "platform-tools" / "adb"))

    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(candidate)
    raise SystemExit("ADB not found. Pass --adb explicitly.")


def adb_prefix(args: argparse.Namespace) -> List[str]:
    command = [args.adb]
    if args.serial:
        command += ["-s", args.serial]
    return command


def run_adb(args: argparse.Namespace, adb_args: Iterable[str]) -> subprocess.CompletedProcess[str]:
    command = adb_prefix(args) + list(adb_args)
    if args.verbose:
        print("ADB>", " ".join(command), flush=True)
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if args.verbose or result.returncode != 0:
        print(result.stdout.strip(), flush=True)
    if result.returncode != 0 and not args.keep_going:
        raise RuntimeError(f"ADB command failed with exit code {result.returncode}: {' '.join(command)}")
    return result


def parse_sample(sample: List[Any]) -> Optional[Dict[str, Any]]:
    if not sample:
        return None
    text = str(sample[0]).strip()
    if not text:
        return None
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        print(f"Ignoring non-JSON LSL command sample: {text!r} ({exc})", flush=True)
        return None
    if not isinstance(value, dict):
        print(f"Ignoring JSON sample that is not an object: {value!r}", flush=True)
        return None
    return value


def push_command_replay_marker(args: argparse.Namespace, command: Dict[str, Any]) -> None:
    language = str(command.get("commandReplayLanguage") or "").strip()
    if not language:
        return
    marker_name = "command-replay-deutsch.json" if language.lower().startswith(("deutsch", "german", "de")) else "command-replay-english.json"
    plan = command.get("commandReplayPlan")
    if not isinstance(plan, dict):
        plan = {}
    if "ParticipantName" not in plan and command.get("participantName"):
        plan["ParticipantName"] = command["participantName"]

    run_adb(args, ["shell", "mkdir", "-p", DEVICE_FILES_DIR])
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as handle:
        json.dump(plan, handle, indent=2)
        local_path = handle.name
    try:
        run_adb(args, ["push", local_path, f"{DEVICE_FILES_DIR}/{marker_name}"])
    finally:
        try:
            os.remove(local_path)
        except OSError:
            pass


def add_extra(am_args: List[str], name: str, value: Any) -> None:
    if value is None or value == "":
        return
    if name == "mq.autoCloseDelayMs":
        am_args += ["--el", name, str(int(value))]
    elif name == "mq.chainStepIndex":
        am_args += ["--ei", name, str(int(value))]
    else:
        am_args += ["--es", name, str(value)]


def chain_plan_json(command: Dict[str, Any]) -> Optional[str]:
    plan = command.get("chainPlan")
    plan_json = command.get("chainPlanJson")
    if isinstance(plan, dict):
        plan_json = json.dumps(plan, separators=(",", ":"))
    if not plan_json:
        return None
    return str(plan_json)


def sanitize_passive_trigger_command(command: Dict[str, Any]) -> Dict[str, Any]:
    """Return a passive trigger command or reject questionnaire-routing payloads."""

    sanitized: Dict[str, Any] = {"command": "trigger"}
    rejected: List[str] = []
    for key, value in command.items():
        clean_key = str(key).strip()
        if clean_key in PASSIVE_TRIGGER_ALLOWED_KEYS:
            sanitized[clean_key] = value
        elif clean_key in PASSIVE_TRIGGER_MQ_TO_COMMAND_KEY:
            sanitized[PASSIVE_TRIGGER_MQ_TO_COMMAND_KEY[clean_key]] = value
        else:
            rejected.append(clean_key)

    if rejected:
        rejected_list = ", ".join(sorted(rejected))
        raise RuntimeError(
            "Passive LSL trigger commands may only carry trigger id and inert "
            f"session/source/timing metadata. Rejected field(s): {rejected_list}"
        )
    if not str(sanitized.get("triggerId") or "").strip():
        raise RuntimeError("Passive LSL trigger command requires triggerId.")
    return sanitized


def start_broker(args: argparse.Namespace, command: Dict[str, Any], broker_command: str) -> None:
    am_args = [
        "shell",
        "am",
        "start",
        "-a",
        BROKER_ACTION,
        "-n",
        f"{QUESTIONNAIRE_PACKAGE}/{BROKER_ACTIVITY}",
        "--es",
        "mq.brokerCommand",
        broker_command,
    ]
    for source, extra in EXTRA_MAP.items():
        add_extra(am_args, extra, command.get(source))
    for plain in ("targetPackage", "targetActivity"):
        add_extra(am_args, plain, command.get(plain))
    plan_json = chain_plan_json(command)
    if plan_json:
        encoded = base64.b64encode(plan_json.encode("utf-8")).decode("ascii")
        add_extra(am_args, "mq.chainPlanBase64", encoded)
    elif command.get("chainPlanBase64"):
        add_extra(am_args, "mq.chainPlanBase64", command.get("chainPlanBase64"))
    elif command.get("chainPlanPath"):
        add_extra(am_args, "mq.chainPlanPath", command.get("chainPlanPath"))
    for key, value in command.items():
        if key.startswith("mq."):
            add_extra(am_args, key, value)
    add_extra(am_args, "mq.autoCloseDelayMs", command.get("autoCloseDelayMs"))
    run_adb(args, am_args)


def start_questionnaire(args: argparse.Namespace, command: Dict[str, Any]) -> None:
    push_command_replay_marker(args, command)
    start_broker(args, command, "startQuestionnaire")


def start_plan(args: argparse.Namespace, command: Dict[str, Any]) -> None:
    push_command_replay_marker(args, command)
    start_broker(args, command, "startPlan")


def open_app(args: argparse.Namespace, command: Dict[str, Any]) -> None:
    start_broker(args, command, "openApp")


def handle_command(args: argparse.Namespace, command: Dict[str, Any]) -> None:
    name = str(command.get("command") or "").strip()
    if args.verbose:
        print("LSL command:", json.dumps(command, ensure_ascii=False), flush=True)
    if name == "startQuestionnaire":
        start_questionnaire(args, command)
    elif name == "startPlan":
        start_plan(args, command)
    elif name == "continuePlan":
        start_broker(args, command, "continuePlan")
    elif name == "trigger":
        start_broker(args, sanitize_passive_trigger_command(command), "trigger")
    elif name == "clearPlan":
        start_broker(args, command, "clearPlan")
    elif name == "discoverHooks":
        start_broker(args, command, "discoverHooks")
    elif name == "openApp":
        open_app(args, command)
    elif name == "goHome":
        start_broker(args, command, "goHome")
    elif name == "forceStopQuestionnaire":
        run_adb(args, ["shell", "am", "force-stop", QUESTIONNAIRE_PACKAGE])
    elif name == "ping":
        print("LSL chain bridge ping received.", flush=True)
    else:
        raise RuntimeError(f"Unsupported LSL command: {name!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Receive LSL chain commands and launch Quest APKs via Android intents.")
    parser.add_argument("--stream-name", default="QuestChainControl")
    parser.add_argument("--stream-type", default="")
    parser.add_argument("--resolve-timeout", type=float, default=10.0)
    parser.add_argument("--pull-timeout", type=float, default=0.5)
    parser.add_argument("--adb", default="")
    parser.add_argument("--serial", default="")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--keep-going", action="store_true")
    args = parser.parse_args()
    args.adb = resolve_adb(args.adb)

    StreamInlet, resolve_stream = load_pylsl()
    if args.stream_type:
        print(f"Resolving LSL stream type={args.stream_type!r} timeout={args.resolve_timeout}s...", flush=True)
        streams = resolve_stream("type", args.stream_type, timeout=args.resolve_timeout)
    else:
        print(f"Resolving LSL stream name={args.stream_name!r} timeout={args.resolve_timeout}s...", flush=True)
        streams = resolve_stream("name", args.stream_name, timeout=args.resolve_timeout)
    if not streams:
        raise SystemExit("No matching LSL control stream found.")

    inlet = StreamInlet(streams[0])
    print("LSL chain bridge listening.", flush=True)
    while True:
        sample, timestamp = inlet.pull_sample(timeout=args.pull_timeout)
        if sample is None:
            continue
        command = parse_sample(sample)
        if command is None:
            continue
        try:
            handle_command(args, command)
            print(f"Handled LSL command at {timestamp}: {command.get('command')}", flush=True)
        except Exception as exc:
            print(f"Command failed: {exc}", file=sys.stderr, flush=True)
            if not args.keep_going:
                return 1
        if args.once:
            return 0


if __name__ == "__main__":
    raise SystemExit(main())
