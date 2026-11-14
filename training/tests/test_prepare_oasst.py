import gzip
import json
import tempfile
import unittest
from pathlib import Path

from training.prepare_oasst import read_conversations


class PrepareOasstTests(unittest.TestCase):
    def test_builds_best_human_only_english_reply(self) -> None:
        messages = [
            {
                "message_id": "root",
                "parent_id": None,
                "message_tree_id": "tree",
                "role": "prompter",
                "lang": "en",
                "text": "Question",
                "synthetic": False,
                "deleted": False,
                "review_result": True,
            },
            {
                "message_id": "ranked-lower",
                "parent_id": "root",
                "message_tree_id": "tree",
                "role": "assistant",
                "lang": "en",
                "text": "Lower ranked answer",
                "rank": 1,
                "synthetic": False,
                "deleted": False,
                "review_result": True,
            },
            {
                "message_id": "ranked-best",
                "parent_id": "root",
                "message_tree_id": "tree",
                "role": "assistant",
                "lang": "en",
                "text": "Best answer",
                "rank": 0,
                "synthetic": False,
                "deleted": False,
                "review_result": True,
            },
            {
                "message_id": "synthetic",
                "parent_id": "root",
                "message_tree_id": "tree",
                "role": "assistant",
                "lang": "en",
                "text": "Synthetic answer",
                "rank": 0,
                "synthetic": True,
                "deleted": False,
                "review_result": True,
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "oasst.jsonl.gz"
            with gzip.open(path, "wt", encoding="utf-8") as source:
                for message in messages:
                    source.write(json.dumps(message))
                    source.write("\n")

            conversations = read_conversations(path)

        self.assertEqual(conversations, ["User: Question\nCono Nova: Best answer"])


if __name__ == "__main__":
    unittest.main()
