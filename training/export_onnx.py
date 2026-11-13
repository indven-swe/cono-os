"""Export and quantize a trained Cono Nova checkpoint for local app inference."""

import argparse
import tempfile
from pathlib import Path

import numpy
import onnx
import onnxruntime
import torch
from onnxruntime.quantization import QuantType, quantize_dynamic

from training.cono_model import (
    ConoLanguageModel,
    MODEL_NAME,
    MODEL_PRESETS,
    ModelConfig,
)


def export_checkpoint(checkpoint_path: Path, output_path: Path) -> None:
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=True)
    if checkpoint.get("model_name") != MODEL_NAME:
        raise ValueError(f"Checkpoint is not a {MODEL_NAME} model.")
    if checkpoint.get("tokenizer") != "utf-8-bytes-v1":
        raise ValueError("Checkpoint uses an unsupported tokenizer.")

    config = ModelConfig(**checkpoint["model_config"])
    preset = next(
        (
            name
            for name, preset_config in MODEL_PRESETS.items()
            if preset_config == config
        ),
        None,
    )
    if preset is None:
        raise ValueError("Checkpoint does not match a supported model preset.")

    model = ConoLanguageModel(config).eval()
    model.load_state_dict(checkpoint["state_dict"])
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(dir=output_path.parent) as temporary_dir:
        float_model = Path(temporary_dir) / "model-fp32.onnx"
        quantized_model = Path(temporary_dir) / "model-int8.onnx"
        example = torch.ones((1, config.sequence_length), dtype=torch.long)
        torch.onnx.export(
            model,
            example,
            float_model,
            input_names=["token_ids"],
            output_names=["logits"],
            opset_version=17,
            dynamo=False,
        )
        quantize_dynamic(
            float_model,
            quantized_model,
            weight_type=QuantType.QInt8,
            op_types_to_quantize=["MatMul"],
        )

        model_file = onnx.load(quantized_model)
        onnx.checker.check_model(model_file)
        metadata = {
            "cono.model_name": MODEL_NAME,
            "cono.model_preset": preset,
            "cono.parameter_count": str(
                sum(parameter.numel() for parameter in model.parameters())
            ),
            "cono.context_length": str(config.sequence_length),
            "cono.validation_loss": str(checkpoint["validation_loss"]),
            "cono.tokenizer": checkpoint["tokenizer"],
        }
        for key, value in metadata.items():
            entry = model_file.metadata_props.add()
            entry.key = key
            entry.value = value
        onnx.save(model_file, quantized_model)
        session = onnxruntime.InferenceSession(
            str(quantized_model),
            providers=["CPUExecutionProvider"],
        )
        logits = session.run(
            ["logits"],
            {
                "token_ids": numpy.ones(
                    (1, config.sequence_length),
                    dtype=numpy.int64,
                )
            },
        )[0]
        if logits.shape != (1, config.sequence_length, 258):
            raise RuntimeError(
                "Exported Cono Nova model returned an invalid shape."
            )
        del session
        quantized_model.replace(output_path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    export_checkpoint(args.checkpoint, args.output)
    print(f"Exported quantized ONNX model to {args.output}.")


if __name__ == "__main__":
    main()
