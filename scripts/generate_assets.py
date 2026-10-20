#!/usr/bin/env python3
"""Generate synthetic board samples and piece templates into ./assets."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from chesshihi.render import ensure_sample_assets  # noqa: E402


def main() -> None:
    sample, templates = ensure_sample_assets(ROOT / "assets")
    print(f"templates → {templates}")
    print(f"samples   → {sample.parent}")


if __name__ == "__main__":
    main()
