#!/usr/bin/env python3
"""
Generate constellations_iau.json for NightScope.

Source data:
- d3-celestial `constellations.json`
- d3-celestial `constellations.lines.json`
License: BSD 3-Clause

Output format:
[
  {
    "japaneseName": "...",
    "englishName": "...",
    "centerRA": 0.0,
    "centerDec": 0.0,
    "segments": [[ra1, dec1, ra2, dec2], ...]
  },
  ...
]
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.request
from collections import OrderedDict
from pathlib import Path
from typing import Any

CONSTELLATIONS_URL = "https://github.com/ofrohn/d3-celestial/raw/refs/heads/master/data/constellations.json"
CONSTELLATION_LINES_URL = "https://github.com/ofrohn/d3-celestial/raw/refs/heads/master/data/constellations.lines.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate constellation resource JSON for NightScope")
    default_output = Path(__file__).resolve().parent.parent / "NightScope" / "Models" / "constellations_iau.json"
    parser.add_argument(
        "--output",
        type=Path,
        default=default_output,
        help=f"Output file path (default: {default_output})",
    )
    return parser.parse_args()


def load_json(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": "NightScope/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def normalize_ra(value: float) -> float:
    return round(value % 360.0, 4)


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def build_entries() -> list[dict[str, Any]]:
    constellation_features = load_json(CONSTELLATIONS_URL)["features"]
    line_features = load_json(CONSTELLATION_LINES_URL)["features"]

    entries_by_id: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for feature in constellation_features:
        constellation_id = feature["id"]
        props = feature["properties"]
        display = props["display"]
        entries_by_id.setdefault(
            constellation_id,
            {
                "japaneseName": normalize_text(props["ja"]),
                "englishName": normalize_text(props["name"]),
                "centerRA": normalize_ra(display[0]),
                "centerDec": round(display[1], 4),
                "segments": [],
            },
        )

    seen_segments: dict[str, set[tuple[float, float, float, float]]] = {
        constellation_id: set() for constellation_id in entries_by_id
    }

    for feature in line_features:
        constellation_id = feature["id"]
        for line in feature["geometry"]["coordinates"]:
            for start, end in zip(line, line[1:]):
                segment = (
                    normalize_ra(start[0]),
                    round(start[1], 4),
                    normalize_ra(end[0]),
                    round(end[1], 4),
                )
                reverse_segment = (segment[2], segment[3], segment[0], segment[1])
                if segment in seen_segments[constellation_id] or reverse_segment in seen_segments[constellation_id]:
                    continue
                seen_segments[constellation_id].add(segment)
                entries_by_id[constellation_id]["segments"].append(list(segment))

    entries = list(entries_by_id.values())
    for entry in entries:
        entry["segments"].sort()

    return entries


def main() -> None:
    args = parse_args()
    entries = build_entries()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(entries, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(f"Generated {len(entries)} constellations -> {args.output}")


if __name__ == "__main__":
    main()
