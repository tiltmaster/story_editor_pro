import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Stable identifiers understood by the native AR implementations.
abstract final class NativeArLensIds {
  static const String none = 'none';
  static const String classicGlasses = 'glasses_classic';
  static const String aviatorGold = 'glasses_aviator_gold';
  static const String visorCyan = 'glasses_visor_cyan';

  static const Set<String> glasses = <String>{
    classicGlasses,
    aviatorGold,
    visorCyan,
  };
}

enum NativeArRuntimeState { disabled, preparing, ready, active, unavailable }

enum NativeArEventType { state, tracking, error, unknown }

@immutable
class NativeArCapabilities {
  const NativeArCapabilities({
    required this.available,
    this.faceTracking = false,
    this.preview = false,
    this.recording = false,
    this.lensIds = const <String>{},
  });

  const NativeArCapabilities.unavailable()
    : available = false,
      faceTracking = false,
      preview = false,
      recording = false,
      lensIds = const <String>{};

  final bool available;
  final bool faceTracking;
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
    this.failure,
  });

  final NativeArEventType type;
  final NativeArRuntimeState state;
  final bool? faceTracked;
  final NativeArFailure? failure;

  factory NativeArEvent.fromMap(Map<Object?, Object?> map) {
    final typeName = map['type']?.toString();
    final stateName = map['state']?.toString();
    final code = map['code']?.toString();
    final message = map['message']?.toString();
    return NativeArEvent(
      type: switch (typeName) {
        'state' => NativeArEventType.state,
        'tracking' => NativeArEventType.tracking,
        'error' => NativeArEventType.error,
        _ => NativeArEventType.unknown,
      },
      state: NativeArController.parseState(stateName),
      faceTracked: map['faceTracked'] as bool?,
      failure: code == null && message == null
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
/// Camera frames and landmarks never cross this channel. Call [prepare] only
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

  Stream<NativeArEvent> get events => _events.stream;
  NativeArCapabilities get capabilities => _capabilities;
  NativeArRuntimeState get state => _state;
  NativeArFailure? get lastFailure => _lastFailure;

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
          lensIds: NativeArLensIds.glasses,
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
      await _methodChannel.invokeMethod<void>('setEnabled', <String, Object?>{
        'enabled': enabled,
      });
      if (!enabled) _emitState(NativeArRuntimeState.disabled);
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

  Future<bool> setLens(String lensId, {double intensity = 1.0}) async {
    _checkNotDisposed();
    final normalizedIntensity = intensity.clamp(0.0, 1.0);
    if (!_capabilities.supportsLens(lensId) && lensId != NativeArLensIds.none) {
      _recordFailure('unsupported_lens', 'The selected AR lens is unavailable');
      return false;
    }
    if (!_capabilities.available) return false;
    try {
      await _methodChannel.invokeMethod<void>('setLens', <String, Object?>{
        'lensId': lensId,
        'intensity': normalizedIntensity,
      });
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
        _state = event.state;
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
