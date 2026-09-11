import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_editor_pro/src/config/story_editor_config.dart';
import 'package:story_editor_pro/src/config/story_editor_strings.dart';
import 'package:story_editor_pro/src/camera_effects.dart';
import 'package:story_editor_pro/src/camera_effects_panel.dart';
import 'package:story_editor_pro/src/native_ar_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'gallery background remains selected when another effect changes',
    (tester) async {
      CameraEffects latest = const CameraEffects();
      Widget panel(CameraEffects effects) => _app(
        child: _panel(
          effects: effects,
          onChanged: (value, _, __) => latest = value,
        ),
      );
      await tester.pumpWidget(panel(const CameraEffects()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        panel(
          const CameraEffects(
            backgroundStyle: 5,
            backgroundPath: '/selected.mp4',
            backgroundIsVideo: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'effects-tab-1');
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(.65);
      await tester.pump();
      expect(latest.beauty, .65);
      expect(latest.backgroundStyle, 5);
      expect(latest.backgroundPath, '/selected.mp4');
      expect(latest.backgroundIsVideo, isTrue);
    },
  );

  test('favorite effects persist locally and reject empty effects', () async {
    final session = CameraEffectsUiSession();
    await session.toggleFavorite('lens', NativeArLensIds.butterflies);
    await session.toggleFavorite('look', 'nightneon');
    await session.toggleFavorite('lens', 'none');
    final reopened = CameraEffectsUiSession();
    await reopened.loadFavorites();
    expect(reopened.isFavorite('lens', NativeArLensIds.butterflies), isTrue);
    expect(reopened.isFavorite('look', 'nightneon'), isTrue);
    expect(reopened.isFavorite('lens', 'none'), isFalse);
    await reopened.toggleFavorite('look', 'nightneon');
    expect(reopened.isFavorite('look', 'nightneon'), isFalse);
  });

  testWidgets(
    'lenses open first and category and face controls survive reopening',
    (tester) async {
      final session = CameraEffectsUiSession();
      await tester.pumpWidget(_app(child: _panel(uiSession: session)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('effects-choices-2')), findsOneWidget);
      expect(find.text('Tap a lens · Swipe for more'), findsOneWidget);
      await _tap(tester, 'effects-tab-1');
      await _tap(tester, 'beauty-control-2');
      await tester.pumpWidget(
        _app(
          child: _panel(key: const ValueKey('reopened'), uiSession: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.category, 1);
      expect(session.beautyControl, 2);
      expect(find.text('Contour'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('effects-choices-2')), findsNothing);
    },
  );

  testWidgets('favorite lens pins near the start and stays selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = CameraEffectsUiSession();
    CameraEffects latest = const CameraEffects();
    await tester.pumpWidget(
      _app(
        child: _panel(
          uiSession: session,
          onChanged: (effects, _, __) => latest = effects,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('effects-choices-2')),
      const Offset(-250, 0),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'effects-card-${NativeArLensIds.butterflies}');
    await tester.tap(find.byTooltip('Save to favorites'));
    await tester.pumpAndSettle();
    expect(session.isFavorite('lens', NativeArLensIds.butterflies), isTrue);
    expect(latest.faceLens, NativeArLensIds.butterflies);
    expect(
      tester
          .getCenter(
            find.byKey(ValueKey('effects-card-${NativeArLensIds.butterflies}')),
          )
          .dx,
      lessThan(200),
    );
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browsing position survives changing category and reopening', (
    tester,
  ) async {
    final session = CameraEffectsUiSession(category: 0);
    await tester.pumpWidget(_app(child: _panel(uiSession: session)));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('effects-choices-0')),
      const Offset(-650, 0),
    );
    await tester.pumpAndSettle();
    final offset = session.scrollOffsets[0]!;
    expect(offset, greaterThan(100));
    await _tap(tester, 'effects-tab-2');
    await _tap(tester, 'effects-tab-0');
    expect(session.scrollOffsets[0], closeTo(offset, 1));
    await tester.pumpWidget(
      _app(
        child: _panel(key: const ValueKey('reopened'), uiSession: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.scrollOffsets[0], closeTo(offset, 1));
  });

  testWidgets('reopening a pending place lookup completes automatically', (
    tester,
  ) async {
    final session = CameraEffectsUiSession();
    final city = Completer<String>();
    final location = CameraPlaceSession(resolver: (_) => city.future);
    CameraEffects latest = const CameraEffects();
    Widget panel(String key) => _app(
      child: _panel(
        key: ValueKey(key),
        uiSession: session,
        locationSession: location,
        onChanged: (effects, _, __) => latest = effects,
      ),
    );
    await tester.pumpWidget(panel('first'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('effects-tab-3')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    city.complete('Kuwait City');
    await tester.pump();
    await tester.pumpWidget(panel('second'));
    await tester.pumpAndSettle();
    expect(latest.placeName, 'Kuwait City');
    expect(latest.placeStyle, 'postcard');
    await _tap(tester, 'effects-card-place-none');
    await tester.pumpWidget(panel('third'));
    await tester.pumpAndSettle();
    expect(latest.placeStyle, 'none', reason: 'Explicit Off remains off');
  });

  testWidgets('reset can be undone without losing any selected layers', (
    tester,
  ) async {
    const original = CameraEffects(
      beauty: .65,
      beautyEyes: .3,
      beautySlim: .2,
      faceLens: NativeArLensIds.celestial,
      placeStyle: 'editorial',
      placeName: 'مدينة الكويت',
    );
    CameraEffects latest = original;
    await tester.pumpWidget(
      _app(
        locale: const Locale('ar'),
        child: _panel(
          effects: original,
          onChanged: (effects, _, __) => latest = effects,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إعادة ضبط التأثيرات'));
    await tester.pumpAndSettle();
    expect(latest.layerCount, 0);
    expect(find.text('تراجع'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(latest, same(original));
    expect(find.text('تراجع'), findsNothing);
  });

  testWidgets('unavailable lens explains why a tap has no camera effect', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        child: _panel(
          faceLenses: const {},
          onChanged: (_, __, ___) =>
              fail('Unsupported lens must not be selected'),
        ),
      ),
    );
    await _tap(tester, 'effects-tab-2');
    await _tap(tester, 'effects-card-${NativeArLensIds.celestial}');
    expect(
      find.text('This effect is unavailable on this camera.'),
      findsOneWidget,
    );
  });

  test('independent beauty controls and layers preserve and bound values', () {
    final effects = const CameraEffects().copyWith(
      beauty: .5,
      beautyEyes: .25,
      beautySlim: .4,
      backgroundStyle: 2,
      faceLens: NativeArLensIds.heartHalo,
      placeStyle: 'postcard',
      placeName: '  مدينة الكويت  ',
    );
    final edited = effects.copyWith(beauty: 2, beautyEyes: -1);
    expect(edited.beauty, 1);
    expect(edited.beautyEyes, 0);
    expect(edited.beautySlim, .4);
    expect(edited.faceLens, NativeArLensIds.heartHalo);
    expect(edited.placeName, 'مدينة الكويت');
    expect(edited.backgroundStyle, 2);
    expect(edited.layerCount, 4);
    expect(edited.copyWith(backgroundStyle: 8).backgroundStyle, 5);
    expect(edited.copyWith(backgroundStyle: -1).backgroundStyle, 0);
    expect(edited.copyWith(beauty: double.nan).beauty, 0);
    expect(edited.copyWith(beautyEyes: double.infinity).beautyEyes, 0);
    expect(edited.copyWith(beautySlim: double.nan).beautySlim, 0);
    expect(edited.copyWith(placeName: '🌍' * 100).placeName.runes.length, 64);
    expect(edited.copyWith(placeName: '').layerCount, 3);
    expect(const CameraEffects(beautyEyes: .5).layerCount, 1);
    expect(const CameraEffects(beautySlim: .5).layerCount, 1);
    expect(const CameraEffects(backgroundStyle: 4).layerCount, 1);
  });

  testWidgets(
    'background stays independent from lenses and reset can undo it',
    (tester) async {
      CameraEffects latest = const CameraEffects(
        beauty: .35,
        faceLens: NativeArLensIds.heartHalo,
      );
      await tester.pumpWidget(
        _app(
          child: _panel(
            effects: latest,
            supportsBackground: true,
            onChanged: (effects, _, __) => latest = effects,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'effects-tab-4');
      await _tap(tester, 'effects-card-background-2');
      expect(latest.backgroundStyle, 2);
      expect(latest.faceLens, NativeArLensIds.heartHalo);
      expect(latest.beauty, .35);
      await tester.tap(find.byTooltip('Reset effects'));
      await tester.pumpAndSettle();
      expect(latest.backgroundStyle, 0);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(latest.backgroundStyle, 2);
      expect(latest.faceLens, NativeArLensIds.heartHalo);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background choices stay unavailable until native capability arrives',
    (tester) async {
      await tester.pumpWidget(
        _app(
          child: _panel(
            onChanged: (_, __, ___) => fail(
              'Background must not activate before capability discovery',
            ),
          ),
        ),
      );
      await _tap(tester, 'effects-tab-4');
      await _tap(tester, 'effects-card-background-1');
      expect(
        find.text('This effect is unavailable on this camera.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Arabic background readiness survives pose events and explains retry',
    (tester) async {
      final events = StreamController<NativeArEvent>.broadcast();
      addTearDown(events.close);
      await tester.pumpWidget(
        _app(
          locale: const Locale('ar'),
          child: _panel(
            supportsBackground: true,
            effects: const CameraEffects(backgroundStyle: 1),
            uiSession: CameraEffectsUiSession(category: 4),
            arEvents: events.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('جارٍ تجهيز الخلفية…'), findsOneWidget);
      events.add(
        const NativeArEvent(
          type: NativeArEventType.background,
          state: NativeArRuntimeState.active,
          backgroundReady: true,
        ),
      );
      await tester.pumpAndSettle();
      events.add(
        const NativeArEvent(
          type: NativeArEventType.pose,
          state: NativeArRuntimeState.active,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('يبقى الشخص في المقدمة · صور وفيديو'), findsOneWidget);
      events.add(
        const NativeArEvent(
          type: NativeArEventType.error,
          state: NativeArRuntimeState.unavailable,
          failure: NativeArFailure(
            code: 'background_error',
            message: 'Native English error',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('اختر إيقاف، ثم خلفية للمحاولة مجدداً.'),
        findsOneWidget,
      );
      expect(find.text('Native English error'), findsNothing);
      await _tap(tester, 'effects-card-background-0');
      await _tap(tester, 'effects-card-background-1');
      expect(find.text('جارٍ تجهيز الخلفية…'), findsOneWidget);
    },
  );

  test(
    'location session is lazy, deduplicates and caches by language',
    () async {
      final result = Completer<String>();
      final calls = <String>[];
      final session = CameraPlaceSession(
        resolver: (locale) {
          calls.add(locale);
          return result.future;
        },
      );
      expect(calls, isEmpty);
      final first = session.resolve(localeIdentifier: 'ar_KW');
      final second = session.resolve(localeIdentifier: 'ar_KW');
      expect(calls, ['ar_KW']);
      result.complete('مدينة الكويت');
      expect(await first, 'مدينة الكويت');
      expect(await second, 'مدينة الكويت');
      expect(await session.resolve(localeIdentifier: 'ar_KW'), 'مدينة الكويت');
      expect(calls, ['ar_KW']);
      await session.resolve(localeIdentifier: 'en_US');
      expect(calls, ['ar_KW', 'en_US']);
    },
  );

  test(
    'failed city lookups can be retried without caching a fake place',
    () async {
      var calls = 0;
      final session = CameraPlaceSession(
        resolver: (_) async {
          if (++calls == 1) throw StateError('permission denied');
          return 'Kuwait City';
        },
      );
      await expectLater(
        session.resolve(localeIdentifier: 'en'),
        throwsStateError,
      );
      expect(await session.resolve(localeIdentifier: 'en'), 'Kuwait City');
      expect(calls, 2);
    },
  );

  test(
    'location lookup requests the app language before resolving the city',
    () async {
      final previousLocator = GeolocatorPlatform.instance;
      final previousGeocoder = geo.GeocodingPlatform.instance;
      final geocoder = _LanguageGeocoder();
      GeolocatorPlatform.instance = _GrantedLocation();
      geo.GeocodingPlatform.instance = geocoder;
      addTearDown(() {
        GeolocatorPlatform.instance = previousLocator;
        geo.GeocodingPlatform.instance =
            previousGeocoder ?? _UnavailableGeocoder();
      });
      expect(
        await resolveCameraPlace(localeIdentifier: 'ar_KW'),
        'مدينة الكويت',
      );
      expect(geocoder.calls, ['locale:ar_KW', 'lookup:ar_KW']);
      expect(
        await resolveCameraPlace(localeIdentifier: 'en_US'),
        'Kuwait City',
      );
      expect(geocoder.calls.last, 'lookup:en_US');
    },
  );

  testWidgets('small RTL camera tray stays compact with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        locale: const Locale('ar', 'KW'),
        textScale: 1.3,
        child: _panel(
          locationSession: CameraPlaceSession(
            resolver: (_) async => 'مدينة الكويت',
          ),
          onClose: () {},
        ),
      ),
    );
    expect(
      Directionality.of(tester.element(find.byType(CameraEffectsPanel))),
      TextDirection.rtl,
    );
    expect(tester.getSize(find.byType(CameraEffectsPanel)).height, 148);
    expect(
      tester.getCenter(find.text('ألوان')).dx,
      greaterThan(tester.getCenter(find.text('جمال')).dx),
    );
    for (final tab in [1, 2, 3, 4, 0]) {
      await _tap(tester, 'effects-tab-$tab');
      expect(
        tester.takeException(),
        isNull,
        reason: 'Tab $tab must fit a small RTL camera',
      );
    }
    await _tap(tester, 'effects-card-daytime');
    expect(find.text('توهّج ذهبي'), findsOneWidget);
    expect(find.text('Golden Bloom'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  test(
    'native command carries a face, composition and real place together',
    () async {
      const channel = MethodChannel('story_editor_pro/ar');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getCapabilities') {
          return {'available': true, 'lensIds': NativeArLensIds.all.toList()};
        }
        return null;
      });
      final controller = NativeArController();
      await controller.getCapabilities();
      expect(
        await controller.setLens(
          NativeArLensIds.celestial,
          compositionId: 'daytime',
          placeStyle: 'editorial',
          placeName: 'Kyoto',
          languageCode: 'ar',
          countryCode: 'KW',
          mirrorOutput: true,
        ),
        isTrue,
      );
      final args = calls.last.arguments as Map;
      expect(args['lensId'], NativeArLensIds.celestial);
      expect(args['compositionId'], 'daytime');
      expect(args['placeStyle'], 'editorial');
      expect(args['placeName'], 'Kyoto');
      expect(args['languageCode'], 'ar');
      expect(args['countryCode'], 'KW');
      expect(args['mirrorOutput'], isTrue);
      expect(args['placeArtwork'], isNotEmpty);
      await controller.setLens(
        NativeArLensIds.celestial,
        compositionId: 'daytime',
        placeStyle: 'editorial',
        placeName: 'Kyoto',
        languageCode: 'ar',
      );
      expect(
        (calls.last.arguments as Map).containsKey('placeArtwork'),
        isFalse,
        reason:
            'Moving or reapplying a sticker must not rasterize/upload it again',
      );
      await controller.updatePlaceSticker(x: .3, y: .4, scale: 1.2);
      expect(calls.last.method, 'updatePlaceSticker');
      expect(calls.last.arguments, {'x': .3, 'y': .4, 'scale': 1.2});
      await expectLater(
        controller.updatePlaceSticker(x: double.nan, y: .4, scale: 1),
        throwsArgumentError,
      );

      await expectLater(
        controller.setLens('none', intensity: double.nan),
        throwsArgumentError,
      );
      await controller.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets('beauty, face shape, lens, real city and look stack and reset', (
    tester,
  ) async {
    CameraEffects latest = const CameraEffects();
    String look = 'none';
    var cityRequests = 0;
    await tester.pumpWidget(
      _app(
        child: _panel(
          supportsFaceBeauty: true,
          locationSession: CameraPlaceSession(
            resolver: (_) async {
              cityRequests++;
              return 'Kyoto';
            },
          ),
          onChanged: (effects, id, _) {
            latest = effects;
            look = id;
          },
        ),
      ),
    );
    expect(
      cityRequests,
      0,
      reason: 'Opening camera effects must not request GPS',
    );
    await _tap(tester, 'effects-tab-1');
    await tester.tap(find.text('Smooth'));
    await _tap(tester, 'beauty-control-1');
    tester.widget<Slider>(find.byType(Slider)).onChanged!(.3);
    await _tap(tester, 'beauty-control-2');
    tester.widget<Slider>(find.byType(Slider)).onChanged!(.4);
    await _tap(tester, 'effects-tab-2');
    expect(find.text('Classic'), findsNothing);
    await _tap(tester, 'effects-card-${NativeArLensIds.heartHalo}');
    await _tap(tester, 'effects-tab-3');
    expect(cityRequests, 1);
    expect(latest.placeName, 'Kyoto');
    expect(latest.placeStyle, 'postcard');
    expect(find.byType(TextField), findsNothing);
    await _tap(tester, 'effects-card-place-editorial');
    await _tap(tester, 'effects-tab-0');
    await _tap(tester, 'effects-card-daytime');
    expect(latest.beauty, .65);
    expect(latest.beautyEyes, .3);
    expect(latest.beautySlim, .4);
    expect(latest.faceLens, NativeArLensIds.heartHalo);
    expect(latest.placeStyle, 'editorial');
    expect(look, 'daytime');
    await tester.tap(find.byTooltip('Reset effects'));
    expect(latest.layerCount, 0);
    expect(look, 'none');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selecting Off while GPS is pending never reapplies a city frame',
    (tester) async {
      final result = Completer<String>();
      CameraEffects latest = const CameraEffects();
      await tester.pumpWidget(
        _app(
          child: _panel(
            locationSession: CameraPlaceSession(resolver: (_) => result.future),
            onChanged: (effects, _, __) => latest = effects,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('effects-tab-3')));
      await tester.pump();
      expect(find.text('Finding your city…'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('effects-card-place-editorial')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('effects-card-place-none')));
      result.complete('Kuwait City');
      await tester.pumpAndSettle();
      expect(latest.placeStyle, 'none');
      expect(latest.placeName, isEmpty);
    },
  );

  testWidgets('city failure offers retry and never allows fabricated names', (
    tester,
  ) async {
    var attempts = 0;
    CameraEffects latest = const CameraEffects();
    await tester.pumpWidget(
      _app(
        child: _panel(
          locationSession: CameraPlaceSession(
            resolver: (_) async {
              if (++attempts == 1) throw StateError('permission denied');
              return 'Kuwait City';
            },
          ),
          onChanged: (effects, _, __) => latest = effects,
        ),
      ),
    );
    await _tap(tester, 'effects-tab-3');
    expect(latest.placeName, isEmpty);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(latest.placeName, 'Kuwait City');
    expect(attempts, 2);
  });

  testWidgets('reopening inline controls reuses the city cache', (
    tester,
  ) async {
    var requests = 0;
    final session = CameraPlaceSession(
      resolver: (_) async {
        requests++;
        return 'Kuwait City';
      },
    );
    Widget panel(String key) => _app(
      child: _panel(key: ValueKey(key), locationSession: session),
    );
    await tester.pumpWidget(panel('first'));
    await _tap(tester, 'effects-tab-3');
    expect(find.byType(Scaffold), findsOneWidget);
    await tester.pumpWidget(panel('second'));
    await _tap(tester, 'effects-tab-3');
    expect(requests, 1);
  });

  testWidgets('unsupported beauty and location controls cannot apply effects', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        child: _panel(
          supportsBeauty: false,
          supportsPlaces: false,
          onChanged: (_, __, ___) =>
              fail('Unavailable control applied an effect'),
        ),
      ),
    );
    await _tap(tester, 'effects-tab-1');
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await _tap(tester, 'beauty-control-1');
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await _tap(tester, 'effects-tab-3');
    expect(find.text('Location frames unavailable'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Arabic GPS place and stacked layers survive a language change', (
    tester,
  ) async {
    CameraEffects latest = const CameraEffects();
    const name = 'الكُوَيْت — Kuwait 2026';
    final session = CameraPlaceSession(resolver: (_) async => name);
    Widget app(Locale locale) => _app(
      locale: locale,
      child: _panel(
        locationSession: session,
        onChanged: (effects, _, __) => latest = effects,
      ),
    );
    await tester.pumpWidget(app(const Locale('ar')));
    await _tap(tester, 'effects-tab-1');
    await tester.tap(find.text('ناعم'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.semanticFormatterCallback!(.5), '50\u200e%\u200e');
    expect(
      Directionality.of(tester.element(find.byType(Slider))),
      TextDirection.rtl,
    );
    await _tap(tester, 'effects-tab-2');
    await _tap(tester, 'effects-card-${NativeArLensIds.heartHalo}');
    await _tap(tester, 'effects-tab-3');
    await _tap(tester, 'effects-card-place-editorial');
    expect(latest.placeName, name);
    expect(latest.beauty, .65);
    expect(latest.placeName, name);
    expect(latest.layerCount, 3);
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Places'), findsOneWidget);
    expect(latest.placeName, name);
    expect(latest.layerCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('beauty Off clears smoothing, eye size and contour together', (
    tester,
  ) async {
    CameraEffects latest = const CameraEffects(
      beauty: .65,
      beautyEyes: .4,
      beautySlim: .5,
    );
    await tester.pumpWidget(
      _app(
        child: _panel(
          effects: latest,
          supportsFaceBeauty: true,
          onChanged: (effects, _, __) => latest = effects,
        ),
      ),
    );
    await _tap(tester, 'effects-tab-1');
    await tester.tap(find.text('Natural'));
    expect(latest.beautyEyes, .4);
    expect(latest.beautySlim, .5);
    await tester.tap(find.text('Off'));
    expect(latest.layerCount, 0);
  });

  testWidgets('Arabic defaults preserve explicit host translations', (
    tester,
  ) async {
    late StoryEditorStrings resolved;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: StoryEditorConfigProvider(
          config: const StoryEditorConfig(
            strings: StoryEditorStrings(cameraEffects: 'عدساتي'),
          ),
          child: Builder(
            builder: (context) {
              resolved = context.storyStrings;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(resolved.cameraEffects, 'عدساتي');
    const arabic = StoryEditorStrings.arabic();
    expect(arabic.cameraEffectsLabel(3), 'التأثيرات · 3');
    expect(arabic.formatStartAfter(5), 'البدء بعد 5 ث');
    expect(arabic.formatCaptureText(1, 4), 'التقاط: 1/4');
    expect(arabic.formatPeopleCount(12), 'عدد الأشخاص: 12');
  });
}

CameraEffectsPanel _panel({
  Key? key,
  CameraEffects effects = const CameraEffects(),
  bool supportsBeauty = true,
  bool supportsFaceBeauty = false,
  bool supportsBackground = false,
  bool supportsPlaces = true,
  CameraPlaceSession? locationSession,
  CameraEffectsUiSession? uiSession,
  Set<String> faceLenses = NativeArLensIds.face,
  VoidCallback? onClose,
  Stream<NativeArEvent>? arEvents,
  void Function(CameraEffects, String, double)? onChanged,
}) => CameraEffectsPanel(
  key: key,
  effects: effects,
  lookId: 'none',
  lookStrength: .85,
  supportedFaceLenses: faceLenses,
  supportsPlaces: supportsPlaces,
  supportsBeauty: supportsBeauty,
  supportsFaceBeauty: supportsFaceBeauty,
  supportsBackground: supportsBackground,
  locationSession: locationSession,
  uiSession: uiSession,
  onClose: onClose,
  arEvents: arEvents,
  onChanged: onChanged ?? (_, __, ___) {},
);

Widget _app({
  required Widget child,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _LanguageGeocoder extends geo.GeocodingPlatform {
  final calls = <String>[];
  String? locale;
  @override
  Future<void> setLocaleIdentifier(String localeIdentifier) async {
    locale = localeIdentifier;
    calls.add('locale:$locale');
  }

  @override
  Future<List<geo.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    calls.add('lookup:$locale');
    return [
      geo.Placemark(
        locality: locale == 'ar_KW' ? 'مدينة الكويت' : 'Kuwait City',
      ),
    ];
  }
}

class _UnavailableGeocoder extends geo.GeocodingPlatform {}

class _GrantedLocation extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    latitude: 29.3759,
    longitude: 47.9774,
    timestamp: DateTime(2026),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
