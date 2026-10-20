"""CLI: screenshot → FEN → Stockfish best move.

Fair play: Chesshihi is for post-game analysis, training, and accessibility —
not for live online engine assistance.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import click

from chesshihi import __version__
from chesshihi.engine.stockfish import StockfishEngine, find_stockfish
from chesshihi.paths import assets_root, samples_dir, templates_dir
from chesshihi.render import ensure_sample_assets
from chesshihi.vision.template_matcher import TemplateMatcherRecognizer

FAIR_PLAY = (
    "Fair play: Chesshihi is for analysis, training, and accessibility only — "
    "not live online engine assist."
)


@click.group()
@click.version_option(__version__, prog_name="chesshihi")
def main() -> None:
    """Chesshihi — board screenshot → FEN → Stockfish (analysis / training / accessibility)."""
    pass


@main.command("prepare-assets")
@click.option(
    "--assets",
    type=click.Path(path_type=Path),
    default=None,
    help="Assets directory (default: ./assets).",
)
def prepare_assets(assets: Path | None) -> None:
    """Generate synthetic piece templates and sample board screenshots."""
    root = assets or assets_root()
    sample, templates = ensure_sample_assets(root)
    click.echo(FAIR_PLAY)
    click.echo(f"Wrote templates → {templates}")
    click.echo(f"Wrote samples   → {sample.parent}")


@main.command("recognize")
@click.argument("image", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--side-to-move", type=click.Choice(["w", "b"]), default="w")
@click.option("--castling", default="KQkq", show_default=True)
@click.option("--templates", type=click.Path(path_type=Path), default=None)
@click.option("--json-out", "json_out", is_flag=True, help="Print machine-readable JSON.")
def recognize_cmd(
    image: Path,
    side_to_move: str,
    castling: str,
    templates: Path | None,
    json_out: bool,
) -> None:
    """Locate the board, classify pieces, print FEN."""
    tmpl = templates or templates_dir()
    if not tmpl.is_dir() or not any(tmpl.glob("*.png")):
        ensure_sample_assets(assets_root())
    recognizer = TemplateMatcherRecognizer(
        tmpl, side_to_move=side_to_move, castling=castling
    )
    result = recognizer.recognize(image)
    if json_out:
        click.echo(
            json.dumps(
                {
                    "fen": result.fen,
                    "board_bbox": result.board_bbox,
                    "confidence": result.confidence,
                    "extras": result.extras,
                    "fair_play": FAIR_PLAY,
                },
                indent=2,
            )
        )
    else:
        click.echo(FAIR_PLAY)
        click.echo(f"image:      {image}")
        click.echo(f"board bbox: {result.board_bbox}")
        click.echo(f"confidence: {result.confidence:.3f}")
        click.echo(f"FEN:        {result.fen}")


@main.command("analyze")
@click.argument("image", type=click.Path(exists=True, dir_okay=False, path_type=Path), required=False)
@click.option("--fen", "fen_in", default=None, help="Skip vision; analyze this FEN directly.")
@click.option("--side-to-move", type=click.Choice(["w", "b"]), default="w")
@click.option("--castling", default="KQkq", show_default=True)
@click.option("--templates", type=click.Path(path_type=Path), default=None)
@click.option("--stockfish", "stockfish_path", default=None, help="Path to Stockfish binary.")
@click.option("--depth", type=int, default=None, help="Search depth (overrides movetime).")
@click.option("--movetime", type=int, default=500, show_default=True, help="Movetime in ms.")
@click.option("--json-out", "json_out", is_flag=True)
def analyze_cmd(
    image: Path | None,
    fen_in: str | None,
    side_to_move: str,
    castling: str,
    templates: Path | None,
    stockfish_path: str | None,
    depth: int | None,
    movetime: int,
    json_out: bool,
) -> None:
    """Screenshot (or FEN) → Stockfish best move. Default image: sample starting position."""
    click.echo(FAIR_PLAY, err=not json_out)

    fen = fen_in
    meta: dict = {}
    if fen is None:
        if image is None:
            ensure_sample_assets(assets_root())
            image = samples_dir() / "starting_position.png"
        tmpl = templates or templates_dir()
        if not tmpl.is_dir() or not any(tmpl.glob("*.png")):
            ensure_sample_assets(assets_root())
        recognizer = TemplateMatcherRecognizer(
            tmpl, side_to_move=side_to_move, castling=castling
        )
        result = recognizer.recognize(image)
        fen = result.fen
        meta = {
            "image": str(image),
            "board_bbox": result.board_bbox,
            "confidence": result.confidence,
            "vision": result.extras,
        }

    engine = StockfishEngine(stockfish_path)
    analysis = engine.analyze(
        fen,
        depth=depth,
        movetime_ms=None if depth is not None else movetime,
    )

    payload = {
        "fair_play": FAIR_PLAY,
        "fen": analysis.fen,
        "best_move_uci": analysis.best_move_uci,
        "best_move_san": analysis.best_move_san,
        "score": analysis.score_text,
        "depth": analysis.depth,
        "movetime_ms": analysis.movetime_ms,
        "engine": analysis.engine_path,
        **meta,
    }

    if json_out:
        click.echo(json.dumps(payload, indent=2))
    else:
        if meta.get("image"):
            click.echo(f"image:      {meta['image']}")
            click.echo(f"confidence: {meta.get('confidence', 0):.3f}")
        click.echo(f"FEN:        {analysis.fen}")
        click.echo(f"best move:  {analysis.best_move_san} ({analysis.best_move_uci})")
        click.echo(f"score:      {analysis.score_text}")
        if analysis.depth is not None:
            click.echo(f"depth:      {analysis.depth}")
        else:
            click.echo(f"movetime:   {analysis.movetime_ms} ms")
        click.echo(f"engine:     {analysis.engine_path}")


@main.command("doctor")
@click.option("--stockfish", "stockfish_path", default=None)
def doctor_cmd(stockfish_path: str | None) -> None:
    """Check Stockfish + asset readiness."""
    click.echo(FAIR_PLAY)
    try:
        path = find_stockfish(stockfish_path)
        click.echo(f"Stockfish:  OK ({path})")
    except FileNotFoundError as exc:
        click.echo(f"Stockfish:  MISSING ({exc})", err=True)
        sys.exit(1)
    root = assets_root()
    ensure_sample_assets(root)
    click.echo(f"templates:  {templates_dir()} ({len(list(templates_dir().glob('*.png')))} files)")
    click.echo(f"samples:    {samples_dir()} ({len(list(samples_dir().glob('*.png')))} files)")


if __name__ == "__main__":
    main()
