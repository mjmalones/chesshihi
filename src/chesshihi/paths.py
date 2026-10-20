"""Resolve asset paths whether running from a source checkout or an installed package."""

from __future__ import annotations

from pathlib import Path


def repo_root() -> Path:
    # src/chesshihi/paths.py → parents[0]=chesshihi, [1]=src, [2]=repo
    return Path(__file__).resolve().parents[2]


def assets_root() -> Path:
    env = Path(__file__).resolve()
    # Prefer repo-level assets/ when developing from source.
    candidate = repo_root() / "assets"
    if candidate.is_dir():
        return candidate
    # Fallback next to package (if assets were packaged).
    pkg = env.parent / "assets"
    return pkg if pkg.is_dir() else candidate


def templates_dir() -> Path:
    return assets_root() / "templates"


def samples_dir() -> Path:
    return assets_root() / "samples"
