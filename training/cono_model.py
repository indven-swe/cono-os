"""Decoder-only Transformer architecture initialized without pretrained weights."""

from dataclasses import dataclass

import torch
from torch import nn

from training.byte_tokenizer import VOCAB_SIZE

MODEL_NAME = "Cono Nova"


@dataclass(frozen=True)
class ModelConfig:
    sequence_length: int = 256
    width: int = 512
    layers: int = 8
    heads: int = 8
    dropout: float = 0.1


MODEL_PRESETS = {
    "phone-25m": ModelConfig(width=512, layers=8, heads=8),
    "balanced-38m": ModelConfig(width=512, layers=12, heads=8),
    "large-85m": ModelConfig(width=768, layers=12, heads=12),
}


def estimate_parameter_count(config: ModelConfig) -> int:
    width = config.width
    embeddings = VOCAB_SIZE * width + config.sequence_length * width
    transformer_layers = config.layers * (12 * width * width + 13 * width)
    final_norm = 2 * width
    return embeddings + transformer_layers + final_norm


class ConoLanguageModel(nn.Module):
    def __init__(self, config: ModelConfig = ModelConfig()) -> None:
        super().__init__()
        if min(config.sequence_length, config.width, config.layers, config.heads) < 1:
            raise ValueError("Model dimensions must be positive.")
        if config.width % config.heads:
            raise ValueError("Model width must be divisible by the attention heads.")
        if not 0 <= config.dropout < 1:
            raise ValueError("Dropout must be in the range [0, 1).")

        self.config = config
        self.token_embedding = nn.Embedding(VOCAB_SIZE, config.width)
        self.position_embedding = nn.Embedding(config.sequence_length, config.width)
        self.blocks = nn.ModuleList(
            [
                nn.TransformerEncoderLayer(
                    d_model=config.width,
                    nhead=config.heads,
                    dim_feedforward=config.width * 4,
                    dropout=config.dropout,
                    activation="gelu",
                    batch_first=True,
                    norm_first=True,
                )
                for _ in range(config.layers)
            ]
        )
        self.final_norm = nn.LayerNorm(config.width)
        self.language_head = nn.Linear(config.width, VOCAB_SIZE, bias=False)
        self.language_head.weight = self.token_embedding.weight

        nn.init.normal_(self.token_embedding.weight, mean=0.0, std=0.02)
        nn.init.normal_(self.position_embedding.weight, mean=0.0, std=0.02)

    def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
        sequence_length = token_ids.size(1)
        if sequence_length > self.config.sequence_length:
            raise ValueError("Input exceeds the configured sequence length.")

        positions = torch.arange(sequence_length, device=token_ids.device)
        hidden = self.token_embedding(token_ids) + self.position_embedding(positions)
        causal_mask = torch.triu(
            torch.ones(
                sequence_length,
                sequence_length,
                device=token_ids.device,
                dtype=torch.bool,
            ),
            diagonal=1,
        )
        for block in self.blocks:
            hidden = block(hidden, src_mask=causal_mask)
        return self.language_head(self.final_norm(hidden))
