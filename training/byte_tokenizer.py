"""A dependency-free UTF-8 byte tokenizer for the Cono AI prototype."""

BOS_TOKEN = 256
EOS_TOKEN = 257
VOCAB_SIZE = 258


def encode(text: str) -> list[int]:
    return [BOS_TOKEN, *text.encode("utf-8"), EOS_TOKEN]


def decode(tokens: list[int]) -> str:
    data = bytearray()
    for token in tokens:
        if token in (BOS_TOKEN, EOS_TOKEN):
            continue
        if not 0 <= token <= 255:
            raise ValueError(f"Token id is outside the vocabulary: {token}")
        data.append(token)
    return data.decode("utf-8", errors="replace")
