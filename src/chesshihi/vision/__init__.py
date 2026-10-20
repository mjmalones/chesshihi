"""Pluggable vision backends: pixels → board grid → piece classes → FEN."""

from chesshihi.vision.base import BoardRecognizer, RecognitionResult
from chesshihi.vision.template_matcher import TemplateMatcherRecognizer

__all__ = [
    "BoardRecognizer",
    "RecognitionResult",
    "TemplateMatcherRecognizer",
]
