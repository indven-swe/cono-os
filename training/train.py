"""Train the Cono AI language model from scratch on a local text corpus."""

import argparse
import json
import random
from pathlib import Path

import torch
from torch.nn import functional as functional
from torch.utils.data import DataLoader, Dataset

from training.byte_tokenizer import encode
from training.cono_model import ConoLanguageModel, MODEL_NAME, MODEL_PRESETS


class WindowedByteDataset(Dataset):
    def __init__(
        self,
        texts: list[str],
        sequence_length: int,
        max_windows: int | None = None,
    ) -> None:
        token_ids = [token for text in texts for token in encode(text)]
        self.tokens = torch.tensor(token_ids, dtype=torch.long)
        self.sequence_length = sequence_length
        self.starts = list(
            range(0, self.tokens.numel() - sequence_length, sequence_length)
        )
        if max_windows is not None:
            self.starts = self.starts[:max_windows]
        if not self.starts:
            raise ValueError(
                "Each dataset split needs at least sequence_length + 1 tokens."
            )

    def __len__(self) -> int:
        return len(self.starts)

    def __getitem__(self, index: int) -> tuple[torch.Tensor, torch.Tensor]:
        start = self.starts[index]
        window = self.tokens[start : start + self.sequence_length + 1]
        return window[:-1], window[1:]


def read_texts(dataset_path: Path) -> list[str]:
    if not dataset_path.is_file():
        raise FileNotFoundError(f"Dataset file not found: {dataset_path}")

    if dataset_path.suffix.lower() == ".jsonl":
        texts = []
        with dataset_path.open(encoding="utf-8") as dataset_file:
            for line_number, line in enumerate(dataset_file, start=1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(
                        f"Invalid JSON on line {line_number}: {error}"
                    ) from error
                text = record.get("text") if isinstance(record, dict) else None
                if not isinstance(text, str) or not text.strip():
                    raise ValueError(
                        f"Line {line_number} must contain a non-empty text field."
                    )
                texts.append(text)
        return texts

    content = dataset_path.read_text(encoding="utf-8")
    return [paragraph.strip() for paragraph in content.split("\n\n") if paragraph.strip()]


def split_texts(texts: list[str], seed: int) -> tuple[list[str], list[str]]:
    if len(texts) < 2:
        raise ValueError("Provide at least two documents for train/validation splits.")
    shuffled = list(texts)
    random.Random(seed).shuffle(shuffled)
    validation_count = max(1, round(len(shuffled) * 0.1))
    validation_count = min(validation_count, len(shuffled) - 1)
    return shuffled[validation_count:], shuffled[:validation_count]


def evaluate(
    model: ConoLanguageModel, batches: DataLoader, device: torch.device
) -> float:
    model.eval()
    total_loss = 0.0
    batch_count = 0
    with torch.no_grad():
        for inputs, targets in batches:
            inputs = inputs.to(device)
            targets = targets.to(device)
            logits = model(inputs)
            loss = functional.cross_entropy(
                logits.reshape(-1, logits.size(-1)),
                targets.reshape(-1),
            )
            total_loss += loss.item()
            batch_count += 1
    return total_loss / batch_count


def choose_device(requested: str) -> torch.device:
    if requested == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested, but no CUDA device is available.")
    if requested == "auto":
        requested = "cuda" if torch.cuda.is_available() else "cpu"
    return torch.device(requested)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--model-size",
        choices=tuple(MODEL_PRESETS),
        default="phone-25m",
        help="Model capacity preset; larger models require more training and phone memory.",
    )
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--threads",
        type=int,
        default=8,
        help="CPU worker threads used for training.",
    )
    parser.add_argument(
        "--max-windows",
        type=int,
        help="Limit the number of sequence windows in each split; defaults to all.",
    )
    parser.add_argument("--device", choices=("auto", "cpu", "cuda"), default="auto")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if (
        args.epochs < 1
        or args.batch_size < 1
        or args.learning_rate <= 0
        or args.threads < 1
        or (args.max_windows is not None and args.max_windows < 1)
    ):
        raise ValueError(
            "Epochs, batch size, threads, max windows, and learning rate "
            "must be positive."
        )

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    torch.set_num_threads(args.threads)
    device = choose_device(args.device)
    training_texts, validation_texts = split_texts(
        read_texts(args.dataset), args.seed
    )
    config = MODEL_PRESETS[args.model_size]
    output_path = args.output or Path(
        f"training/checkpoints/cono-nova-{args.model_size}.pt"
    )
    training_data = WindowedByteDataset(
        training_texts, config.sequence_length, max_windows=args.max_windows
    )
    validation_data = WindowedByteDataset(
        validation_texts, config.sequence_length, max_windows=args.max_windows
    )
    training_batches = DataLoader(
        training_data,
        batch_size=args.batch_size,
        shuffle=True,
    )
    validation_batches = DataLoader(
        validation_data,
        batch_size=args.batch_size,
    )

    model = ConoLanguageModel(config).to(device)
    parameter_count = sum(parameter.numel() for parameter in model.parameters())
    print(
        f"Training {MODEL_NAME} from scratch: "
        f"{parameter_count:,} parameters on {device}.",
        flush=True,
    )
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate)
    best_validation_loss = float("inf")

    for epoch in range(1, args.epochs + 1):
        model.train()
        for batch_index, (inputs, targets) in enumerate(training_batches, start=1):
            inputs = inputs.to(device)
            targets = targets.to(device)
            optimizer.zero_grad(set_to_none=True)
            logits = model(inputs)
            loss = functional.cross_entropy(
                logits.reshape(-1, logits.size(-1)),
                targets.reshape(-1),
            )
            loss.backward()
            optimizer.step()
            if batch_index % 250 == 0 or batch_index == len(training_batches):
                print(
                    f"Epoch {epoch}/{args.epochs}: "
                    f"training batch {batch_index}/{len(training_batches)}",
                    flush=True,
                )

        validation_loss = evaluate(model, validation_batches, device)
        print(
            f"Epoch {epoch}/{args.epochs}: "
            f"validation loss {validation_loss:.4f}",
            flush=True,
        )
        if validation_loss < best_validation_loss:
            best_validation_loss = validation_loss
            output_path.parent.mkdir(parents=True, exist_ok=True)
            torch.save(
                {
                    "model_config": config.__dict__,
                    "state_dict": model.state_dict(),
                    "model_name": MODEL_NAME,
                    "model_preset": args.model_size,
                    "validation_loss": validation_loss,
                    "tokenizer": "utf-8-bytes-v1",
                },
                output_path,
            )
            print(f"Saved best checkpoint to {output_path}.", flush=True)


if __name__ == "__main__":
    main()
