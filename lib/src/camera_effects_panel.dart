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
    required this.onChanged,
    this.arEvents,
    this.onClose,
    this.locationSession,
  });

  final CameraEffects effects;
  final String lookId;
  final double lookStrength;
  final Set<String> supportedFaceLenses;
  final bool supportsPlaces;
  final bool supportsBeauty;
  final bool supportsFaceBeauty;
  final Stream<NativeArEvent>? arEvents;
  final VoidCallback? onClose;
  final CameraPlaceSession? locationSession;
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
  int _tab = 0;
  int _beautyControl = 0;
  bool _locating = false;
  String? _locationError;
  String _requestedPlaceStyle = 'postcard';
  int _locationRevision = 0;

  String t(String english, String arabic) =>
      Localizations.localeOf(context).languageCode == 'ar' ? arabic : english;

  @override
  void didUpdateWidget(CameraEffectsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effects != widget.effects) _effects = widget.effects;
    if (oldWidget.lookId != widget.lookId) _look = widget.lookId;
    if (oldWidget.lookStrength != widget.lookStrength) {
      _strength = widget.lookStrength;
    }
  }

  void _change({CameraEffects? effects, String? look, double? strength}) {
    setState(() {
      _effects = effects ?? _effects;
      _look = look ?? _look;
      _strength = strength ?? _strength;
    });
    widget.onChanged(_effects, _look, _strength);
  }

  void _selectTab(int tab) {
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
    if (tab == 3 && widget.supportsPlaces) {
      _requestedPlaceStyle = _effects.placeStyle == 'none'
          ? 'postcard'
          : _effects.placeStyle;
      _locate();
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
    if (style == 'none') {
      _change(
        effects: _effects.copyWith(placeStyle: 'none', placeName: ''),
      );
    } else {
      _locate();
    }
  }

  void _reset() {
    _requestedPlaceStyle = 'none';
    _locationError = null;
    _change(effects: const CameraEffects(), look: 'none', strength: .85);
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
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (index, label) in [
                            t('Looks', 'ألوان'),
                            t('Beauty', 'جمال'),
                            t('Lenses', 'عدسات'),
                            t('Places', 'أماكن'),
                          ].indexed)
                            Semantics(
                              selected: _tab == index,
                              button: true,
                              child: InkWell(
                                key: ValueKey('effects-tab-$index'),
                                onTap: () => _selectTab(index),
                                child: Container(
                                  height: 44,
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
                    onPressed: _reset,
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
            const SizedBox(height: 8),
            SizedBox(
              height: 91,
              child: switch (_tab) {
                0 => _looks(),
                1 => _beauty(),
                2 => _lenses(),
                _ => _places(),
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: switch (_tab) {
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
                  _ => _placeStatus(),
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
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    children: cards,
  );

  Widget _looks() => _row([
    for (final look in StoryEditorFilters.presets)
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
                    onPressed: () => setState(() => _beautyControl = index),
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
                child: _statusText(
                  !widget.supportsFaceBeauty
                      ? t(
                          'Face shaping unavailable on this camera',
                          'تعديل الوجه غير متاح في هذه الكاميرا',
                        )
                      : _beautyControl == 1
                      ? t(
                          'Adjust eye size · Follows your face',
                          'اضبط حجم العينين · يتتبع وجهك',
                        )
                      : t(
                          'Define your cheeks · Follows your face',
                          'حدّد ملامح الخدّين · يتتبع وجهك',
                        ),
                ),
              ),
      ),
    ],
  );

  Widget _lenses() => _row([
    for (final (id, label, icon, colors) in [
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
    ])
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
          : event?.faceTracked == false && _effects.faceLens != 'none'
          ? t('Bring your face into view', 'ضع وجهك أمام الكاميرا')
          : t('Face tracking · Photo & video', 'تتبع الوجه · صور وفيديو');
      return _statusText(
        message,
        error: event?.failure != null && _effects.faceLens != 'none',
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
    child: InkWell(
      key: ValueKey('effects-card-$id'),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap();
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
