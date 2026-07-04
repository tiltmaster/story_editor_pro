import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// ---------------------------------------------------------------------------
/// Smart stickers + the Snapchat-style sticker drawer.
/// Live-data stickers (time, date, day, battery, speed, location, emoji)
/// freeze their values at add-time; rendering is a pure function of the model
/// so the same widget serves the interactive layer and the export
/// RepaintBoundary — stickers bake into photos AND videos with no native work.
/// ---------------------------------------------------------------------------

enum SmartStickerType { time, date, day, battery, speed, location, emoji, greeting }

class SmartStickerOverlay {
  final SmartStickerType type;
  int skin;
  final Map<String, String> data;
  Offset offset;
  double scale;

  SmartStickerOverlay({
    required this.type,
    this.skin = 0,
    required this.data,
    this.offset = const Offset(120, 260),
    this.scale = 1.0,
  });

  int get skinCount => smartStickerSkinCount(type);

  void cycleSkin() => skin = (skin + 1) % skinCount;
}

int smartStickerSkinCount(SmartStickerType type) {
  switch (type) {
    case SmartStickerType.time:
      return 3;
    case SmartStickerType.date:
      return 3;
    case SmartStickerType.day:
      return 2;
    case SmartStickerType.battery:
      return 2;
    case SmartStickerType.speed:
      return 2;
    case SmartStickerType.location:
      return 3;
    case SmartStickerType.emoji:
      return 2;
    case SmartStickerType.greeting:
      return 2;
  }
}

/// What the drawer hands back to the editor.
class StickerDrawerResult {
  final SmartStickerOverlay? sticker;

  /// Bundled decorative sticker (word-art) — the editor materializes it to a
  /// temp file and adds a normal ImageOverlay.
  final String? imageAssetPath;

  /// Already-downloaded sticker file (e.g. a KLIPY sticker) — added directly
  /// as an ImageOverlay.
  final String? imageFilePath;

  const StickerDrawerResult.sticker(SmartStickerOverlay this.sticker)
      : imageAssetPath = null,
        imageFilePath = null;
  const StickerDrawerResult.asset(String this.imageAssetPath)
      : sticker = null,
        imageFilePath = null;
  const StickerDrawerResult.file(String this.imageFilePath)
      : sticker = null,
        imageAssetPath = null;
}

/// A remote sticker (thumb for the grid, url to download on pick).
class RemoteSticker {
  final String thumbUrl;
  final String url;
  const RemoteSticker({required this.thumbUrl, required this.url});
}

/// Download a remote sticker to a temp file for use as an ImageOverlay.
Future<String> downloadStickerToTemp(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('sticker download failed (${response.statusCode})');
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    final dir = await getTemporaryDirectory();
    final ext = url.split('?').first.split('.').last;
    final safeExt = ['gif', 'png', 'webp', 'jpg'].contains(ext) ? ext : 'png';
    final f = File(
        '${dir.path}/klipy_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  } finally {
    client.close(force: true);
  }
}

/// Bundled decorative word-art stickers (Higgsfield-generated, transparent).
const List<String> kWordArtAssets = [
  'packages/story_editor_pro/assets/word_art/good_vibes.png',
  'packages/story_editor_pro/assets/word_art/habibi.png',
  'packages/story_editor_pro/assets/word_art/weekend.png',
  'packages/story_editor_pro/assets/word_art/late_night.png',
];

/// Copy a bundled asset to a temp file (the editor's ImageOverlay renders
/// from file paths).
final Map<String, String> _materializedAssets = {};
Future<String> materializeStickerAsset(String assetPath) async {
  final cached = _materializedAssets[assetPath];
  if (cached != null && File(cached).existsSync()) return cached;
  final data = await rootBundle.load(assetPath);
  final dir = await getTemporaryDirectory();
  final name = assetPath.split('/').last;
  final f = File('${dir.path}/story_sticker_$name');
  await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
  _materializedAssets[assetPath] = f.path;
  return f.path;
}

/// Host-app data injection (the app supplies its own places/geocoding —
/// e.g. Niero injects its Supabase places; a Google Places-backed search can
/// be plugged in the same way).
class SmartStickerProviders {
  SmartStickerProviders._();
  static final SmartStickerProviders instance = SmartStickerProviders._();

  /// Nearby place names for (lat, lng). Optional.
  Future<List<String>> Function(double lat, double lng)? nearbyPlaces;

  /// Single display name for (lat, lng) — city/area. Optional.
  Future<String?> Function(double lat, double lng)? reverseGeocode;

  /// Free-text place search (e.g. Google Places / own DB). Optional.
  Future<List<String>> Function(String query, double? lat, double? lng)?
      searchPlaces;

  /// Remote sticker packs (e.g. KLIPY via the host's secure proxy).
  /// query == null/empty → trending. Optional.
  Future<List<RemoteSticker>> Function({String? query, int page})?
      remoteStickers;
}

// ---------------------------------------------------------------------------
// Rendering (pure — identical in interactive + export layers)
// ---------------------------------------------------------------------------

Widget buildSmartStickerContent(SmartStickerOverlay o) {
  switch (o.type) {
    case SmartStickerType.time:
      return _timeSticker(o);
    case SmartStickerType.date:
      return _dateSticker(o);
    case SmartStickerType.day:
      return _daySticker(o);
    case SmartStickerType.battery:
      return _batterySticker(o);
    case SmartStickerType.speed:
      return _speedSticker(o);
    case SmartStickerType.location:
      return _locationSticker(o);
    case SmartStickerType.emoji:
      return _emojiSticker(o);
    case SmartStickerType.greeting:
      return _greetingSticker(o);
  }
}

const _shadow = [
  Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
];

Widget _pill({required Widget child, Color color = Colors.black54}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
}

Widget _timeSticker(SmartStickerOverlay o) {
  final time = o.data['time'] ?? '';
  switch (o.skin) {
    case 1:
      return _pill(
        child: Text(time,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700)),
      );
    case 2:
      return Text(o.data['time12'] ?? time,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w200,
              letterSpacing: 2,
              shadows: _shadow));
    default:
      final ampm = o.data['ampm'] ?? '';
      // Arabic reads the AM/PM marker inline with the time; stacking it looks
      // broken, so render on a single line (big time + smaller marker).
      if (o.data['rtl'] == '1') {
        // Arabic: marker sits to the LEFT of the digits (RTL reading). Order
        // the children [marker, time] in a plain LTR row for that visual —
        // avoids colliding with intl's own `TextDirection` type.
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (ampm.isNotEmpty) ...[
              Text(ampm,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      shadows: _shadow)),
              const SizedBox(width: 8),
            ],
            Text(time,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                    height: 0.95,
                    shadows: _shadow)),
          ],
        );
      }
      // Snapchat-style segmented digital clock (LTR)
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(time,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  height: 0.95,
                  shadows: _shadow)),
          Text(ampm,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  shadows: _shadow)),
        ],
      );
  }
}

Widget _dateSticker(SmartStickerOverlay o) {
  switch (o.skin) {
    case 1:
      return _pill(
        color: Colors.white,
        child: Text(o.data['dateLong'] ?? '',
            style: const TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      );
    case 2:
      // Calendar-page skin
      return Container(
        width: 110,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(o.data['month'] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(o.data['dayNum'] ?? '',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      height: 1.0)),
            ),
          ],
        ),
      );
    default:
      return Text(o.data['dateLong'] ?? '',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              shadows: _shadow));
  }
}

Widget _daySticker(SmartStickerOverlay o) {
  final day = o.data['weekday'] ?? '';
  if (o.skin == 1) {
    return _pill(
      child: Text(day.toUpperCase(),
          style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 4)),
    );
  }
  return Text(day,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w700,
          shadows: _shadow));
}

Widget _batterySticker(SmartStickerOverlay o) {
  final pct = int.tryParse(o.data['battery'] ?? '') ?? 0;
  final color = pct <= 20
      ? Colors.redAccent
      : pct <= 50
          ? Colors.amber
          : Colors.greenAccent;
  if (o.skin == 1) {
    return Text('$pct%',
        style: TextStyle(
            color: color,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            shadows: _shadow));
  }
  return _pill(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
            pct <= 20
                ? Icons.battery_2_bar
                : pct <= 60
                    ? Icons.battery_4_bar
                    : Icons.battery_full,
            color: color,
            size: 24),
        const SizedBox(width: 6),
        Text('$pct%',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

Widget _speedSticker(SmartStickerOverlay o) {
  final kmh = o.data['kmh'] ?? '0';
  if (o.skin == 1) {
    return _pill(
      child: Text('$kmh km/h',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700)),
    );
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(kmh,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 54,
              fontWeight: FontWeight.w800,
              height: 1.0,
              shadows: _shadow)),
      const Text('km/h',
          style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              shadows: _shadow)),
    ],
  );
}

Widget _greetingSticker(SmartStickerOverlay o) {
  final text = o.data['greeting'] ?? 'Hello';
  final emoji = o.data['emoji'] ?? '';
  if (o.skin == 1) {
    return _pill(
      child: Text('$text${emoji.isEmpty ? '' : ' $emoji'}',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700)),
    );
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (emoji.isNotEmpty) Text(emoji, style: const TextStyle(fontSize: 34)),
      Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              shadows: _shadow)),
    ],
  );
}

Widget _locationSticker(SmartStickerOverlay o) {
  final name = o.data['name'] ?? '';
  switch (o.skin) {
    case 1:
      return _pill(
        color: Colors.white,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place, color: Colors.redAccent, size: 22),
            const SizedBox(width: 4),
            Text(name,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    case 2:
      return Text(name,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              shadows: _shadow));
    default:
      // Snapchat-style banner: icon + name with accent underline
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, color: Colors.white, size: 26),
              const SizedBox(width: 4),
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      shadows: _shadow)),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 3),
            height: 4,
            width: 64,
            decoration: BoxDecoration(
              color: Colors.amberAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
  }
}

Widget _emojiSticker(SmartStickerOverlay o) {
  final e = o.data['emoji'] ?? '🙂';
  if (o.skin == 1) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Text(e, style: const TextStyle(fontSize: 56)),
    );
  }
  return Text(e, style: const TextStyle(fontSize: 72));
}

// ---------------------------------------------------------------------------
// Data capture (frozen at add-time)
// ---------------------------------------------------------------------------

Future<Map<String, String>> captureStickerData(
    SmartStickerType type, String locale) async {
  final now = DateTime.now();
  switch (type) {
    case SmartStickerType.time:
      final jm = DateFormat.jm(locale).format(now); // e.g. 2:15 AM / ٢:١٥ م
      final parts = jm.split(' ');
      return {
        'time': parts.first,
        'ampm': parts.length > 1 ? parts.sublist(1).join(' ') : '',
        'time12': jm,
        // Arabic reads the AM/PM marker inline with the digits, so the
        // stacked "2:15 / AM" clock skin must render on one line for RTL.
        'rtl': locale.toLowerCase().startsWith('ar') ? '1' : '0',
      };
    case SmartStickerType.date:
      return {
        'dateLong': DateFormat.yMMMMd(locale).format(now),
        'month': DateFormat.MMM(locale).format(now).toUpperCase(),
        'dayNum': DateFormat.d(locale).format(now),
      };
    case SmartStickerType.day:
      return {'weekday': DateFormat.EEEE(locale).format(now)};
    case SmartStickerType.battery:
      int level = 0;
      try {
        level = await Battery().batteryLevel;
      } catch (_) {}
      return {'battery': '$level'};
    case SmartStickerType.speed:
      double kmh = 0;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 5));
        kmh = (pos.speed * 3.6).clamp(0, 400);
      } catch (_) {}
      return {'kmh': kmh.round().toString()};
    case SmartStickerType.location:
      return {}; // filled by the drawer
    case SmartStickerType.emoji:
      return {}; // filled by the drawer
    case SmartStickerType.greeting:
      // Gulf convention is simply صباح (morning) vs مساء (from midday on) —
      // there's no natural third "afternoon" greeting, so a two-way split at
      // noon reads far more organic than forcing a literal "Good Afternoon".
      final hour = now.hour;
      final isArabic = locale.toLowerCase().startsWith('ar');
      final bool morning = hour < 12;
      final text = isArabic
          ? (morning ? 'صباح الخير' : 'مساء الخير')
          : (morning ? 'Good Morning' : 'Good Evening');
      final emoji = morning ? '☀️' : '🌙';
      return {'greeting': text, 'emoji': emoji};
  }
}

// ---------------------------------------------------------------------------
// THE STICKER DRAWER (Snapchat-style full panel)
// ---------------------------------------------------------------------------

Future<StickerDrawerResult?> showStickerDrawer(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context)?.toString() ?? 'en';
  return showModalBottomSheet<StickerDrawerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StickerDrawer(locale: locale),
  );
}

class _StickerDrawer extends StatefulWidget {
  final String locale;
  const _StickerDrawer({required this.locale});

  @override
  State<_StickerDrawer> createState() => _StickerDrawerState();
}

class _StickerDrawerState extends State<_StickerDrawer> {
  // Live values for the big previews
  Map<String, String> _time = {};
  Map<String, String> _date = {};
  Map<String, String> _day = {};
  Map<String, String> _battery = {};

  // Location auto-detect
  String? _detectedArea;
  bool _locating = true;
  Map<String, String> _greeting = const {};

  // Remote stickers (KLIPY via host proxy)
  List<RemoteSticker> _remoteStickers = const [];
  bool _loadingStickers = false;
  bool _stickersHasMore = true;
  int _stickerPage = 1;
  String _stickerQuery = '';
  Timer? _stickerDebounce;
  String? _downloadingUrl;
  final TextEditingController _stickerSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreviewData();
    _detectLocation();
    if (SmartStickerProviders.instance.remoteStickers != null) {
      _loadRemoteStickers(reset: true);
    }
  }

  @override
  void dispose() {
    _stickerDebounce?.cancel();
    _stickerSearch.dispose();
    super.dispose();
  }

  Future<void> _loadRemoteStickers({bool reset = false}) async {
    final provider = SmartStickerProviders.instance.remoteStickers;
    if (provider == null || _loadingStickers) return;
    setState(() {
      _loadingStickers = true;
      if (reset) {
        _stickerPage = 1;
        _remoteStickers = const [];
        _stickersHasMore = true;
      }
    });
    try {
      final items = await provider(
        query: _stickerQuery.isEmpty ? null : _stickerQuery,
        page: _stickerPage,
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _remoteStickers = [..._remoteStickers, ...items];
        _stickersHasMore = items.length >= 12;
        _stickerPage += 1;
        _loadingStickers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStickers = false);
    }
  }

  void _onStickerSearchChanged(String q) {
    _stickerDebounce?.cancel();
    _stickerDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _stickerQuery = q.trim();
      _loadRemoteStickers(reset: true);
    });
  }

  Future<void> _pickRemoteSticker(RemoteSticker s) async {
    if (_downloadingUrl != null) return;
    setState(() => _downloadingUrl = s.url);
    try {
      final path = await downloadStickerToTemp(s.url);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.pop(context, StickerDrawerResult.file(path));
    } catch (_) {
      if (mounted) setState(() => _downloadingUrl = null);
    }
  }

  Future<void> _loadPreviewData() async {
    final time = await captureStickerData(SmartStickerType.time, widget.locale);
    final date = await captureStickerData(SmartStickerType.date, widget.locale);
    final day = await captureStickerData(SmartStickerType.day, widget.locale);
    final battery =
        await captureStickerData(SmartStickerType.battery, widget.locale);
    final greeting =
        await captureStickerData(SmartStickerType.greeting, widget.locale);
    if (!mounted) return;
    setState(() {
      _time = time;
      _date = date;
      _day = day;
      _battery = battery;
      _greeting = greeting;
    });
  }

  Future<void> _detectLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 6));
      final providers = SmartStickerProviders.instance;
      String? area;
      try {
        area = await providers.reverseGeocode
            ?.call(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      // Built-in fallback: platform reverse geocoder — the location circle
      // must ALWAYS resolve, host providers or not.
      if (area == null || area.trim().isEmpty) {
        try {
          final placemarks = await geo
              .placemarkFromCoordinates(pos.latitude, pos.longitude)
              .timeout(const Duration(seconds: 5));
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            area = [p.subLocality, p.locality]
                .whereType<String>()
                .firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
            if (area.trim().isEmpty) area = p.administrativeArea;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _detectedArea = area?.trim().isNotEmpty == true ? area!.trim() : null;
        _locating = false;
      });
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _returnSticker(SmartStickerType type, Map<String, String> data) {
    HapticFeedback.lightImpact();
    Navigator.pop(
      context,
      StickerDrawerResult.sticker(SmartStickerOverlay(type: type, data: data)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            // Slightly translucent so the story stays visible behind
            color: Color(0xCC141414),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    // ---- Live previews (tap = add) — 3×2 grid ----
                    _sectionTitle('Smart'),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.8,
                      children: [
                        _smartTile(
                          onTap: _detectedArea == null
                              ? null
                              : () => _returnSticker(SmartStickerType.location,
                                  {'name': _detectedArea!}),
                          child: _detectedArea == null
                              ? _tilePlaceholder(Icons.place,
                                  _locating ? 'Locating…' : 'Location')
                              : buildSmartStickerContent(SmartStickerOverlay(
                                  type: SmartStickerType.location,
                                  data: {'name': _detectedArea!})),
                        ),
                        _smartTile(
                          onTap: () =>
                              _returnSticker(SmartStickerType.time, _time),
                          child: buildSmartStickerContent(SmartStickerOverlay(
                              type: SmartStickerType.time, data: _time)),
                        ),
                        _smartTile(
                          onTap: () =>
                              _returnSticker(SmartStickerType.date, _date),
                          child: buildSmartStickerContent(SmartStickerOverlay(
                              type: SmartStickerType.date,
                              skin: 2,
                              data: _date)),
                        ),
                        _smartTile(
                          onTap: () =>
                              _returnSticker(SmartStickerType.day, _day),
                          child: buildSmartStickerContent(SmartStickerOverlay(
                              type: SmartStickerType.day, data: _day)),
                        ),
                        _smartTile(
                          onTap: () => _returnSticker(
                              SmartStickerType.battery, _battery),
                          child: buildSmartStickerContent(SmartStickerOverlay(
                              type: SmartStickerType.battery, data: _battery)),
                        ),
                        _smartTile(
                          onTap: () => _returnSticker(
                              SmartStickerType.greeting, _greeting),
                          child: _greeting.isEmpty
                              ? _tilePlaceholder(
                                  Icons.waving_hand_outlined, 'Greeting')
                              : buildSmartStickerContent(SmartStickerOverlay(
                                  type: SmartStickerType.greeting,
                                  skin: 1,
                                  data: _greeting)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ---- Remote stickers (KLIPY via host proxy) ----
                    if (SmartStickerProviders.instance.remoteStickers !=
                        null) ...[
                      _sectionTitle('Stickers'),
                      TextField(
                        controller: _stickerSearch,
                        onChanged: (q) {
                          // Rebuild immediately (clear button visibility);
                          // the actual search stays debounced.
                          setState(() {});
                          _onStickerSearchChanged(q);
                        },
                        textInputAction: TextInputAction.search,
                        onSubmitted: (q) {
                          _stickerDebounce?.cancel();
                          _stickerQuery = q.trim();
                          _loadRemoteStickers(reset: true);
                        },
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15),
                        cursorColor: Colors.amberAccent,
                        decoration: InputDecoration(
                          hintText: 'Search stickers…',
                          hintStyle: const TextStyle(
                              color: Colors.white38, fontSize: 15),
                          prefixIcon: const Icon(Icons.search,
                              color: Colors.white54, size: 20),
                          suffixIcon: _stickerSearch.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.cancel,
                                      color: Colors.white38, size: 18),
                                  onPressed: () {
                                    _stickerDebounce?.cancel();
                                    _stickerSearch.clear();
                                    _stickerQuery = '';
                                    setState(() {});
                                    _loadRemoteStickers(reset: true);
                                  },
                                ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.10)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: const BorderSide(
                                color: Colors.white38, width: 1.2),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final s in _remoteStickers)
                            InkWell(
                              onTap: () => _pickRemoteSticker(s),
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 76,
                                height: 76,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      s.thumbUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const SizedBox.shrink(),
                                    ),
                                    if (_downloadingUrl == s.url)
                                      const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (_stickersHasMore || _loadingStickers)
                            InkWell(
                              onTap: _loadingStickers
                                  ? null
                                  : () => _loadRemoteStickers(),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: _loadingStickers
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white54),
                                        )
                                      : const Icon(Icons.expand_more,
                                          color: Colors.white54),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Word-art section hidden for now (assets kept; the
                    // StickerDrawerResult.asset path still works when it
                    // returns with better art packs).

                    // ---- Emoji (quick row + full picker) ----
                    _sectionTitle('Emoji'),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ...const [
                          '😂', '❤️', '🔥', '😍', '😎', '🥳', '✨', '🙏',
                        ].map(_emojiTile),
                        InkWell(
                          onTap: _openFullEmojiPicker,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.apps,
                                    color: Colors.white70, size: 20),
                                SizedBox(width: 6),
                                Text('All',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emojiTile(String e) {
    return InkWell(
      onTap: () => _returnSticker(SmartStickerType.emoji, {'emoji': e}),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(e, style: const TextStyle(fontSize: 30)),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      );

  Widget _smartTile({VoidCallback? onTap, required Widget child}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
    );
  }

  Widget _tilePlaceholder(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

  Future<void> _openFullEmojiPicker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF2141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.55,
        child: EmojiPicker(
          onEmojiSelected: (category, e) => Navigator.pop(ctx, e.emoji),
          config: const Config(
            checkPlatformCompatibility: true,
            emojiViewConfig: EmojiViewConfig(
              emojiSizeMax: 30,
              backgroundColor: Colors.transparent,
            ),
            categoryViewConfig: CategoryViewConfig(
              backgroundColor: Colors.transparent,
              iconColorSelected: Colors.white,
              iconColor: Colors.white38,
              indicatorColor: Colors.white,
            ),
            bottomActionBarConfig: BottomActionBarConfig(enabled: false),
            searchViewConfig: SearchViewConfig(
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      ),
    );
    if (emoji != null && mounted) {
      _returnSticker(SmartStickerType.emoji, {'emoji': emoji});
    }
  }
}
