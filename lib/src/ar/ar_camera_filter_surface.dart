import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/story_editor_filters.dart';
import 'ar_filter.dart';
import 'ar_filter_capabilities.dart';
import 'ar_filter_catalog.dart';
import 'ar_filter_controller.dart';

/// Composites a selected AR effect over any camera preview without accessing
/// the underlying frame bytes. Shader failure and low-end devices fall back to
/// the package's existing one-pass [ColorFiltered] presets.
class ArCameraFilterSurface extends StatefulWidget {
  const ArCameraFilterSurface({
    super.key,
    required this.controller,
    required this.child,
    this.capabilities,
    this.clipBehavior = Clip.hardEdge,
    this.shaderAsset,
    this.preloadedProgram,
    this.imageFilterFactory,
  });

  final ArCameraFilterController controller;
  final Widget child;
  final ArCameraCapabilities? capabilities;
  final Clip clipBehavior;

  /// Asset override for package tests or custom package embedding.
  final String? shaderAsset;

  /// Optional prewarmed program. Supplying this removes shader asset I/O from
  /// the first filter selection and is recommended on latency-sensitive flows.
  final ui.FragmentProgram? preloadedProgram;

  /// Renderer hook for embedders and deterministic tests. Defaults to
  /// [ui.ImageFilter.shader].
  final ui.ImageFilter Function(ui.FragmentShader shader)? imageFilterFactory;

  @override
  State<ArCameraFilterSurface> createState() => _ArCameraFilterSurfaceState();
}

class _ArCameraFilterSurfaceState extends State<ArCameraFilterSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  ui.FragmentShader? _shader;
  bool _shaderLoading = false;
  bool _shaderUnavailable = false;
  bool _rendererFailureScheduled = false;
  bool _appActive = true;

  ArCameraCapabilities get _capabilities =>
      widget.capabilities ?? ArCameraCapabilities.current();

  ResolvedArCameraFilter get _resolved => ArCameraCapabilityPolicy.resolve(
    widget.controller.selectedFilter,
    _shaderUnavailable
        ? ArCameraCapabilities(
            platform: _capabilities.platform,
            quality: _capabilities.quality,
            fragmentShadersAvailable: false,
            reduceMotion: _capabilities.reduceMotion,
            liveEffectsEnabled: _capabilities.liveEffectsEnabled,
          )
        : _capabilities,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_selectionChanged);
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _shader = widget.preloadedProgram?.fragmentShader();
    _configureRenderer();
  }

  @override
  void didUpdateWidget(covariant ArCameraFilterSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_selectionChanged);
      widget.controller.addListener(_selectionChanged);
    }
    if (oldWidget.preloadedProgram != widget.preloadedProgram &&
        widget.preloadedProgram != null) {
      _shader?.dispose();
      _shader = widget.preloadedProgram!.fragmentShader();
    }
    if (oldWidget.capabilities != widget.capabilities) _configureRenderer();
  }

  void _selectionChanged() {
    if (!mounted) return;
    _configureRenderer();
    setState(() {});
  }

  void _configureRenderer() {
    final resolved = _resolved;
    if (resolved.useShader && _shader == null) _loadShader();
    if (_appActive && resolved.animate) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.stop();
    }
  }

  Future<void> _loadShader() async {
    if (_shaderLoading || _shaderUnavailable || _shader != null) return;
    _shaderLoading = true;
    try {
      ui.FragmentProgram? program;
      Object? lastError;
      final candidateAssets = widget.shaderAsset == null
          ? const <String>[
              ArCameraFilterCatalog.shaderAsset,
              ArCameraFilterCatalog.packageRootShaderAsset,
            ]
          : <String>[widget.shaderAsset!];
      for (final asset in candidateAssets) {
        try {
          program = await ui.FragmentProgram.fromAsset(asset);
          break;
        } catch (error) {
          lastError = error;
        }
      }
      if (program == null) {
        throw lastError ?? StateError('AR shader unavailable');
      }
      if (!mounted) return;
      _shader = program.fragmentShader();
    } catch (_) {
      // Expected on unsupported renderers. Keep camera usable via color matrix.
      _shaderUnavailable = true;
    } finally {
      _shaderLoading = false;
      if (mounted) setState(_configureRenderer);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _configureRenderer();
  }

  Widget _fallback(ArCameraFilter filter) {
    if (filter.id == ArCameraFilterId.none) {
      return KeyedSubtree(
        key: const ValueKey<String>('ar-filter-surface-original'),
        child: widget.child,
      );
    }
    return ColorFiltered(
      key: const ValueKey<String>('ar-filter-surface-fallback'),
      colorFilter: StoryEditorFilters.colorFilter(
        filter.fallbackPresetId,
        widget.controller.intensity,
      ),
      child: widget.child,
    );
  }

  Widget _buildFrame() {
    final resolved = _resolved;
    if (!resolved.useShader || _shader == null) {
      return _fallback(resolved.filter);
    }
    return Stack(
      key: const ValueKey<String>('ar-filter-surface-shader'),
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                if (!size.isFinite || size.isEmpty) {
                  return const SizedBox.shrink(
                    key: ValueKey<String>('ar-filter-surface-empty'),
                  );
                }
                _shader!
                  ..setFloat(0, size.width)
                  ..setFloat(1, size.height)
                  ..setFloat(2, _clock.value * 12)
                  ..setFloat(3, widget.controller.intensity)
                  ..setFloat(4, resolved.filter.shaderMode.toDouble())
                  ..setFloat(
                    5,
                    resolved.quality == ArCameraQuality.high ? 1 : 0,
                  );
                ui.ImageFilter imageFilter;
                try {
                  imageFilter =
                      (widget.imageFilterFactory ?? ui.ImageFilter.shader)(
                        _shader!,
                      );
                } on UnsupportedError {
                  _scheduleRendererFallback();
                  return const SizedBox.shrink();
                }
                return BackdropFilter(
                  key: const ValueKey<String>('ar-filter-surface-backdrop'),
                  filter: imageFilter,
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      clipBehavior: widget.clipBehavior,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, child) => _buildFrame(),
      ),
    ),
  );

  void _scheduleRendererFallback() {
    if (_rendererFailureScheduled || _shaderUnavailable) return;
    _rendererFailureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rendererFailureScheduled = false;
      _shaderUnavailable = true;
      _clock.stop();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_selectionChanged);
    _clock.dispose();
    _shader?.dispose();
    super.dispose();
  }
}
