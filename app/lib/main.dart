import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';

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

  String? _imageLabel;
  ImageProvider? _preview;
  RecognitionResult? _recognition;
  EngineResult? _engineResult;
  String? _error;
  bool _busy = false;

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

  @override
  void initState() {
    super.initState();
    _loadSample(_samples.first);
  }

  @override
  void dispose() {
    _engine.dispose();
    _announcer.dispose();
    super.dispose();
  }

  Future<void> _loadSample(
    ({String path, String label}) sample,
  ) async {
    setState(() {
      _imageLabel = sample.label;
      _preview = AssetImage(sample.path);
      _recognition = _recognizer.recognize(assetPath: sample.path);
      _engineResult = null;
      _error = null;
    });
  }

  Future<void> _pickFromPhotos() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() {
        _imageLabel = 'Photos: ${file.name}';
        _preview = FileImage(File(file.path));
        _recognition = _recognizer.recognize(pickedLabel: file.name);
        _engineResult = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open Photos: $e');
    }
  }

  Future<void> _analyzeAndSpeak() async {
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

      final announcement = result.stub
          ? 'Stub best move: ${result.bestMoveSpoken}'
          : 'Best move: ${result.bestMoveSpoken}';
      await SemanticsService.sendAnnouncement(
        View.of(context),
        announcement,
        TextDirection.ltr,
      );
      await _announcer.speak(announcement);
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
                'Board screenshot → FEN → Stockfish → spoken best move',
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
                    onPressed: _busy ? null : _pickFromPhotos,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Pick from Photos'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (recognition != null) ...[
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
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy || recognition == null
                    ? null
                    : _analyzeAndSpeak,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.psychology_alt_outlined),
                label: Text(_busy ? 'Analyzing…' : 'Analyze & speak'),
              ),
              if (engine != null) ...[
                const SizedBox(height: 20),
                _SectionLabel('Best move'),
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
