import unittest

import torch

from training.cono_model import (
    MODEL_PRESETS,
    ConoLanguageModel,
    estimate_parameter_count,
)


class ConoLanguageModelTests(unittest.TestCase):
    def test_model_has_target_parameter_count_and_logits_shape(self) -> None:
        model = ConoLanguageModel().eval()
        parameter_count = sum(parameter.numel() for parameter in model.parameters())
        self.assertGreaterEqual(parameter_count, 20_000_000)
        self.assertLessEqual(parameter_count, 40_000_000)
        self.assertEqual(estimate_parameter_count(model.config), parameter_count)

        with torch.no_grad():
            logits = model(torch.randint(0, 258, (1, 8)))
        self.assertEqual(tuple(logits.shape), (1, 8, 258))

    def test_large_preset_can_exceed_the_original_parameter_limit(self) -> None:
        phone_count = estimate_parameter_count(MODEL_PRESETS["phone-25m"])
        balanced_count = estimate_parameter_count(MODEL_PRESETS["balanced-38m"])
        large_count = estimate_parameter_count(MODEL_PRESETS["large-85m"])

        self.assertLess(phone_count, balanced_count)
        self.assertGreater(balanced_count, 35_000_000)
        self.assertGreater(large_count, 80_000_000)

    def test_future_tokens_do_not_change_prior_logits(self) -> None:
        model = ConoLanguageModel().eval()
        first = torch.randint(0, 258, (1, 8))
        second = first.clone()
        second[:, 4:] = (second[:, 4:] + 1) % 258

        with torch.no_grad():
            first_logits = model(first)
            second_logits = model(second)

        torch.testing.assert_close(
            first_logits[:, :4],
            second_logits[:, :4],
            rtol=0,
            atol=1e-5,
        )


if __name__ == "__main__":
    unittest.main()
