#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def yaml_string(value: object) -> str:
    text = str(value)
    if not text or any(ord(character) < 32 for character in text):
        raise ValueError(f"Unsafe catalog text: {text!r}")
    return json.dumps(text, ensure_ascii=False)


def render(catalog: dict[str, object]) -> str:
    lines = ["# Generated from config/service-catalog.json. Do not edit by hand."]
    groups = catalog.get("homepage")
    if not isinstance(groups, list):
        raise ValueError("Catalog homepage section must be a list")
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("items"), list):
            raise ValueError("Invalid Homepage group")
        lines.append(f"- {yaml_string(group.get('group'))}:")
        for item in group["items"]:
            if not isinstance(item, dict):
                raise ValueError("Invalid Homepage item")
            lines.append(f"    - {yaml_string(item.get('name'))}:")
            for key in ("icon", "href", "description"):
                lines.append(f"        {key}: {yaml_string(item.get(key))}")
            if item.get("container"):
                lines.append("        server: local")
                lines.append(f"        container: {yaml_string(item.get('container'))}")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default="config/service-catalog.json")
    parser.add_argument("--output", default="config/homepage/services.yaml")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = render(json.loads(Path(args.catalog).read_text(encoding="utf-8")))
    output = Path(args.output)
    if args.check:
        return 0 if output.exists() and output.read_text(encoding="utf-8") == expected else 1
    output.write_text(expected, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
