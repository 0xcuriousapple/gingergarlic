#!/usr/bin/env python3
"""Export the gingergarlic corpus as training data for Apple's Foundation
Models adapter training toolkit (LoRA).

Reads ~/.config/gingergarlic/corpus.jsonl (written automatically as you use
the tool) and emits train.jsonl / valid.jsonl in the toolkit's chat format:
one JSON list of {role, content} messages per line.

Usage:
    python3 scripts/export_training_data.py [--min-pairs 200] [--out DIR]

Then follow the toolkit's README to train, roughly:
    1. download the adapter training toolkit from developer.apple.com
       (search "Foundation Models adapter training toolkit") — verify the
       exact data schema in its README matches this export, it can change
       between toolkit releases
    2. train with its provided script/config pointing at train.jsonl
    3. produce the .fmadapter package and copy it to:
       ~/.config/gingergarlic/adapter.fmadapter
    4. relaunch gingergarlic — the menu will show "+ LoRA adapter"

Rejected pairs (you pressed undo) are exported to rejected.jsonl separately;
current toolkit releases don't take preference data, but keep it — it's
useful for filtering and future tuning methods.
"""

import argparse
import json
import random
import sys
from pathlib import Path

SYSTEM_PROMPT = (
    "You rewrite the user's rough draft message so it reads clearly, while "
    "keeping the author's voice. Output only the rewritten draft."
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path,
                        default=Path.home() / ".config/gingergarlic/corpus.jsonl")
    parser.add_argument("--out", type=Path, default=Path("training-data"))
    parser.add_argument("--min-pairs", type=int, default=200,
                        help="refuse to export a corpus too small to be worth training on")
    parser.add_argument("--valid-fraction", type=float, default=0.1)
    args = parser.parse_args()

    if not args.corpus.exists():
        sys.exit(f"no corpus at {args.corpus} — use gingergarlic for a while first")

    accepted, rejected = [], []
    with args.corpus.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            (accepted if entry.get("accepted") else rejected).append(entry)

    if len(accepted) < args.min_pairs:
        sys.exit(
            f"only {len(accepted)} accepted pairs — LoRA on fewer than "
            f"{args.min_pairs} will likely overfit. keep using the tool "
            f"(or lower --min-pairs if you know what you're doing)"
        )

    def to_sample(entry: dict) -> str:
        return json.dumps([
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"draft: {entry['draft']}\nrewrite:"},
            {"role": "assistant", "content": entry["rewrite"]},
        ], ensure_ascii=False)

    random.seed(7)
    random.shuffle(accepted)
    split = max(1, int(len(accepted) * args.valid_fraction))
    valid, train = accepted[:split], accepted[split:]

    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "train.jsonl").write_text(
        "\n".join(to_sample(e) for e in train) + "\n")
    (args.out / "valid.jsonl").write_text(
        "\n".join(to_sample(e) for e in valid) + "\n")
    if rejected:
        (args.out / "rejected.jsonl").write_text(
            "\n".join(json.dumps(e, ensure_ascii=False) for e in rejected) + "\n")

    print(f"exported {len(train)} train / {len(valid)} valid pairs to {args.out}/")
    print(f"({len(rejected)} rejected pairs kept aside in rejected.jsonl)")


if __name__ == "__main__":
    main()
