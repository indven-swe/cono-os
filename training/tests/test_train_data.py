import json
import tempfile
import unittest
from pathlib import Path

from training.train import WindowedByteDataset, read_texts, split_texts


class TrainingDataTests(unittest.TestCase):
    def test_reads_jsonl_text_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "corpus.jsonl"
            path.write_text(
                json.dumps({"text": "first document"})
                + "\n"
                + json.dumps({"text": "second document"})
                + "\n",
                encoding="utf-8",
            )
            self.assertEqual(
                read_texts(path),
                ["first document", "second document"],
            )

    def test_split_is_deterministic_and_disjoint(self) -> None:
        texts = [f"document {index}" for index in range(10)]
        training, validation = split_texts(texts, seed=7)
        repeated_training, repeated_validation = split_texts(texts, seed=7)

        self.assertEqual(training, repeated_training)
        self.assertEqual(validation, repeated_validation)
        self.assertFalse(set(training) & set(validation))
        self.assertEqual(len(training) + len(validation), len(texts))

    def test_builds_next_token_windows(self) -> None:
        dataset = WindowedByteDataset(["a" * 300], sequence_length=256)
        inputs, targets = dataset[0]

        self.assertEqual(tuple(inputs.shape), (256,))
        self.assertEqual(tuple(targets.shape), (256,))
        self.assertEqual(inputs[0].item(), 256)
        self.assertEqual(targets[-1].item(), ord("a"))

    def test_limits_windows_when_requested(self) -> None:
        dataset = WindowedByteDataset(
            ["a" * 4097],
            sequence_length=256,
            max_windows=3,
        )

        self.assertEqual(len(dataset), 3)


if __name__ == "__main__":
    unittest.main()
