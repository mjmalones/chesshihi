import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';

import 'capture/frame_ingest.dart';
import 'capture/replaykit_service.dart';
import 'engine/fen.dart';
import 'engine/stockfish_service.dart';
import 'fair_play.dart';
import 'speech/announce.dart';
import 'ui/analysis_results.dart';
import 'ui/app_theme.dart';
import 'ui/fair_play_banner.dart';
import 'ui/screen_capture_section.dart';
import 'ui/section_label.dart';
import 'vision/board_recognizer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChesshihiApp());
}

class ChesshihiApp extends StatelessWidget {
  const ChesshihiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chesshihi',
      debugShowCheckedModeBanner: false,
      theme: ChesshihiTheme.light(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recognizer = BoardRecognizer();
  final _engine = StockfishService();
  final _announcer = MoveAnnouncer();
  final _picker = ImagePicker();
  final _replayKit = ReplayKitService();
  late final _frameIngest = FrameIngest(recognizer: _recognizer);
  final _framePolicy = const FrameIngestPolicy();

  String? _imageLabel;
  ImageProvider? _preview;
  RecognitionResult? _recognition;
  EngineResult? _engineResult;
  String? _error;
  bool _busy = false;

  /// Spoken best-move output (TTS). Off by default if user prefers quiet review.
  bool _speakBestMove = true;

  /// Training/review capture loop — not for live online engine assist.
  /// When on, each Photos/camera/ReplayKit frame auto-runs analysis for the set side.
  bool _liveWatch = false;

  /// Poll App Group for ReplayKit frames (training/review only).
  bool _screenCaptureWatch = false;
  BroadcastState _broadcast = BroadcastState.unsupported;
  Timer? _broadcastPoll;
  String? _lastBroadcastHash;
  DateTime? _lastBroadcastIngestAt;

  static const _samples = [
    (
      path: 'assets/samples/starting_position.png',
      label: 'Starting position (sample)',
    ),
    (
      path: 'assets/samples/italian_game.png',
      label: 'Italian Game (sample)',
    ),
    (
      path: 'assets/samples/kings_queen_endgame.png',
      label: 'K+Q endgame (sample)',
    ),
  ];

  FenPosition? get _fen {
    final fen = _recognition?.fen;
    if (fen == null) return null;
    return FenPosition(fen);
  }

  @override
  void initState() {
    super.initState();
    _loadSample(_samples.first);
  }

  @override
  void dispose() {
    _broadcastPoll?.cancel();
    _engine.dispose();
    _announcer.dispose();
    super.dispose();
  }

  void _setRecognition(RecognitionResult result, {String? label}) {
    setState(() {
      if (label != null) _imageLabel = label;
      _recognition = result;
      _engineResult = null;
      if (!result.success) {
        _error = result.note;
      } else {
        _error = null;
      }
    });
  }

  Future<void> _loadSample(
    ({String path, String label}) sample,
  ) async {
    setState(() {
      _busy = true;
      _imageLabel = sample.label;
      _preview = AssetImage(sample.path);
      _error = null;
    });
    try {
      final side = _fen?.sideToMove ?? 'w';
      final result = await _recognizer.recognizeAsset(
        sample.path,
        sideToMove: side,
      );
      if (!mounted) return;
      _setRecognition(result, label: sample.label);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Recognition error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final label = source == ImageSource.camera
          ? 'Camera: ${file.name}'
          : 'Photos: ${file.name}';
      await _ingestLocalFile(File(file.path), label: label);
    } catch (e) {
      setState(() => _error = 'Could not open image: $e');
    }
  }

  /// Apply current side-to-move to a freshly recognized FEN.
  RecognitionResult _withCurrentSide(RecognitionResult result) {
    final fen = result.fen;
    if (!result.success || fen == null) return result;
    final side = _fen?.sideToMove;
    if (side == null) return result;
    final nextFen = FenPosition(fen).withSideToMove(side);
    if (nextFen == fen) return result;
    return RecognitionResult(
      fen: nextFen,
      source: result.source,
      note: result.note,
      success: true,
      confidence: result.confidence,
    );
  }

  Future<void> _ingestLocalFile(File file, {required String label}) async {
    setState(() {
      _busy = true;
      _imageLabel = label;
      _preview = FileImage(file);
      _error = null;
    });
    try {
      final side = _fen?.sideToMove ?? 'w';
      final recognized = _withCurrentSide(
        await _frameIngest.recognizeFile(
          file,
          label: label,
          sideToMove: side,
        ),
      );
      if (!mounted) return;
      _setRecognition(recognized);
      if (recognized.success && (_liveWatch || _screenCaptureWatch)) {
        await _analyze();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Recognition error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setScreenCaptureWatch(bool enabled) {
    setState(() => _screenCaptureWatch = enabled);
    _broadcastPoll?.cancel();
    _broadcastPoll = null;
    if (!enabled) return;
    // Also enable live-watch semantics for analyze-on-frame.
    if (!_liveWatch) {
      setState(() => _liveWatch = true);
    }
    _broadcastPoll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_pollBroadcast());
    });
    unawaited(_pollBroadcast());
  }

  Future<void> _pollBroadcast() async {
    if (!_screenCaptureWatch || !mounted) return;
    final state = await _replayKit.getState();
    if (!mounted) return;
    setState(() => _broadcast = state);

    if (!_framePolicy.shouldIngest(
      candidateHash: state.contentHash,
      lastHash: _lastBroadcastHash,
      lastIngestAt: _lastBroadcastIngestAt,
      now: DateTime.now(),
    )) {
      return;
    }
    if (!state.hasFrame || _busy) return;

    final path = state.framePath!;
    _lastBroadcastHash = state.contentHash;
    _lastBroadcastIngestAt = DateTime.now();
    await _ingestLocalFile(
      File(path),
      label: 'Broadcast frame #${state.frameCount}',
    );
  }

  void _setSideToMove(String side) {
    final current = _recognition;
    final fen = current?.fen;
    if (current == null || fen == null || !current.success) return;
    final nextFen = FenPosition(fen).withSideToMove(side);
    if (nextFen == fen) return;
    _setRecognition(
      RecognitionResult(
        fen: nextFen,
        source: current.source,
        note: '${current.note} Side to move set manually to '
            '${side == 'w' ? 'White' : 'Black'} — Stockfish will analyze for that side.',
        success: true,
        confidence: current.confidence,
      ),
    );
  }

  Future<void> _analyze({bool? speakOverride}) async {
    final recognition = _recognition;
    final fen = recognition?.fen;
    if (recognition == null || fen == null || !recognition.success) {
      setState(() {
        _error = recognition?.note ??
            'No board position to analyze — pick a clear board image first.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _engineResult = null;
    });

    try {
      final result = await _engine.analyze(fen);
      if (!mounted) return;
      setState(() => _engineResult = result);

      final shouldSpeak = speakOverride ?? _speakBestMove;
      final announcement = result.stub
          ? 'Stub best move for ${FenPosition(result.fen).sideToMoveLabel}: '
              '${result.bestMoveSpoken}. ${result.whyThisMove}'
          : 'Best move for ${FenPosition(result.fen).sideToMoveLabel}: '
              '${result.bestMoveSpoken}. ${result.whyThisMove}';

      // Always update accessibility semantics; TTS is optional.
      await SemanticsService.sendAnnouncement(
        View.of(context),
        announcement,
        TextDirection.ltr,
      );
      if (shouldSpeak) {
        await _announcer.speak(announcement);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Engine error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recognition = _recognition;
    final engine = _engineResult;
    final fen = _fen;
    final boardReady =
        recognition != null && recognition.success && recognition.fen != null;
    final widest = MediaQuery.sizeOf(context).width;
    final isWide = widest >= 900;

    final primaryColumn = <Widget>[
      const FairPlayBanner(),
      const SizedBox(height: 22),
      Text(
        'Chesshihi',
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
      ),
      const SizedBox(height: 6),
      Text(
        'Board → FEN → Stockfish → optional spoken best move',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
      ),
      const SizedBox(height: 20),
      if (_preview != null)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: ClipRRect(
            key: ValueKey(_imageLabel ?? _preview.hashCode),
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: scheme.surface.withValues(alpha: 0.65),
                child: Image(image: _preview!, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      if (_imageLabel != null) ...[
        const SizedBox(height: 8),
        Text(
          _imageLabel!,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
      const SizedBox(height: 16),
      const SectionLabel('Capture'),
      Text(
        'Samples for a quick check, or Photos / camera for a real board frame.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in _samples)
            OutlinedButton(
              onPressed: _busy ? null : () => _loadSample(s),
              child: Text(s.label.split(' (').first),
            ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Photos'),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Capture frame'),
          ),
        ],
      ),
      const SizedBox(height: 22),
      if (recognition != null) ...[
        if (fen != null) ...[
          const SectionLabel('Side to move'),
          Text(
            'Stockfish only analyzes the side in the FEN. '
            'Vision assumes White at bottom and cannot see clocks — '
            'set this if the turn looks wrong.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'w',
                label: Text('White'),
                icon: Icon(Icons.circle_outlined),
              ),
              ButtonSegment(
                value: 'b',
                label: Text('Black'),
                icon: Icon(Icons.circle),
              ),
            ],
            selected: {fen.sideToMove},
            onSelectionChanged:
                _busy ? null : (set) => _setSideToMove(set.first),
          ),
          const SizedBox(height: 6),
          Text(
            fen.sideToMoveLabel,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Recognized FEN'),
          SelectableText(
            recognition.fen!,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
          ),
        ] else ...[
          const SectionLabel('Board recognition'),
          Text(
            'No FEN — board not found or image could not be read.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.error,
                ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          recognition.note,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: recognition.success
                    ? scheme.onSurfaceVariant
                    : scheme.error,
              ),
        ),
      ],
      const SizedBox(height: 18),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Speak best move'),
        subtitle: const Text('Turn off to keep analysis on-screen only'),
        value: _speakBestMove,
        onChanged: _busy ? null : (v) => setState(() => _speakBestMove = v),
      ),
      const SizedBox(height: 4),
      Semantics(
        button: true,
        enabled: !_busy && boardReady,
        label: _busy ? 'Analyzing' : 'Analyze for side to move',
        child: FilledButton.icon(
          onPressed: _busy || !boardReady ? null : () => _analyze(),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _busy
                ? const SizedBox(
                    key: ValueKey('busy'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    key: ValueKey('idle'),
                    Icons.psychology_alt_outlined,
                  ),
          ),
          label: Text(_busy ? 'Analyzing…' : 'Analyze for side to move'),
        ),
      ),
      const SizedBox(height: 14),
      AnalysisStatusBanner(
        busy: _busy && engine == null,
        error: _error,
        hasBoard: boardReady,
        hasResult: engine != null,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: engine == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AnalysisResults(engine: engine),
              ),
      ),
    ];

    final secondaryColumn = <Widget>[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Live watch (training / review)'),
        subtitle: const Text(
          'When on, each Capture frame / Photos pick / ReplayKit '
          'frame is recognized → FEN → auto-analyzed for the selected '
          'side to move. Set Side to move yourself (vision does not '
          'read clocks). Not for live online engine assist.',
        ),
        value: _liveWatch,
        onChanged: _busy ? null : (v) => setState(() => _liveWatch = v),
      ),
      const SizedBox(height: 8),
      ScreenCaptureSection(
        supported: _replayKit.isSupported,
        watching: _screenCaptureWatch,
        broadcast: _broadcast,
        onWatchChanged: _busy ? null : _setScreenCaptureWatch,
      ),
      const SizedBox(height: 28),
      Text(
        fairPlayDetail,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
      ),
    ];

    return Scaffold(
      body: Container(
        decoration: ChesshihiTheme.atmosphere(scheme),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              isWide ? 28 : 20,
              12,
              isWide ? 28 : 20,
              32,
            ),
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 11,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: primaryColumn,
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 9,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Watch & capture',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Secondary tools for training review. '
                            'Primary analyze flow stays on the left.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          ...secondaryColumn,
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                ...primaryColumn,
                const SizedBox(height: 28),
                Divider(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                const SizedBox(height: 16),
                Text(
                  'Watch & capture',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ReplayKit and live watch sit below the main analyze path.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                ...secondaryColumn,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
