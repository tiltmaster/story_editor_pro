import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:story_editor_pro/src/config/story_editor_config.dart';
import 'package:story_editor_pro/src/config/story_editor_strings.dart';
import 'package:story_editor_pro/src/camera_effects.dart';
import 'package:story_editor_pro/src/camera_effects_panel.dart';
import 'package:story_editor_pro/src/native_ar_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('independent layers survive edits and bound user input', () {
    final effects = const CameraEffects().copyWith(
      beauty: .5,
      faceLens: NativeArLensIds.heartHalo,
      placeStyle: 'postcard',
      placeName: '  مدينة الكويت  ',
    );
    final edited = effects.copyWith(beauty: 2);
    expect(edited.beauty, 1);
    expect(edited.faceLens, NativeArLensIds.heartHalo);
    expect(edited.placeName, 'مدينة الكويت');
    expect(edited.layerCount, 3);
    expect(edited.copyWith(beauty: double.nan).beauty, 0);
    expect(edited.copyWith(placeName: '🌍' * 100).placeName.runes.length, 64);
    expect(edited.copyWith(placeName: '').layerCount, 2);
  });

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

  testWidgets('small RTL layout remains usable with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar', 'KW'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CameraEffectsPanel(
              effects: const CameraEffects(),
              lookId: 'none',
              lookStrength: .85,
              supportedFaceLenses: NativeArLensIds.face,
              supportsPlaces: true,
              supportsBeauty: true,
              onChanged: (_, __, ___) {},
            ),
          ),
        ),
      ),
    );
    expect(
      Directionality.of(tester.element(find.byType(CameraEffectsPanel))),
      TextDirection.rtl,
    );
    expect(
      tester.getCenter(find.text('ألوان')).dx,
      greaterThan(tester.getCenter(find.text('جمال')).dx),
    );
    for (final tab in ['جمال', 'عدسات', 'أماكن', 'ألوان']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$tab must fit a small screen',
      );
    }
    expect(find.text('توهّج ذهبي'), findsOneWidget);
    expect(find.text('Golden Bloom'), findsNothing);
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
      await expectLater(
        controller.setLens('none', intensity: double.nan),
        throwsArgumentError,
      );
      await controller.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets('beauty, lens, place and look can be combined then cleared', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CameraEffects latest = const CameraEffects();
    String look = 'none';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CameraEffectsPanel(
              effects: latest,
              lookId: look,
              lookStrength: .85,
              supportedFaceLenses: NativeArLensIds.face,
              supportsPlaces: true,
              supportsBeauty: true,
              onChanged: (effects, id, _) {
                latest = effects;
                look = id;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Beauty'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soft'));
    await tester.tap(find.text('Lenses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heart halo'));
    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Kyoto');
    await tester.tap(find.text('Editorial'));
    await tester.tap(find.text('Looks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Golden Bloom'));
    expect(latest.beauty, .5);
    expect(latest.faceLens, NativeArLensIds.heartHalo);
    expect(latest.placeStyle, 'editorial');
    expect(latest.placeName, 'Kyoto');
    expect(look, 'daytime');
    await tester.tap(find.text('Reset'));
    expect(latest.layerCount, 0);
    expect(look, 'none');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unsupported capabilities do not offer working-looking beauty controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraEffectsPanel(
              effects: const CameraEffects(),
              lookId: 'none',
              lookStrength: .85,
              supportedFaceLenses: const {},
              supportsPlaces: false,
              supportsBeauty: false,
              onChanged: (_, __, ___) =>
                  fail('Unavailable control must not apply an effect'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Beauty'));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    },
  );

  testWidgets(
    'Arabic mixed place entry and stacked layers survive a language change',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      CameraEffects latest = const CameraEffects();
      Widget app(Locale locale) => MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CameraEffectsPanel(
              effects: const CameraEffects(),
              lookId: 'none',
              lookStrength: .85,
              supportedFaceLenses: NativeArLensIds.face,
              supportsPlaces: true,
              supportsBeauty: true,
              onChanged: (effects, _, __) => latest = effects,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('جمال'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ناعم'));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      // CLDR's generic Arabic locale uses Latin digits with bidi marks.
      expect(slider.semanticFormatterCallback!(.5), '50\u200e%\u200e');
      expect(
        Directionality.of(tester.element(find.byType(Slider))),
        TextDirection.rtl,
      );
      await tester.tap(find.text('عدسات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('هالة قلوب'));
      await tester.tap(find.text('أماكن'));
      await tester.pumpAndSettle();
      const name = 'الكُوَيْت — Kuwait 2026';
      await tester.enterText(find.byType(TextField), name);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('مجلة'));
      await tester.tap(find.text('مجلة'));
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable
            .textDirection,
        TextDirection.rtl,
      );
      expect(editable.controller.text, name);
      expect(latest.beauty, .5);
      expect(latest.faceLens, NativeArLensIds.heartHalo);
      expect(latest.placeStyle, 'editorial');
      expect(latest.placeName, name);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Arabic place input must fit with the keyboard open',
      );
      tester.view.resetViewInsets();
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Place name'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        name,
      );
      expect(latest.layerCount, 3);
      expect(tester.takeException(), isNull);
    },
  );

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
