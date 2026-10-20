import 'package:flutter/material.dart';

import '../engine/fen.dart';
import '../engine/san.dart';
import '../engine/stockfish_service.dart';
import 'section_label.dart';

/// Prominent results: FEN context, best move, and engine-backed explanation.
class AnalysisResults extends StatelessWidget {
  const AnalysisResults({
    super.key,
    required this.engine,
  });

  final EngineResult engine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = FenPosition(engine.fen).sideToMoveLabel;
    final pv = engine.principalVariation;
    final bestSan = SanLine.uciToSan(engine.fen, engine.bestMoveUci);

    return Semantics(
      container: true,
      label: 'Analysis results for $side. Best move ${engine.bestMoveUci}. '
          '${engine.whyThisMove}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Best move ($side)'),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: scheme.primary,
                ),
            child: Text(engine.bestMoveUci),
          ),
          if (bestSan != null) ...[
            const SizedBox(height: 2),
            Text(
              bestSan,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          Text(
            engine.bestMoveSpoken,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                label: 'Eval',
                value: engine.scoreLabel,
                emphasize: true,
              ),
              if (engine.depth != null)
                _MetaChip(label: 'Depth', value: '${engine.depth}'),
              if (pv.moves.isNotEmpty)
                _MetaChip(
                  label: pv.usedSan ? 'PV (SAN)' : 'PV (UCI)',
                  value: pv.joined,
                  wide: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          const SectionLabel('Why this move'),
          Text(
            engine.whyThisMove,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                ),
          ),
          if (engine.stub)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                engine.detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.tertiary,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wide ? 420 : 200),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: emphasize
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: wide ? null : 'monospace',
                      color: emphasize ? scheme.primary : scheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty / loading / error callouts for the analyze flow.
class AnalysisStatusBanner extends StatelessWidget {
  const AnalysisStatusBanner({
    super.key,
    required this.busy,
    this.error,
    this.hasResult = false,
    this.hasBoard = false,
  });

  final bool busy;
  final String? error;
  final bool hasResult;
  final bool hasBoard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (error != null) {
      return Semantics(
        liveRegion: true,
        child: Text(
          error!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.error,
                height: 1.4,
              ),
        ),
      );
    }

    if (busy) {
      return Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Working… recognition and Stockfish run on-device.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      );
    }

    if (!hasBoard) {
      return Text(
        'Load a sample, Photos pick, camera frame, or ReplayKit broadcast '
        'to recognize a board.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
      );
    }

    if (!hasResult) {
      return Text(
        'Board ready — set side to move, then Analyze for an engine-backed '
        'recommendation and explanation.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
      );
    }

    return const SizedBox.shrink();
  }
}
