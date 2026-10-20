import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Host-side view of the ReplayKit Broadcast Upload Extension.
///
/// The extension writes the latest JPEG + status into the App Group shared
/// container; this service polls that state over a MethodChannel.
///
/// Honest limit: the user must start Screen Recording from Control Center and
/// pick **Chesshihi**. There is no silent Chess.com capture.
class ReplayKitService {
  ReplayKitService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('chesshihi/replaykit');

  final MethodChannel _channel;

  /// Whether this platform can talk to a ReplayKit extension at all.
  bool get isSupported => !kIsWeb && Platform.isIOS;

  Future<BroadcastState> getState() async {
    if (!isSupported) {
      return BroadcastState.unsupported;
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getState');
      if (raw == null) return BroadcastState.unsupported;
      return BroadcastState.fromMap(raw);
    } on MissingPluginException {
      return BroadcastState.unsupported;
    } on PlatformException {
      return BroadcastState.unsupported;
    }
  }

  Future<void> clearState() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('clearState');
    } on MissingPluginException {
      // Host channel not registered (e.g. unit tests).
    } on PlatformException {
      // Ignore — clearing is best-effort.
    }
  }
}

/// Snapshot of broadcast + latest frame metadata from the App Group.
class BroadcastState {
  const BroadcastState({
    required this.available,
    required this.appGroupReady,
    required this.status,
    this.framePath,
    this.updatedAtMs,
    this.contentHash,
    this.frameCount = 0,
    this.appGroupId,
  });

  static const unsupported = BroadcastState(
    available: false,
    appGroupReady: false,
    status: BroadcastStatus.idle,
  );

  final bool available;
  final bool appGroupReady;
  final BroadcastStatus status;
  final String? framePath;
  final int? updatedAtMs;
  final String? contentHash;
  final int frameCount;
  final String? appGroupId;

  bool get isBroadcasting =>
      status == BroadcastStatus.started || status == BroadcastStatus.paused;

  bool get hasFrame =>
      framePath != null && framePath!.isNotEmpty && File(framePath!).existsSync();

  factory BroadcastState.fromMap(Map<String, dynamic> map) {
    return BroadcastState(
      available: map['available'] == true,
      appGroupReady: map['appGroupReady'] == true,
      status: BroadcastStatus.parse(map['status']?.toString()),
      framePath: map['framePath'] as String?,
      updatedAtMs: _asInt(map['updatedAtMs']),
      contentHash: map['contentHash'] as String?,
      frameCount: _asInt(map['frameCount']) ?? 0,
      appGroupId: map['appGroupId'] as String?,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

enum BroadcastStatus {
  idle,
  started,
  paused,
  finished,
  error;

  static BroadcastStatus parse(String? raw) {
    switch (raw) {
      case 'started':
        return BroadcastStatus.started;
      case 'paused':
        return BroadcastStatus.paused;
      case 'finished':
        return BroadcastStatus.finished;
      case 'error':
        return BroadcastStatus.error;
      default:
        return BroadcastStatus.idle;
    }
  }

  String get label {
    switch (this) {
      case BroadcastStatus.idle:
        return 'Not broadcasting';
      case BroadcastStatus.started:
        return 'Broadcasting — frames arriving';
      case BroadcastStatus.paused:
        return 'Broadcast paused';
      case BroadcastStatus.finished:
        return 'Broadcast finished';
      case BroadcastStatus.error:
        return 'Broadcast error (check App Group signing)';
    }
  }
}

/// Pure helpers for host-side frame dedupe / throttle decisions.
class FrameIngestPolicy {
  const FrameIngestPolicy({
    this.minInterval = const Duration(milliseconds: 500),
  });

  final Duration minInterval;

  /// Returns true when [candidateHash] should be analyzed.
  bool shouldIngest({
    required String? candidateHash,
    required String? lastHash,
    required DateTime? lastIngestAt,
    required DateTime now,
  }) {
    if (candidateHash == null || candidateHash.isEmpty) return false;
    if (candidateHash == lastHash) return false;
    if (lastIngestAt != null && now.difference(lastIngestAt) < minInterval) {
      return false;
    }
    return true;
  }
}
