import 'place_sticker_artwork.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'face_beauty.dart';

/// Stable identifiers understood by the native AR implementations.
abstract final class NativeArLensIds {
  static const String none = 'none';
  static const String classicGlasses = 'glasses_classic';
  static const String analogTape = 'vhs1993';
  static const String goldenBloom = 'daytime';
  static const String studioGlow = 'timefocus';
  static const String desertLuxe = 'kuwaitgold';
  static const String filmAura = 'retrodate';
  static const String celestial = 'face_celestial';
  static const String heartHalo = 'face_hearts';
  static const String freckles = 'face_freckles';
  static const String neonContour = 'face_neon';
  static const String butterflies = 'face_butterflies';

  static const Set<String> glasses = <String>{};
  static const Set<String> face = <String>{
    celestial,
    heartHalo,
    freckles,
    neonContour,
    butterflies,
  };
  static const Set<String> composed = <String>{
    analogTape,
    goldenBloom,
    studioGlow,
    desertLuxe,
    filmAura,
  };
  static const Set<String> all = <String>{...face, ...composed};
}

enum NativeArRuntimeState { disabled, preparing, ready, active, unavailable }

enum NativeArEventType {
  state,
  tracking,
  pose,
  recordingStarted,
  background,
  error,
  unknown,
}

@immutable
class NativeArCapabilities {
  const NativeArCapabilities({
    required this.available,
    this.faceTracking = false,
    this.backgrounds = false,
    this.preview = false,
    this.recording = false,
    this.lensIds = const <String>{},
  });

  const NativeArCapabilities.unavailable()
    : available = false,
      faceTracking = false,
      backgrounds = false,
      preview = false,
      recording = false,
      lensIds = const <String>{};

  final bool available;
  final bool faceTracking;
  final bool backgrounds;
  final bool preview;
  final bool recording;
  final Set<String> lensIds;

  bool supportsLens(String lensId) =>
      available && (lensIds.isEmpty || lensIds.contains(lensId));

  factory NativeArCapabilities.fromMap(Map<Object?, Object?> map) {
    final lenses = map['lensIds'] ?? map['lenses'];
    return NativeArCapabilities(
      available: map['available'] == true || map['supported'] == true,
      faceTracking: map['faceTracking'] == true,
      backgrounds: map['backgrounds'] == true,
      preview: map['preview'] == true,
      recording: map['recording'] == true,
      lensIds: lenses is Iterable
          ? lenses.map((value) => value.toString()).toSet()
          : const <String>{},
    );
  }
}

@immutable
class NativeArFailure {
  const NativeArFailure({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;
}

@immutable
class NativeArEvent {
  const NativeArEvent({
    required this.type,
    required this.state,
    this.faceTracked,
    this.faceTrackingReady,
    this.backgroundReady,
    this.message,
    this.failure,
    this.facePose,
    this.timestampMs,
    this.isPhoto = false,
  });

  final NativeArEventType type;
  final NativeArRuntimeState state;
  final bool? faceTracked;
  final bool? faceTrackingReady;
  final bool? backgroundReady;
  final String? message;
  final NativeArFailure? failure;
  final FaceBeautyPose? facePose;
  final double? timestampMs;
  final bool isPhoto;

  factory NativeArEvent.fromMap(Map<Object?, Object?> map) {
    final typeName = map['type']?.toString();
    final stateName = map['state']?.toString();
    final code = map['code']?.toString();
    final message = map['message']?.toString();
    return NativeArEvent(
      type: switch (typeName) {
        'state' => NativeArEventType.state,
        'tracking' => NativeArEventType.tracking,
        'pose' => NativeArEventType.pose,
        'recordingStarted' => NativeArEventType.recordingStarted,
        'background' => NativeArEventType.background,
        'error' => NativeArEventType.error,
        _ => NativeArEventType.unknown,
      },
      state: NativeArController.parseState(stateName),
      faceTracked: map['faceTracked'] as bool?,
      faceTrackingReady: map['faceReady'] as bool?,
      backgroundReady: map['backgroundReady'] as bool?,
      message: message,
      facePose: FaceBeautyPose.fromMap(map['facePose']),
      timestampMs: (map['timestampMs'] as num?)?.toDouble(),
      isPhoto: map['isPhoto'] == true,
      failure: code == null && (message == null || typeName == 'background')
          ? null
          : NativeArFailure(
              code: code ?? 'native_error',
              message: message ?? 'Native AR error',
            ),
    );
  }
}

/// Typed, low-frequency control plane for the native AR renderer.
///
/// Camera frames never cross this channel. Four eye coordinates are emitted
/// at most 15 times per second when face shaping is active. Call [prepare] only
/// after the native camera preview has produced its first frame so AR cannot
/// delay camera startup.
class NativeArController {
  NativeArController({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel('story_editor_pro/ar'),
      _eventChannel =
          eventChannel ?? const EventChannel('story_editor_pro/ar_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final StreamController<NativeArEvent> _events =
      StreamController<NativeArEvent>.broadcast(sync: true);

  StreamSubscription<Object?>? _nativeEvents;
  NativeArCapabilities _capabilities = const NativeArCapabilities.unavailable();
  NativeArRuntimeState _state = NativeArRuntimeState.disabled;
  NativeArFailure? _lastFailure;
  Future<NativeArCapabilities>? _capabilitiesRequest;
  Future<void>? _prepareRequest;
  bool _disposed = false;
  bool _faceTrackingReady = false;
  bool _backgroundReady = false;
  int _backgroundStyle = 0;
  String _backgroundPath = '';

  Stream<NativeArEvent> get events => _events.stream;
  NativeArCapabilities get capabilities => _capabilities;
  NativeArRuntimeState get state => _state;
  NativeArFailure? get lastFailure => _lastFailure;
  bool get faceTrackingReady => _faceTrackingReady;
  bool get backgroundReady => _backgroundReady;

  Future<NativeArCapabilities> getCapabilities() {
    _checkNotDisposed();
    return _capabilitiesRequest ??= _loadCapabilities();
  }

  Future<NativeArCapabilities> _loadCapabilities() async {
    try {
      final result = await _methodChannel.invokeMethod<Object?>(
        'getCapabilities',
      );
      if (result is Map) {
        _capabilities = NativeArCapabilities.fromMap(result);
      } else if (result == true) {
        _capabilities = const NativeArCapabilities(
          available: true,
          faceTracking: true,
          preview: true,
          recording: true,
          lensIds: NativeArLensIds.all,
        );
      } else {
        _capabilities = const NativeArCapabilities.unavailable();
      }
      if (!_capabilities.available) {
        _emitState(NativeArRuntimeState.unavailable);
      }
    } on MissingPluginException catch (error) {
      _markUnavailable('missing_plugin', error.message ?? 'AR is unavailable');
    } on PlatformException catch (error) {
      _markUnavailable(
        error.code,
        error.message ?? 'AR is unavailable',
        error.details,
      );
    }
    return _capabilities;
  }

  /// Starts native AR preparation. This is idempotent and must not be awaited
  /// by the camera first-frame path.
  Future<void> prepare() {
    _checkNotDisposed();
    return _prepareRequest ??= _prepare();
  }

  Future<void> _prepare() async {
    final supported = await getCapabilities();
    if (!supported.available) return;
    _listenToNativeEvents();
    _emitState(NativeArRuntimeState.preparing);
    try {
      await _methodChannel.invokeMethod<void>('prepare');
    } on MissingPluginException catch (error) {
      _markUnavailable('missing_plugin', error.message ?? 'AR is unavailable');
    } on PlatformException catch (error) {
      _recordFailure(
        error.code,
        error.message ?? 'AR preparation failed',
        details: error.details,
      );
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    _checkNotDisposed();
    if (!_capabilities.available) return false;
    try {
      _listenToNativeEvents();
      final response = await _methodChannel.invokeMethod<Object?>(
        'setEnabled',
        <String, Object?>{'enabled': enabled},
      );
      if (response is Map && response['state'] is String) {
        _faceTrackingReady = response['faceReady'] == true;
        _emitState(parseState(response['state'] as String));
      }
      if (!enabled) {
        _backgroundReady = false;
        _emitState(NativeArRuntimeState.disabled);
      }
      return true;
    } on MissingPluginException catch (error) {
      _markUnavailable('missing_plugin', error.message ?? 'AR is unavailable');
    } on PlatformException catch (error) {
      _recordFailure(
        error.code,
        error.message ?? 'Could not change AR state',
        details: error.details,
      );
    }
    return false;
  }

  Future<void> awaitFrame() async {
    await _methodChannel
        .invokeMethod<bool>('awaitFrame')
        .timeout(const Duration(seconds: 3));
  }

  Future<void> restartBackground() async {
    _backgroundReady = false;
    await _methodChannel.invokeMethod<void>('restartBackground');
  }

  String _placeArtworkKey = '';

  Future<void> updatePlaceSticker({
    required double x,
    required double y,
    required double scale,
  }) async {
    _checkNotDisposed();
    if (!x.isFinite || !y.isFinite || !scale.isFinite) {
      throw ArgumentError('Sticker transform must be finite');
    }
    await _methodChannel.invokeMethod<void>('updatePlaceSticker', {
      'x': x,
      'y': y,
      'scale': scale,
    });
  }

  Future<bool> setLens(
    String lensId, {
    double intensity = 1.0,
    String? languageCode,
    String? countryCode,
    bool mirrorOutput = false,
    String compositionId = 'none',
    String placeStyle = 'none',
    String placeName = '',
    int placeVariant = 0,
    double placeX = .5,
    double placeY = .68,
    double placeScale = 1,
    double beautyEyes = 0,
    double beautySlim = 0,
    int backgroundStyle = 0,
    String backgroundPath = '',
    bool backgroundIsVideo = false,
  }) async {
    _checkNotDisposed();
    if (!intensity.isFinite) throw ArgumentError.value(intensity, 'intensity');
    final normalizedIntensity = intensity.clamp(0.0, 1.0);
    if (!_capabilities.supportsLens(lensId) && lensId != NativeArLensIds.none) {
      _recordFailure('unsupported_lens', 'The selected AR lens is unavailable');
      return false;
    }
    if (!_capabilities.available) return false;
    try {
      _listenToNativeEvents();
      final artworkKey =
          '$placeStyle|$placeName|$placeVariant|$languageCode|${DateTime.now().toIso8601String().substring(0, 10)}';
      final artwork =
          placeStyle != 'none' &&
              placeName.isNotEmpty &&
              artworkKey != _placeArtworkKey
          ? await renderPlaceSticker(
              style: placeStyle,
              name: placeName,
              variant: placeVariant,
              language: languageCode ?? 'en',
            )
          : null;
      final style = backgroundStyle.clamp(0, 5);
      if (_backgroundStyle != style || _backgroundPath != backgroundPath) {
        _backgroundReady = false;
      }
      _backgroundPath = backgroundPath;
      _backgroundStyle = style;
      await _methodChannel.invokeMethod<void>('setLens', <String, Object?>{
        'lensId': lensId,
        'intensity': normalizedIntensity,
        if (languageCode != null) 'languageCode': languageCode,
        if (countryCode != null) 'countryCode': countryCode,
        'mirrorOutput': mirrorOutput,
        'compositionId': compositionId,
        'placeStyle': placeStyle,
        'placeName': String.fromCharCodes(placeName.trim().runes.take(64)),
        if (placeStyle != 'none') ...{
          'placeX': placeX,
          'placeY': placeY,
          'placeScale': placeScale,
          if (artwork != null) 'placeArtwork': artwork,
        },
        'beautyEyes': beautyEyes.isFinite ? beautyEyes.clamp(0, 1) : 0,
        'beautySlim': beautySlim.isFinite ? beautySlim.clamp(0, 1) : 0,
        'backgroundStyle': style,
        'backgroundPath': backgroundPath,
        'backgroundIsVideo': backgroundIsVideo,
      });
      if (placeStyle != 'none') _placeArtworkKey = artworkKey;
      return true;
    } on MissingPluginException catch (error) {
      _markUnavailable('missing_plugin', error.message ?? 'AR is unavailable');
    } on PlatformException catch (error) {
      _recordFailure(
        error.code,
        error.message ?? 'Could not select AR lens',
        details: error.details,
      );
    }
    return false;
  }

  void _listenToNativeEvents() {
    if (_nativeEvents != null) return;
    _nativeEvents = _eventChannel.receiveBroadcastStream().listen(
      (Object? raw) {
        if (_disposed || raw is! Map) return;
        final event = NativeArEvent.fromMap(raw);
        if (event.backgroundReady != null) {
          _backgroundReady = event.backgroundReady!;
        }
        if (event.faceTrackingReady != null) {
          _faceTrackingReady = event.faceTrackingReady!;
        }
        // Pose/recording metadata may omit state. It must not disable an
        // active tracker simply because parsing defaults to disabled.
        if (raw['state'] is String) _state = event.state;
        if (event.failure != null) _lastFailure = event.failure;
        _events.add(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (error is MissingPluginException) {
          _markUnavailable(
            'missing_plugin',
            error.message ?? 'AR is unavailable',
          );
        } else if (error is PlatformException) {
          _recordFailure(
            error.code,
            error.message ?? 'Native AR event error',
            details: error.details,
          );
        } else {
          _recordFailure('event_error', error.toString());
        }
      },
    );
  }

  void _emitState(NativeArRuntimeState next) {
    if (_disposed) return;
    _state = next;
    _events.add(NativeArEvent(type: NativeArEventType.state, state: next));
  }

  void _markUnavailable(String code, String message, [Object? details]) {
    _capabilities = const NativeArCapabilities.unavailable();
    _recordFailure(
      code,
      message,
      details: details,
      state: NativeArRuntimeState.unavailable,
    );
  }

  void _recordFailure(
    String code,
    String message, {
    Object? details,
    NativeArRuntimeState? state,
  }) {
    if (_disposed) return;
    _lastFailure = NativeArFailure(
      code: code,
      message: message,
      details: details,
    );
    _state = state ?? _state;
    _events.add(
      NativeArEvent(
        type: NativeArEventType.error,
        state: _state,
        failure: _lastFailure,
      ),
    );
  }

  static NativeArRuntimeState parseState(String? value) => switch (value) {
    'preparing' => NativeArRuntimeState.preparing,
    'ready' => NativeArRuntimeState.ready,
    'active' => NativeArRuntimeState.active,
    'unavailable' => NativeArRuntimeState.unavailable,
    _ => NativeArRuntimeState.disabled,
  };

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _nativeEvents?.cancel();
    } catch (_) {
      // Event teardown must not prevent the native pipeline from disposing.
    }
    try {
      await _methodChannel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      // Unsupported platforms are an expected no-op.
    } on PlatformException {
      // Disposal is best-effort and must not break camera teardown.
    }
    try {
      await _events.close();
    } catch (_) {
      // The controller is already terminal; cleanup remains best effort.
    }
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('NativeArController has been disposed');
  }
}
