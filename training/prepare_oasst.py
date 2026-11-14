"""Prepare English, non-synthetic OASST1 conversations for Cono Nova."""

import argparse
import gzip
import hashlib
import json
from collections import defaultdict
from pathlib import Path
from urllib.request import Request, urlopen


DATASET_URL = (
    "https://huggingface.co/datasets/OpenAssistant/oasst1/resolve/"
    "fdf72ae0827c1cda404aff25b6603abec9e3399b/"
    "2023-04-12_oasst_ready.messages.jsonl.gz"
)
DATASET_SHA256 = "286a6e9a5a413b3272ae9c0b5a20d327983dea1c24342ae28cb244a6da65185c"
REJECTED_LABELS = {
    "spam",
    "lang_mismatch",
    "pii",
    "not_appropriate",
    "hate_speech",
    "sexual_content",
}


def _label_scores(labels: object) -> dict[str, float]:
    if not isinstance(labels, dict):
        return {}
    names = labels.get("name")
    values = labels.get("value")
    if isinstance(names, list) and isinstance(values, list):
        return {
            name: value
            for name, value in zip(names, values)
            if isinstance(name, str) and isinstance(value, (int, float))
        }

    scores = {}
    for name, value in labels.items():
        if isinstance(value, dict):
            value = value.get("value")
        if isinstance(name, str) and isinstance(value, (int, float)):
            scores[name] = value
    return scores


def _is_eligible(message: dict) -> bool:
    if (
        message.get("lang") != "en"
        or message.get("role") not in {"prompter", "assistant"}
        or message.get("synthetic") is not False
        or message.get("deleted") is not False
        or message.get("review_result") is not True
        or not isinstance(message.get("text"), str)
        or not message["text"].strip()
    ):
        return False
    scores = _label_scores(message.get("labels"))
    return not any(scores.get(label, 0) > 0 for label in REJECTED_LABELS)


def read_conversations(source: Path) -> list[str]:
    trees: dict[str, dict[str, dict]] = defaultdict(dict)
    with gzip.open(source, "rt", encoding="utf-8") as dataset:
        for line_number, line in enumerate(dataset, start=1):
            if not line.strip():
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(
                    f"Invalid OASST1 JSON on line {line_number}: {error}"
                ) from error
            if not isinstance(message, dict):
                raise ValueError(f"OASST1 line {line_number} is not an object.")
            if not _is_eligible(message):
                continue

            message_id = message.get("message_id")
            tree_id = message.get("message_tree_id")
            if not isinstance(message_id, str) or not isinstance(tree_id, str):
                continue
            if message_id in trees[tree_id]:
                raise ValueError(f"Duplicate OASST1 message id: {message_id}")
            trees[tree_id][message_id] = message

    conversations = []
    for messages in trees.values():
        roots = [
            message
            for message in messages.values()
            if message.get("parent_id") is None
            and message.get("role") == "prompter"
        ]
        if not roots:
            continue
        root = min(roots, key=lambda message: message["message_id"])
        children: dict[str, list[dict]] = defaultdict(list)
        for message in messages.values():
            parent_id = message.get("parent_id")
            if isinstance(parent_id, str) and parent_id in messages:
                children[parent_id].append(message)

        path = [root]
        while len(path) < 32:
            parent = path[-1]
            expected_role = (
                "assistant" if parent["role"] == "prompter" else "prompter"
            )
            candidates = [
                message
                for message in children.get(parent["message_id"], [])
                if message["role"] == expected_role
            ]
            if not candidates:
                break
            if expected_role == "assistant":
                candidates.sort(
                    key=lambda message: (
                        message.get("rank") is None,
                        message.get("rank", 0),
                        message.get("created_date", ""),
                        message["message_id"],
                    )
                )
            else:
                candidates.sort(
                    key=lambda message: (
                        message.get("created_date", ""),
                        message["message_id"],
                    )
                )
            path.append(candidates[0])

        if len(path) < 2 or path[-1]["role"] != "assistant":
            continue
        turns = [
            f"{'User' if message['role'] == 'prompter' else 'Cono Nova'}: "
            f"{message['text'].strip()}"
            for message in path
        ]
        conversations.append("\n".join(turns))

    return conversations


def download_dataset(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".part")
    request = Request(DATASET_URL, headers={"User-Agent": "ConoOS-training/1.0"})
    digest = hashlib.sha256()
    try:
        with urlopen(request, timeout=60) as response, temporary.open("wb") as file:
            while chunk := response.read(1024 * 1024):
                file.write(chunk)
                digest.update(chunk)
        if digest.hexdigest() != DATASET_SHA256:
            raise ValueError("Downloaded OASST1 file failed SHA-256 verification.")
        temporary.replace(destination)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=Path("training/data/oasst1-ready.messages.jsonl.gz"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("training/data/cono-nova-oasst1-en.jsonl"),
    )
    args = parser.parse_args()

    if not args.source.is_file():
        print(f"Downloading the Apache-2.0 OASST1 dataset to {args.source}.")
        download_dataset(args.source)

    conversations = read_conversations(args.source)
    if not conversations:
        raise ValueError("No eligible English conversations were found in OASST1.")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as output:
        for conversation in conversations:
            output.write(json.dumps({"text": conversation}, ensure_ascii=False))
            output.write("\n")
    print(f"Prepared {len(conversations):,} conversations in {args.output}.")


if __name__ == "__main__":
    main()
