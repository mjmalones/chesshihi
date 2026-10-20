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
import 'vision/board_recognizer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChesshihiApp());
}

class ChesshihiApp extends StatelessWidget {
  const ChesshihiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1B4D3E),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Chesshihi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: base,
        useMaterial3: true,
      ),
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
  final _frameIngest = FrameIngest();
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
  ];

  FenPosition? get _fen =>
      _recognition == null ? null : FenPosition(_recognition!.fen);

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
      _error = null;
    });
  }

  Future<void> _loadSample(
    ({String path, String label}) sample,
  ) async {
    setState(() {
      _imageLabel = sample.label;
      _preview = AssetImage(sample.path);
    });
    _setRecognition(_recognizer.recognize(assetPath: sample.path));
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

  /// Apply current side-to-move to a freshly recognized (often stub) FEN.
  RecognitionResult _withCurrentSide(RecognitionResult result) {
    final side = _fen?.sideToMove;
    if (side == null) return result;
    final nextFen = FenPosition(result.fen).withSideToMove(side);
    if (nextFen == result.fen) return result;
    return RecognitionResult(
      fen: nextFen,
      source: result.source,
      note: result.note,
    );
  }

  Future<void> _ingestLocalFile(File file, {required String label}) async {
    setState(() {
      _imageLabel = label;
      _preview = FileImage(file);
    });
    final recognized = _withCurrentSide(
      _frameIngest.recognizeFile(file, label: label),
    );
    _setRecognition(recognized);
    if (_liveWatch || _screenCaptureWatch) {
      await _analyze();
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
    if (current == null) return;
    final nextFen = FenPosition(current.fen).withSideToMove(side);
    if (nextFen == current.fen) return;
    _setRecognition(
      RecognitionResult(
        fen: nextFen,
        source: current.source,
        note: '${current.note} Side to move set manually to '
            '${side == 'w' ? 'White' : 'Black'} — Stockfish will analyze for that side.',
      ),
    );
  }

  Future<void> _analyze({bool? speakOverride}) async {
    final recognition = _recognition;
    if (recognition == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _engineResult = null;
    });

    try {
      final result = await _engine.analyze(recognition.fen);
      if (!mounted) return;
      setState(() => _engineResult = result);

      final shouldSpeak = speakOverride ?? _speakBestMove;
      final announcement = result.stub
          ? 'Stub best move for ${FenPosition(result.fen).sideToMoveLabel}: '
              '${result.bestMoveSpoken}. ${result.explanation}'
          : 'Best move for ${FenPosition(result.fen).sideToMoveLabel}: '
              '${result.bestMoveSpoken}. ${result.explanation}';

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

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              scheme.primaryContainer.withValues(alpha: 0.35),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _FairPlayBanner(scheme: scheme),
              const SizedBox(height: 20),
              Text(
                'Chesshihi',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: scheme.primary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Board → FEN → Stockfish → optional spoken best move',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              if (_preview != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image(image: _preview!, fit: BoxFit.contain),
                  ),
                ),
              if (_imageLabel != null) ...[
                const SizedBox(height: 8),
                Text(
                  _imageLabel!,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
              const SizedBox(height: 16),
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
                    onPressed: _busy
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Photos'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Capture frame'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (recognition != null && fen != null) ...[
                _SectionLabel('Side to move'),
                Text(
                  'Stockfish only analyzes the side in the FEN. '
                  'Vision cannot see clocks yet — set this if the turn looks wrong.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'w', label: Text('White'), icon: Icon(Icons.circle_outlined)),
                    ButtonSegment(value: 'b', label: Text('Black'), icon: Icon(Icons.circle)),
                  ],
                  selected: {fen.sideToMove},
                  onSelectionChanged: _busy
                      ? null
                      : (set) => _setSideToMove(set.first),
                ),
                const SizedBox(height: 6),
                Text(
                  fen.sideToMoveLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                _SectionLabel('Recognized FEN'),
                SelectableText(
                  recognition.fen,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  recognition.note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: recognition.isStub
                            ? scheme.tertiary
                            : scheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Speak best move'),
                subtitle: const Text('Turn off to keep analysis on-screen only'),
                value: _speakBestMove,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _speakBestMove = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Live watch (training / review)'),
                subtitle: const Text(
                  'When on, each Capture frame / Photos pick / ReplayKit '
                  'frame auto-analyzes for the selected side to move. '
                  'Vision is still stubbed — set Side to move yourself. '
                  'Not for live online engine assist.',
                ),
                value: _liveWatch,
                onChanged:
                    _busy ? null : (v) => setState(() => _liveWatch = v),
              ),
              const SizedBox(height: 8),
              _ScreenCaptureSection(
                scheme: scheme,
                supported: _replayKit.isSupported,
                watching: _screenCaptureWatch,
                broadcast: _broadcast,
                onWatchChanged: _busy ? null : _setScreenCaptureWatch,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || recognition == null ? null : () => _analyze(),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.psychology_alt_outlined),
                label: Text(_busy ? 'Analyzing…' : 'Analyze for side to move'),
              ),
              if (engine != null) ...[
                const SizedBox(height: 20),
                _SectionLabel('Best move (${FenPosition(engine.fen).sideToMoveLabel})'),
                Text(
                  engine.bestMoveUci,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                ),
                Text(
                  engine.bestMoveSpoken,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Eval: ${engine.scoreLabel}'
                  '${engine.depth != null ? ' · depth ${engine.depth}' : ''}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                ),
                const SizedBox(height: 10),
                _SectionLabel('Why this move'),
                Text(
                  engine.explanation.isEmpty ? engine.detail : engine.explanation,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (engine.stub)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      engine.detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.tertiary,
                          ),
                    ),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 28),
              Text(
                fairPlayDetail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenCaptureSection extends StatelessWidget {
  const _ScreenCaptureSection({
    required this.scheme,
    required this.supported,
    required this.watching,
    required this.broadcast,
    required this.onWatchChanged,
  });

  final ColorScheme scheme;
  final bool supported;
  final bool watching;
  final BroadcastState broadcast;
  final ValueChanged<bool>? onWatchChanged;

  @override
  Widget build(BuildContext context) {
    final statusLine = !supported
        ? 'ReplayKit is iOS-only — build/sideload an IPA to use screen capture.'
        : !broadcast.appGroupReady && broadcast.available
            ? 'App Group not ready — Karl’s signer must include '
                'group.com.chesshihi.chesshihi on app + extension.'
            : broadcast.status.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Screen capture (ReplayKit)'),
        Text(
          'You must start Screen Recording from Control Center and select '
          'Chesshihi. Chesshihi cannot silently capture Chess.com (or any '
          'other app). For analysis, training, and accessibility only — '
          'not live online engine assist.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '1. Open Control Center → Screen Recording (long-press).\n'
          '2. Choose Chesshihi as the broadcast app, then Start.\n'
          '3. Switch to the board you want to review.\n'
          '4. Return here with “Watch broadcast frames” on.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Watch broadcast frames'),
          subtitle: Text(
            watching
                ? 'Polling App Group for new frames (throttled; identical '
                    'frames skipped). Enables Live watch.'
                : 'Off — start a Chesshihi broadcast from Control Center first.',
          ),
          value: watching,
          onChanged: supported ? onWatchChanged : null,
        ),
        Text(
          'Status: $statusLine'
          '${broadcast.frameCount > 0 ? ' · frames ${broadcast.frameCount}' : ''}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: broadcast.isBroadcasting
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _FairPlayBanner extends StatelessWidget {
  const _FairPlayBanner({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: fairPlayBanner,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.gavel_outlined, color: scheme.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fairPlayBanner,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onErrorContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
