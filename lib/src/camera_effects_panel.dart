import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'camera_effects.dart';
import 'config/story_editor_filters.dart';
import 'config/story_editor_config.dart';
import 'native_ar_controller.dart';

/// Live editing surface; the camera remains visible above the sheet.
class CameraEffectsPanel extends StatefulWidget {
  const CameraEffectsPanel({
    super.key,
    required this.effects,
    required this.lookId,
    required this.lookStrength,
    required this.supportedFaceLenses,
    required this.supportsPlaces,
    required this.supportsBeauty,
    required this.onChanged,
    this.arEvents,
  });

  final CameraEffects effects;
  final String lookId;
  final double lookStrength;
  final Set<String> supportedFaceLenses;
  final bool supportsPlaces;
  final bool supportsBeauty;
  final Stream<NativeArEvent>? arEvents;
  final void Function(CameraEffects effects, String lookId, double strength)
  onChanged;

  @override
  State<CameraEffectsPanel> createState() => _CameraEffectsPanelState();
}

class _CameraEffectsPanelState extends State<CameraEffectsPanel> {
  static const _accent = Color(0xFFE6F5AE);
  late CameraEffects _effects = widget.effects;
  late String _look = widget.lookId;
  late double _strength = widget.lookStrength;
  late final TextEditingController _place = TextEditingController(
    text: _effects.placeName,
  );
  int _tab = 0;
  bool _locating = false;
  String? _locationError;

  String t(String english, String arabic) =>
      Localizations.localeOf(context).languageCode == 'ar' ? arabic : english;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  void _change({CameraEffects? effects, String? look, double? strength}) {
    setState(() {
      _effects = effects ?? _effects;
      _look = look ?? _look;
      _strength = strength ?? _strength;
    });
    widget.onChanged(_effects, _look, _strength);
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final locale = Localizations.localeOf(context);
      final name = await resolveCameraPlace(
        localeIdentifier: locale.toString(),
      );
      if (!mounted) return;
      _place.text = name;
      _change(
        effects: _effects.copyWith(
          placeName: name,
          placeStyle: _effects.placeStyle == 'none'
              ? 'postcard'
              : _effects.placeStyle,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationError = t(
            'Location is unavailable. Check permission and location services, or type a place.',
            'الموقع غير متاح. تحقق من الإذن وخدمات الموقع أو اكتب اسم المكان.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final desiredHeight = screenHeight * 0.48;
    final panelHeight = (desiredHeight < 360 ? 360.0 : desiredHeight).clamp(
      0.0,
      screenHeight * 0.84,
    );
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accent,
          secondaryContainer: _accent,
          onSecondaryContainer: Color(0xFF1D2511),
          surface: Color(0xFF141419),
          onPrimary: Color(0xFF1D2511),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: panelHeight + MediaQuery.viewInsetsOf(context).bottom,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              0,
              22,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('Make it yours', 'على ذوقك'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _place.clear();
                        _change(
                          effects: const CameraEffects(),
                          look: 'none',
                          strength: 0.85,
                        );
                      },
                      child: Text(t('Reset', 'إعادة ضبط')),
                    ),
                    IconButton(
                      tooltip: t('Done', 'تم'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check_rounded, color: _accent),
                    ),
                  ],
                ),
                Text(
                  t(
                    'Layer your look. Keep your character.',
                    'اجمع تأثيراتك واحتفظ بشخصيتك.',
                  ),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final (index, label) in [
                      t('Looks', 'ألوان'),
                      t('Beauty', 'جمال'),
                      t('Lenses', 'عدسات'),
                      t('Places', 'أماكن'),
                    ].indexed)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 5),
                          child: Semantics(
                            selected: _tab == index,
                            button: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _tab = index);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: _tab == index
                                      ? _accent
                                      : const Color(0xFF24242C),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _tab == index
                                        ? const Color(0xFF1D2511)
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: switch (_tab) {
                      0 => _looks(),
                      1 => _beauty(),
                      2 => _lenses(),
                      _ => _places(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _looks() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _slider(
        t('Intensity', 'قوة التأثير'),
        _strength,
        (v) => _change(strength: v),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final look in StoryEditorFilters.presets)
            ChoiceChip(
              label: Text(
                context.storyEditorConfig.strings.filterNameForPreset(
                  look.id,
                  languageCode: Localizations.localeOf(context).languageCode,
                ),
              ),
              selected: _look == look.id,
              onSelected: widget.supportsBeauty || look.id == 'none'
                  ? (_) => _change(look: look.id)
                  : null,
              avatar: Icon(StoryEditorFilters.thumbnailIcon(look.id), size: 16),
            ),
        ],
      ),
    ],
  );

  Widget _beauty() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t('A softer finish. Still you.', 'لمسة أنعم، بطبيعتك.'),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        widget.supportsBeauty
            ? t(
                'Smooth fine texture while keeping edges and natural skin tone.',
                'نعومة خفيفة تحافظ على التفاصيل ولون البشرة الطبيعي.',
              )
            : t(
                'Beauty requires a supported camera renderer.',
                'التجميل يتطلب معالج كاميرا مدعوم.',
              ),
        style: const TextStyle(
          fontSize: 12,
          height: 1.5,
          color: Colors.white54,
        ),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 8,
        children: [
          for (final (value, label) in [
            (0.0, t('Off', 'إيقاف')),
            (0.28, t('Natural', 'طبيعي')),
            (0.5, t('Soft', 'ناعم')),
            (0.75, t('Polished', 'مصقول')),
          ])
            ChoiceChip(
              label: Text(label),
              selected: (_effects.beauty - value).abs() < 0.02,
              onSelected: widget.supportsBeauty
                  ? (_) => _change(effects: _effects.copyWith(beauty: value))
                  : null,
            ),
        ],
      ),
      _slider(
        t('Smoothing', 'النعومة'),
        _effects.beauty,
        widget.supportsBeauty
            ? (v) => _change(effects: _effects.copyWith(beauty: v))
            : null,
      ),
    ],
  );

  Widget _lenses() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t('Moves with you', 'يتحرك معك'),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (id, label, icon, colors) in [
            (
              'none',
              t('None', 'بدون'),
              Icons.block,
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
              NativeArLensIds.classicGlasses,
              t('Classic', 'كلاسيك'),
              Icons.face_retouching_natural,
              [const Color(0xFF3A5358), const Color(0xFF89A5A3)],
            ),
          ])
            _tile(
              id,
              label,
              icon,
              colors,
              _effects.faceLens == id,
              id == 'none' || widget.supportedFaceLenses.contains(id)
                  ? () => _change(effects: _effects.copyWith(faceLens: id))
                  : null,
            ),
        ],
      ),
      const SizedBox(height: 12),
      StreamBuilder<NativeArEvent>(
        stream: widget.arEvents,
        builder: (context, snapshot) {
          final event = snapshot.data;
          final message = event?.failure != null
              ? t(
                  'Lens unavailable. Choose another effect.',
                  'العدسة غير متاحة. اختر تأثيراً آخر.',
                )
              : event?.state == NativeArRuntimeState.preparing
              ? t('Preparing your lens…', 'جارٍ تجهيز العدسة…')
              : event?.faceTracked == false && _effects.faceLens != 'none'
              ? t('Bring your face into view', 'ضع وجهك أمام الكاميرا')
              : t(
                  'Face tracking • Saved in photos and videos',
                  'تتبع الوجه • يُحفظ في الصور والفيديو',
                );
          return Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: event?.failure == null
                  ? Colors.white54
                  : const Color(0xFFFFBCBC),
            ),
          );
        },
      ),
    ],
  );

  Widget _places() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _place,
        maxLength: 64,
        enabled: widget.supportsPlaces,
        textInputAction: TextInputAction.done,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: t('Place name', 'اسم المكان'),
          counterText: '',
          prefixIcon: const Icon(Icons.place_outlined),
          filled: true,
          fillColor: const Color(0xFF24242C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) => _change(
          effects: _effects.copyWith(
            placeName: v,
            placeStyle: _effects.placeStyle == 'none' && v.trim().isNotEmpty
                ? 'postcard'
                : null,
          ),
        ),
      ),
      TextButton.icon(
        onPressed: widget.supportsPlaces && !_locating ? _locate : null,
        icon: _locating
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location, size: 17),
        label: Text(
          _locating
              ? t('Finding your city…', 'جارٍ تحديد مدينتك…')
              : t('Use my location', 'استخدم موقعي'),
        ),
      ),
      if (_locationError != null)
        Text(
          _locationError!,
          style: const TextStyle(color: Color(0xFFFFBCBC), fontSize: 12),
        ),
      if (!widget.supportsPlaces)
        Text(
          t(
            'Place frames need the native camera.',
            'إطارات الأماكن تتطلب الكاميرا الأصلية.',
          ),
          style: const TextStyle(color: Colors.white54),
        ),
      Wrap(
        spacing: 8,
        children: [
          for (final (id, name) in [
            ('none', t('Off', 'إيقاف')),
            ('postcard', t('Postcard', 'بطاقة بريدية')),
            ('editorial', t('Editorial', 'مجلة')),
            ('stamp', t('Passport', 'جواز سفر')),
          ])
            ChoiceChip(
              label: Text(name),
              selected: _effects.placeStyle == id,
              onSelected: widget.supportsPlaces
                  ? (_) => _change(effects: _effects.copyWith(placeStyle: id))
                  : null,
            ),
        ],
      ),
    ],
  );

  Widget _slider(String label, double value, ValueChanged<double>? onChanged) =>
      Column(
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                _percent(value),
                style: const TextStyle(color: _accent, fontSize: 12),
              ),
            ],
          ),
          Slider(
            value: value,
            onChanged: onChanged,
            semanticFormatterCallback: _percent,
          ),
        ],
      );

  String _percent(double value) => NumberFormat.percentPattern(
    Localizations.localeOf(context).languageCode,
  ).format(value);

  Widget _tile(
    String id,
    String label,
    IconData icon,
    List<Color> colors,
    bool selected,
    VoidCallback? tap,
  ) => Semantics(
    button: true,
    selected: selected,
    enabled: tap != null,
    label: label,
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(18),
      child: Opacity(
        opacity: tap == null ? 0.35 : 1,
        child: Container(
          width: 94,
          height: 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(
              color: selected ? _accent : Colors.white12,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
