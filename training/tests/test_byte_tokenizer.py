import unittest

from training.byte_tokenizer import BOS_TOKEN, EOS_TOKEN, decode, encode


class ByteTokenizerTests(unittest.TestCase):
    def test_round_trips_unicode_text(self) -> None:
        text = "Cono AI: hello, 世界 🌑"
        self.assertEqual(decode(encode(text)), text)

    def test_encoding_adds_boundaries(self) -> None:
        self.assertEqual(encode("A"), [BOS_TOKEN, ord("A"), EOS_TOKEN])

    def test_rejects_ids_outside_vocabulary(self) -> None:
        with self.assertRaises(ValueError):
            decode([258])


if __name__ == "__main__":
    unittest.main()
