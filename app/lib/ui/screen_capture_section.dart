import 'package:flutter/material.dart';

import '../capture/replaykit_service.dart';
import 'section_label.dart';

class ScreenCaptureSection extends StatelessWidget {
  const ScreenCaptureSection({
    super.key,
    required this.supported,
    required this.watching,
    required this.broadcast,
    required this.onWatchChanged,
  });

  final bool supported;
  final bool watching;
  final BroadcastState broadcast;
  final ValueChanged<bool>? onWatchChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLine = !supported
        ? 'ReplayKit is iOS-only — build/sideload an IPA to use screen capture.'
        : !broadcast.appGroupReady && broadcast.available
            ? 'App Group not ready — Karl’s signer must include '
                'group.com.chesshihi.chesshihi on app + extension.'
            : broadcast.status.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Screen capture (ReplayKit)'),
        Text(
          'You must start Screen Recording from Control Center and select '
          'Chesshihi. Chesshihi cannot silently capture Chess.com (or any '
          'other app). For analysis, training, and accessibility only — '
          'not live online engine assist.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
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
                height: 1.45,
              ),
        ),
        const SizedBox(height: 4),
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
