#!/usr/bin/env python3
"""Send one JSON control command on an LSL marker stream."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path


def load_pylsl():
    try:
        from pylsl import StreamInfo, StreamOutlet, cf_string, IRREGULAR_RATE  # type: ignore
    except ImportError as exc:
        raise SystemExit("pylsl is not installed. Run: python -m pip install pylsl") from exc
    return StreamInfo, StreamOutlet, cf_string, IRREGULAR_RATE


def main() -> int:
    parser = argparse.ArgumentParser(description="Push one JSON command onto an LSL chain-control stream.")
    parser.add_argument("--stream-name", default="QuestChainControl")
    parser.add_argument("--stream-type", default="Markers")
    parser.add_argument("--source-id", default="myquestionnaire2d-chain-control")
    parser.add_argument("--command-json", default="")
    parser.add_argument("--command-file", default="")
    parser.add_argument("--settle-seconds", type=float, default=1.0)
    args = parser.parse_args()

    if args.command_file:
        command_text = Path(args.command_file).read_text(encoding="utf-8")
    elif args.command_json:
        command_text = args.command_json
    else:
        raise SystemExit("Pass --command-json or --command-file.")
    command = json.loads(command_text)

    StreamInfo, StreamOutlet, cf_string, irregular_rate = load_pylsl()
    info = StreamInfo(args.stream_name, args.stream_type, 1, irregular_rate, cf_string, args.source_id)
    outlet = StreamOutlet(info)
    time.sleep(args.settle_seconds)
    outlet.push_sample([json.dumps(command, separators=(",", ":"))])
    print(json.dumps({"status": "sent", "streamName": args.stream_name, "command": command.get("command")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
