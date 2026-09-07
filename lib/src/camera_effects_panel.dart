import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'camera_effects.dart';
import 'config/story_editor_filters.dart';
import 'config/story_editor_config.dart';
import 'native_ar_controller.dart';

/// Compact controls embedded in the camera; preview and shutter remain usable.
class CameraEffectsPanel extends StatefulWidget {
  const CameraEffectsPanel({
    super.key,
    required this.effects,
    required this.lookId,
    required this.lookStrength,
    required this.supportedFaceLenses,
    required this.supportsPlaces,
    required this.supportsBeauty,
    this.supportsFaceBeauty = false,
    this.supportsBackground = false,
    this.backgroundReady = false,
    required this.onChanged,
    this.arEvents,
    this.onClose,
    this.locationSession,
    this.uiSession,
  });

  final CameraEffects effects;
  final String lookId;
  final double lookStrength;
  final Set<String> supportedFaceLenses;
  final bool supportsPlaces;
  final bool supportsBeauty;
  final bool supportsFaceBeauty;
  final bool supportsBackground;
  final bool backgroundReady;
  final Stream<NativeArEvent>? arEvents;
  final VoidCallback? onClose;
  final CameraPlaceSession? locationSession;
  final CameraEffectsUiSession? uiSession;
  final void Function(CameraEffects effects, String lookId, double strength)
  onChanged;

  @override
  State<CameraEffectsPanel> createState() => _CameraEffectsPanelState();
}

class _CameraEffectsPanelState extends State<CameraEffectsPanel> {
  static const _accent = Colors.white;
  late CameraEffects _effects = widget.effects;
  late String _look = widget.lookId;
  late double _strength = widget.lookStrength;
  late final CameraPlaceSession _locationSession =
      widget.locationSession ?? CameraPlaceSession();
  late final CameraEffectsUiSession _ui =
      widget.uiSession ?? CameraEffectsUiSession();
  late int _tab = _ui.category.clamp(0, 4);
  late int _beautyControl = _ui.beautyControl.clamp(0, 2);
  late final Map<int, ScrollController> _scrollers;
  final List<GlobalKey> _tabKeys = List.generate(5, (_) => GlobalKey());
  (CameraEffects, String, double)? _undo;
  String? _notice;
  bool _locating = false;
  String? _locationError;
  late String _requestedPlaceStyle =
      _ui.requestedPlaceStyle ??
      (_effects.placeStyle == 'none' ? 'postcard' : _effects.placeStyle);
  int _locationRevision = 0;
  late bool _backgroundReady = widget.backgroundReady;
  bool _backgroundFailed = false;
  bool? _lastFaceTracked;
  StreamSubscription<NativeArEvent>? _backgroundEvents;

  String t(String english, String arabic) =>
      Localizations.localeOf(context).languageCode == 'ar' ? arabic : english;

  @override
  void initState() {
    super.initState();
    _listenForBackground();
    _scrollers = {
      for (final tab in [0, 2, 3, 4])
        tab: ScrollController(initialScrollOffset: _ui.scrollOffsets[tab] ?? 0),
    };
    for (final entry in _scrollers.entries) {
      entry.value.addListener(() {
        if (entry.value.hasClients) {
          _ui.scrollOffsets[entry.key] = entry.value.offset;
        }
      });
    }
    final favoritesWereLoaded = _ui.favoritesLoaded;
    _ui.loadFavorites().then((_) {
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _revealSelection(force: !favoritesWereLoaded),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealSelection();
      if (mounted &&
          _tab == 3 &&
          _requestedPlaceStyle != 'none' &&
          _effects.placeName.isEmpty) {
        _locate();
      }
    });
  }

  @override
  void dispose() {
    _backgroundEvents?.cancel();
    for (final controller in _scrollers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _listenForBackground() {
    _backgroundEvents?.cancel();
    _backgroundEvents = widget.arEvents?.listen((event) {
      if (!mounted) return;
      final tracked =
          event.faceTracked ?? (event.facePose != null ? true : null);
      if (tracked != null && tracked != _lastFaceTracked) {
        setState(() => _lastFaceTracked = tracked);
      }
      if (_effects.backgroundStyle == 0) return;
      if (event.backgroundReady != null || event.failure != null) {
        setState(() {
          if (event.backgroundReady != null) {
            _backgroundReady = event.backgroundReady!;
            _backgroundFailed = false;
          }
          if (event.failure != null) _backgroundFailed = true;
        });
      }
    });
  }

  void _revealSelection({bool force = false}) {
    if (!mounted) return;
    final tabContext = _tabKeys[_tab].currentContext;
    if (tabContext != null) {
      Scrollable.ensureVisible(
        tabContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
    final controller = _scrollers[_tab];
    if (controller == null || !controller.hasClients) return;
    final ids = switch (_tab) {
      0 => _orderedLooks.map((look) => look.id).toList(),
      2 => _orderedLensIds,
      3 => ['none', 'postcard', 'editorial', 'stamp'],
      _ => ['0', '1', '2', '3', '4'],
    };
    final selected = switch (_tab) {
      0 => _look,
      2 => _effects.faceLens,
      3 => _effects.placeStyle,
      _ => _effects.backgroundStyle.toString(),
    };
    if (!force && _ui.selectedIds[_tab] == selected) return;
    _ui.selectedIds[_tab] = selected;
    final index = ids.indexOf(selected);
    if (index < 0) return;
    final leading = index * 82.0;
    final trailing = leading + 82;
    final view = controller.position.viewportDimension;
    if (leading < controller.offset || trailing > controller.offset + view) {
      controller.jumpTo(
        (leading - (view - 82) / 2).clamp(
          0.0,
          controller.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(CameraEffectsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arEvents != widget.arEvents) _listenForBackground();
    if (oldWidget.backgroundReady != widget.backgroundReady) {
      _backgroundReady = widget.backgroundReady;
    }
    if (oldWidget.effects != widget.effects) _effects = widget.effects;
    if (oldWidget.lookId != widget.lookId) _look = widget.lookId;
    if (oldWidget.lookStrength != widget.lookStrength) {
      _strength = widget.lookStrength;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelection());
    if (!oldWidget.supportsPlaces &&
        widget.supportsPlaces &&
        _tab == 3 &&
        _requestedPlaceStyle != 'none') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _locate();
      });
    }
  }

  void _change({CameraEffects? effects, String? look, double? strength}) {
    setState(() {
      _undo = null;
      _notice = null;
      if (effects != null &&
          effects.backgroundStyle != _effects.backgroundStyle) {
        _backgroundReady = false;
        _backgroundFailed = false;
      }
      _effects = effects ?? _effects;
      _look = look ?? _look;
      _strength = strength ?? _strength;
      _ui.selectedIds[_tab] = switch (_tab) {
        0 => _look,
        2 => _effects.faceLens,
        3 => _effects.placeStyle,
        _ => _effects.backgroundStyle.toString(),
      };
    });
    widget.onChanged(_effects, _look, _strength);
  }

  void _selectTab(int tab) {
    HapticFeedback.selectionClick();
    setState(() {
      _tab = tab;
      _ui.category = tab;
      _notice = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelection());
    if (tab == 3 && widget.supportsPlaces) {
      _requestedPlaceStyle =
          _ui.requestedPlaceStyle ??
          (_effects.placeStyle == 'none' ? 'postcard' : _effects.placeStyle);
      _ui.requestedPlaceStyle = _requestedPlaceStyle;
      if (_requestedPlaceStyle != 'none') _locate();
    }
  }

  Future<void> _locate() async {
    if (_locating || !widget.supportsPlaces) return;
    final revision = ++_locationRevision;
    final locale = Localizations.localeOf(context).toString();
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final name = await _locationSession.resolve(localeIdentifier: locale);
      if (!mounted || revision != _locationRevision) return;
      if (_requestedPlaceStyle != 'none') {
        _change(
          effects: _effects.copyWith(
            placeName: name,
            placeStyle: _requestedPlaceStyle,
          ),
        );
      }
    } catch (_) {
      if (mounted && revision == _locationRevision) {
        setState(
          () => _locationError = t(
            'Allow location access and turn on GPS, then retry.',
            'اسمح بالوصول للموقع وفعّل GPS، ثم أعد المحاولة.',
          ),
        );
      }
    } finally {
      if (mounted && revision == _locationRevision) {
        setState(() => _locating = false);
      }
    }
  }

  void _selectPlace(String style) {
    _requestedPlaceStyle = style;
    _ui.requestedPlaceStyle = style;
    if (style == 'none') {
      _change(
        effects: _effects.copyWith(placeStyle: 'none', placeName: ''),
      );
    } else {
      _locate();
    }
  }

  void _reset() {
    final previous = (_effects, _look, _strength);
    _requestedPlaceStyle = 'none';
    _ui.requestedPlaceStyle = 'none';
    _locationError = null;
    _change(effects: const CameraEffects(), look: 'none', strength: .85);
    setState(() => _undo = previous);
  }

  Widget _undoReset() => Row(
    children: [
      Expanded(child: _statusText(t('Effects cleared', 'تم مسح التأثيرات'))),
      TextButton(
        onPressed: () {
          final previous = _undo;
          if (previous == null) return;
          _requestedPlaceStyle = previous.$1.placeStyle;
          _ui.requestedPlaceStyle = _requestedPlaceStyle;
          _change(
            effects: previous.$1,
            look: previous.$2,
            strength: previous.$3,
          );
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _revealSelection(),
          );
        },
        child: Text(t('Undo', 'تراجع')),
      ),
    ],
  );

  Future<void> _toggleFavorite(String kind, String id) async {
    HapticFeedback.selectionClick();
    await _ui.toggleFavorite(kind, id);
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealSelection(force: true),
    );
  }

  Widget _favoriteButton(String kind, String id) {
    final favorite = _ui.isFavorite(kind, id);
    return IconButton(
      key: ValueKey('favorite-$kind-$id'),
      tooltip: favorite
          ? t('Remove from favorites', 'إزالة من المفضلة')
          : t('Save to favorites', 'حفظ في المفضلة'),
      onPressed: id == 'none' ? null : () => _toggleFavorite(kind, id),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        favorite ? Icons.star_rounded : Icons.star_border_rounded,
        size: 21,
        color: favorite ? const Color(0xFFFFDB82) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: _accent,
        secondary: _accent,
        surface: Color(0xFF151517),
        onPrimary: Colors.black,
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 2,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
    ),
    child: Material(
      color: const Color(0xD91A1A1D),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 192,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (index, label) in [
                            (2, t('Lenses', 'عدسات')),
                            (0, t('Looks', 'ألوان')),
                            (1, t('Beauty', 'جمال')),
                            (3, t('Places', 'أماكن')),
                            (4, t('Background', 'الخلفية')),
                          ])
                            Semantics(
                              key: _tabKeys[index],
                              selected: _tab == index,
                              button: true,
                              child: InkWell(
                                key: ValueKey('effects-tab-$index'),
                                onTap: () => _selectTab(index),
                                child: Container(
                                  height: 48,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: _tab == index
                                            ? Colors.white
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _tab == index
                                          ? Colors.white
                                          : Colors.white60,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t('Reset effects', 'إعادة ضبط التأثيرات'),
                    onPressed: _effects.layerCount > 0 || _look != 'none'
                        ? _reset
                        : null,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.restart_alt_rounded, size: 19),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: t('Close effects', 'إغلاق التأثيرات'),
                      onPressed: widget.onClose,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 91,
              child: switch (_tab) {
                0 => _looks(),
                1 => _beauty(),
                2 => _lenses(),
                3 => _places(),
                _ => _backgrounds(),
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _undo != null
                    ? _undoReset()
                    : _notice != null
                    ? _statusText(_notice!)
                    : switch (_tab) {
                        0 => _slider(
                          t('Intensity', 'قوة التأثير'),
                          _strength,
                          widget.supportsBeauty && _look != 'none'
                              ? (value) => _change(strength: value)
                              : null,
                        ),
                        1 => _slider(
                          switch (_beautyControl) {
                            1 => t('Eye size', 'حجم العينين'),
                            2 => t('Contour', 'تحديد الوجه'),
                            _ => t('Smoothing', 'النعومة'),
                          },
                          switch (_beautyControl) {
                            1 => _effects.beautyEyes,
                            2 => _effects.beautySlim,
                            _ => _effects.beauty,
                          },
                          (_beautyControl == 0
                                  ? widget.supportsBeauty
                                  : widget.supportsFaceBeauty)
                              ? (value) => _change(
                                  effects: switch (_beautyControl) {
                                    1 => _effects.copyWith(beautyEyes: value),
                                    2 => _effects.copyWith(beautySlim: value),
                                    _ => _effects.copyWith(beauty: value),
                                  },
                                )
                              : null,
                        ),
                        2 => _lensStatus(),
                        3 => _placeStatus(),
                        _ => _backgroundStatus(),
                      },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(List<Widget> cards) => ListView(
    key: ValueKey('effects-choices-$_tab'),
    controller: _scrollers[_tab],
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    children: cards,
  );

  Widget _looks() => _row([
    for (final look in _orderedLooks)
      _card(
        id: look.id,
        label: context.storyEditorConfig.strings.filterNameForPreset(
          look.id,
          languageCode: Localizations.localeOf(context).languageCode,
        ),
        icon: StoryEditorFilters.thumbnailIcon(look.id),
        colors: _lookColors(look.id),
        selected: _look == look.id,
        onTap: widget.supportsBeauty || look.id == 'none'
            ? () => _change(look: look.id)
            : null,
      ),
  ]);

  Widget _beauty() => Column(
    children: [
      SizedBox(
        height: 38,
        child: Row(
          children: [
            const SizedBox(width: 12),
            for (final (index, label) in [
              t('Skin', 'البشرة'),
              t('Eyes', 'العينان'),
              t('Contour', 'تحديد الوجه'),
            ].indexed)
              Expanded(
                child: Semantics(
                  selected: _beautyControl == index,
                  child: TextButton(
                    key: ValueKey('beauty-control-$index'),
                    onPressed: () => setState(() {
                      _beautyControl = index;
                      _ui.beautyControl = index;
                    }),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: _beautyControl == index
                          ? Colors.white12
                          : Colors.transparent,
                      foregroundColor: _beautyControl == index
                          ? Colors.white
                          : Colors.white60,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 12),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: _beautyControl == 0
            ? ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final (value, label) in [
                    (0.0, t('Off', 'إيقاف')),
                    (.35, t('Natural', 'طبيعي')),
                    (.65, t('Smooth', 'ناعم')),
                    (1.0, t('Studio', 'استوديو')),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(
                          label,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: (_effects.beauty - value).abs() < .02,
                        onSelected: widget.supportsBeauty
                            ? (_) => _change(
                                effects: value == 0
                                    ? _effects.copyWith(
                                        beauty: 0,
                                        beautyEyes: 0,
                                        beautySlim: 0,
                                      )
                                    : _effects.copyWith(beauty: value),
                              )
                            : null,
                        showCheckmark: false,
                        selectedColor: Colors.white,
                        labelStyle: TextStyle(
                          color: (_effects.beauty - value).abs() < .02
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                    ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: StreamBuilder<NativeArEvent>(
                  stream: widget.arEvents,
                  builder: (context, snapshot) =>
                      _statusText(_faceBeautyHint(snapshot.data)),
                ),
              ),
      ),
    ],
  );

  String _faceBeautyHint(NativeArEvent? event) {
    if (!widget.supportsFaceBeauty) {
      return t(
        'Face shaping unavailable on this camera',
        'تعديل الوجه غير متاح في هذه الكاميرا',
      );
    }
    if (event?.failure != null) {
      return t(
        'Face adjustment unavailable. Try another effect.',
        'تعديل الوجه غير متاح. جرّب تأثيراً آخر.',
      );
    }
    if (event?.state == NativeArRuntimeState.preparing) {
      return t('Preparing face tracking…', 'جارٍ تجهيز تتبع الوجه…');
    }
    final amount = _beautyControl == 1
        ? _effects.beautyEyes
        : _effects.beautySlim;
    if (amount > 0 && (event?.faceTracked ?? _lastFaceTracked) != true) {
      return t('Bring your face into view', 'ضع وجهك أمام الكاميرا');
    }
    return _beautyControl == 1
        ? t(
            'Adjust eye size · Follows your face',
            'اضبط حجم العينين · يتتبع وجهك',
          )
        : t(
            'Define your cheeks · Follows your face',
            'حدّد ملامح الخدّين · يتتبع وجهك',
          );
  }

  List<(String, String, IconData, List<Color>)> get _lensChoices => [
    (
      'none',
      t('None', 'بدون'),
      Icons.block_rounded,
      [const Color(0xFF42424C), const Color(0xFF232329)],
    ),
    (
      NativeArLensIds.celestial,
      t('Stardust', 'غبار النجوم'),
      Icons.auto_awesome,
      [const Color(0xFF67548D), const Color(0xFFCBA572)],
    ),
    (
      NativeArLensIds.heartHalo,
      t('Heart halo', 'هالة قلوب'),
      Icons.favorite,
      [const Color(0xFFAD4569), const Color(0xFFE9A9B6)],
    ),
    (
      NativeArLensIds.freckles,
      t('Sun freckles', 'نمش الشمس'),
      Icons.wb_sunny_outlined,
      [const Color(0xFF906039), const Color(0xFFEAC99C)],
    ),
    (
      NativeArLensIds.neonContour,
      t('Neon contour', 'تحديد نيون'),
      Icons.face_6_outlined,
      [const Color(0xFF365DAB), const Color(0xFFD873CE)],
    ),
    (
      NativeArLensIds.butterflies,
      t('Butterflies', 'فراشات'),
      Icons.emoji_nature_outlined,
      [const Color(0xFF6659AD), const Color(0xFFCAA5F1)],
    ),
  ];

  List<(String, String, IconData, List<Color>)> get _orderedLensChoices {
    final choices = _lensChoices;
    return [
      ...choices.where((choice) => choice.$1 == 'none'),
      ...choices.where(
        (choice) => choice.$1 != 'none' && _ui.isFavorite('lens', choice.$1),
      ),
      ...choices.where(
        (choice) => choice.$1 != 'none' && !_ui.isFavorite('lens', choice.$1),
      ),
    ];
  }

  List<String> get _orderedLensIds =>
      _orderedLensChoices.map((choice) => choice.$1).toList();

  List<StoryFilterPreset> get _orderedLooks => [
    ...StoryEditorFilters.presets.where((look) => look.id == 'none'),
    ...StoryEditorFilters.presets.where(
      (look) => look.id != 'none' && _ui.isFavorite('look', look.id),
    ),
    ...StoryEditorFilters.presets.where(
      (look) => look.id != 'none' && !_ui.isFavorite('look', look.id),
    ),
  ];

  Widget _lenses() => _row([
    for (final (id, label, icon, colors) in _orderedLensChoices)
      _card(
        id: id,
        label: label,
        icon: icon,
        colors: colors,
        selected: _effects.faceLens == id,
        onTap: id == 'none' || widget.supportedFaceLenses.contains(id)
            ? () => _change(effects: _effects.copyWith(faceLens: id))
            : null,
      ),
  ]);

  Widget _backgrounds() => _row([
    for (final (style, label, icon, colors) in [
      (
        0,
        t('Off', 'إيقاف'),
        Icons.block_rounded,
        [const Color(0xFF42424C), const Color(0xFF232329)],
      ),
      (
        1,
        t('Studio', 'استوديو'),
        Icons.portrait_outlined,
        [const Color(0xFF738191), const Color(0xFFDFDAD2)],
      ),
      (
        2,
        t('Sunset', 'غروب'),
        Icons.wb_twilight_rounded,
        [const Color(0xFFB278A2), const Color(0xFFF4B47E)],
      ),
      (
        3,
        t('Night', 'ليل'),
        Icons.nights_stay_outlined,
        [const Color(0xFF252D65), const Color(0xFF867BB4)],
      ),
      (
        4,
        t('Blur', 'ضبابية'),
        Icons.blur_on_rounded,
        [const Color(0xFF548178), const Color(0xFFBDCCC3)],
      ),
    ])
      _card(
        id: 'background-$style',
        label: label,
        icon: icon,
        colors: colors,
        selected: _effects.backgroundStyle == style,
        onTap: widget.supportsBackground || style == 0
            ? () => _change(effects: _effects.copyWith(backgroundStyle: style))
            : null,
      ),
  ]);

  Widget _backgroundStatus() {
    if (!widget.supportsBackground) {
      return _statusText(
        t(
          'Background effects unavailable on this camera',
          'تأثيرات الخلفية غير متاحة في هذه الكاميرا',
        ),
      );
    }
    if (_effects.backgroundStyle == 0) {
      return _statusText(
        t(
          'Keep your surroundings, or choose a new background',
          'احتفظ بالمشهد المحيط أو اختر خلفية جديدة',
        ),
      );
    }
    return _statusText(
      _backgroundFailed
          ? t(
              'Choose Off, then a background to retry.',
              'اختر إيقاف، ثم خلفية للمحاولة مجدداً.',
            )
          : !_backgroundReady
          ? t('Preparing your background…', 'جارٍ تجهيز الخلفية…')
          : t(
              'Your subject stays in front · Photo & video',
              'يبقى الشخص في المقدمة · صور وفيديو',
            ),
      error: _backgroundFailed,
    );
  }

  Widget _places() => _row([
    for (final (id, label, icon, colors) in [
      (
        'none',
        t('Off', 'إيقاف'),
        Icons.block_rounded,
        [const Color(0xFF42424C), const Color(0xFF232329)],
      ),
      (
        'postcard',
        t('Postcard', 'بطاقة بريدية'),
        Icons.photo_outlined,
        [const Color(0xFF86765C), const Color(0xFFDBD0B6)],
      ),
      (
        'editorial',
        t('Editorial', 'مجلة'),
        Icons.view_agenda_outlined,
        [const Color(0xFF454750), const Color(0xFF9EA1AB)],
      ),
      (
        'stamp',
        t('Passport', 'جواز سفر'),
        Icons.public,
        [const Color(0xFF496853), const Color(0xFFA8BE94)],
      ),
    ])
      _card(
        id: 'place-$id',
        label: label,
        icon: icon,
        colors: colors,
        selected: _effects.placeStyle == id,
        onTap: widget.supportsPlaces ? () => _selectPlace(id) : null,
      ),
  ]);

  Widget _lensStatus() => StreamBuilder<NativeArEvent>(
    stream: widget.arEvents,
    builder: (context, snapshot) {
      final event = snapshot.data;
      final message = event?.failure != null && _effects.faceLens != 'none'
          ? t('Lens unavailable. Try another.', 'العدسة غير متاحة. جرّب أخرى.')
          : event?.state == NativeArRuntimeState.preparing
          ? t('Preparing your lens…', 'جارٍ تجهيز العدسة…')
          : (event?.faceTracked ?? _lastFaceTracked) == false &&
                _effects.faceLens != 'none'
          ? t('Bring your face into view', 'ضع وجهك أمام الكاميرا')
          : (event?.faceTracked ?? _lastFaceTracked) == true &&
                _effects.faceLens == NativeArLensIds.heartHalo
          ? t('Open your mouth', 'افتح فمك')
          : (event?.faceTracked ?? _lastFaceTracked) == true &&
                _effects.faceLens == NativeArLensIds.butterflies
          ? t('Wink to flutter', 'اغمز لتحريك الفراشات')
          : t('Face tracking · Photo & video', 'تتبع الوجه · صور وفيديو');
      return Row(
        children: [
          Expanded(
            child: _statusText(
              _effects.faceLens == 'none'
                  ? t('Tap a lens · Swipe for more', 'اختر عدسة · اسحب للمزيد')
                  : message,
              error: event?.failure != null && _effects.faceLens != 'none',
            ),
          ),
          _favoriteButton('lens', _effects.faceLens),
        ],
      );
    },
  );

  Widget _placeStatus() {
    if (!widget.supportsPlaces) {
      return _statusText(
        t('Location frames unavailable', 'إطارات الموقع غير متاحة'),
      );
    }
    if (_locating) {
      return Row(
        children: [
          const SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statusText(t('Finding your city…', 'جارٍ تحديد مدينتك…')),
          ),
        ],
      );
    }
    if (_locationError != null) {
      return Row(
        children: [
          Expanded(child: _statusText(_locationError!, error: true)),
          TextButton(
            onPressed: _locate,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              t('Retry', 'إعادة المحاولة'),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.location_on_outlined, size: 15, color: Colors.white70),
        const SizedBox(width: 6),
        Expanded(
          child: _statusText(
            _effects.placeName.isNotEmpty
                ? _effects.placeName
                : t('Your current city · GPS', 'مدينتك الحالية · GPS'),
          ),
        ),
      ],
    );
  }

  Widget _statusText(String text, {bool error = false}) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: error ? const Color(0xFFFFBCBC) : Colors.white70,
      ),
    ),
  );

  Widget _slider(String label, double value, ValueChanged<double>? onChanged) =>
      Row(
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 5,
            child: Slider(
              value: value.clamp(0, 1),
              onChanged: onChanged,
              semanticFormatterCallback: _percent,
            ),
          ),
          Text(
            _percent(value),
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          if (_tab == 0) _favoriteButton('look', _look),
        ],
      );

  String _percent(double value) => NumberFormat.percentPattern(
    Localizations.localeOf(context).languageCode,
  ).format(value);

  List<Color> _lookColors(String id) {
    final params = StoryEditorFilters.resolve(id, 1);
    return [
      Color.fromRGBO(
        (155 * params.red).clamp(0, 255).round(),
        (145 * params.green).clamp(0, 255).round(),
        (165 * params.blue).clamp(0, 255).round(),
        1,
      ),
      Color.fromRGBO(
        (80 * params.red).clamp(0, 255).round(),
        (100 * params.green).clamp(0, 255).round(),
        (105 * params.blue).clamp(0, 255).round(),
        1,
      ),
    ];
  }

  Widget _card({
    required String id,
    required String label,
    required IconData icon,
    required List<Color> colors,
    required bool selected,
    VoidCallback? onTap,
  }) => Semantics(
    button: true,
    selected: selected,
    enabled: onTap != null,
    label: label,
    hint: onTap == null
        ? t('Unavailable on this camera', 'غير متاح في هذه الكاميرا')
        : null,
    child: InkWell(
      key: ValueKey('effects-card-$id'),
      onTap: () {
        if (onTap == null) {
          setState(
            () => _notice = t(
              'This effect is unavailable on this camera.',
              'هذا التأثير غير متاح في هذه الكاميرا.',
            ),
          );
        } else {
          HapticFeedback.selectionClick();
          onTap();
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 82,
        child: Opacity(
          opacity: onTap == null ? .35 : 1,
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                  ),
                  child: Icon(icon, size: 23, color: Colors.white),
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
