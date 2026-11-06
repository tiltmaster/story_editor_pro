import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_editor_pro/story_editor_pro.dart';
import 'package:story_editor_pro/src/camera_effects.dart';
import 'package:story_editor_pro/src/camera_effects_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('explicit retry requests permission even while device location is off', () async {
    var requests=0;
    final access=CameraPlaceAccess(checkPermission:() async => LocationPermission.denied,
      requestPermission:() async { requests++; return LocationPermission.whileInUse; },
      serviceEnabled:() async => false);
    await expectLater(access.prepare(userInitiated:false), throwsA(isA<CameraPlaceAccessException>()
      .having((e)=>e.recovery,'recovery',CameraPlaceRecovery.permission)));
    expect(requests,0);
    await expectLater(access.prepare(userInitiated:true), throwsA(isA<CameraPlaceAccessException>()
      .having((e)=>e.recovery,'recovery',CameraPlaceRecovery.services)));
    expect(requests,1);
  });
  testWidgets('Places denial offers Allow location and deliberate retry resolves it', (tester) async {
    var requests=0;
    CameraEffects latest=const CameraEffects();
    final session=CameraPlaceSession(resolver:(_) async => 'Kuwait City',
      access:CameraPlaceAccess(checkPermission:() async => LocationPermission.denied,
        requestPermission:() async => ++requests==1 ? LocationPermission.denied : LocationPermission.whileInUse,
        serviceEnabled:() async => true));
    await host(tester,session,(value)=>latest=value);
    expect(requests,0);
    await tester.tap(find.byKey(const ValueKey('effects-tab-3'))); await tester.pumpAndSettle();
    expect(requests,1); expect(find.text('Allow location'),findsOneWidget);
    await tester.tap(find.text('Allow location')); await tester.pumpAndSettle();
    expect(requests,2); expect(latest.placeName,'Kuwait City');
    expect(tester.takeException(),isNull);
  });
  testWidgets('Nearby handles permission revoked after a cached city', (tester) async {
    var permission=LocationPermission.whileInUse;
    final session=CameraPlaceSession(resolver:(_) async => 'Kuwait City',
      nearbyResolver:(_,__,___) async => [],
      access:CameraPlaceAccess(checkPermission:() async => permission, serviceEnabled:() async => true));
    await host(tester,session,(_){});
    await tester.tap(find.byKey(const ValueKey('effects-tab-3')));await tester.pumpAndSettle();
    permission=LocationPermission.deniedForever;
    await tester.tap(find.byKey(const ValueKey('camera-nearby-places')));await tester.pumpAndSettle();
    expect(find.text('Open app settings'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('permanent denial only opens labelled settings and rechecks quietly on return', (tester) async {
    var permission=LocationPermission.deniedForever, settings=0, requests=0;
    CameraEffects latest=const CameraEffects();
    final session=CameraPlaceSession(resolver:(_) async => 'Kuwait City',
      access:CameraPlaceAccess(checkPermission:() async => permission,
        requestPermission:() async { requests++; return permission; },
        serviceEnabled:() async => true,
        openAppSettings:() async { settings++; return true; }));
    await host(tester,session,(value)=>latest=value);
    await tester.tap(find.byKey(const ValueKey('effects-tab-3'))); await tester.pumpAndSettle();
    expect(settings,0); expect(requests,0);
    await tester.tap(find.text('Open app settings')); await tester.pumpAndSettle();
    expect(settings,1);
    permission=LocationPermission.whileInUse;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(latest.placeName,'Kuwait City'); expect(settings,1); expect(requests,0);
    expect(tester.takeException(),isNull);
  });
}
Future<void> host(WidgetTester tester,CameraPlaceSession session,ValueChanged<CameraEffects> changed) async {
  await tester.pumpWidget(MaterialApp(home:StoryEditorConfigProvider(config:const StoryEditorConfig(),
    child:Scaffold(body:CameraEffectsPanel(effects:const CameraEffects(),lookId:'none',lookStrength:1,
      supportedFaceLenses:const {},supportsPlaces:true,supportsBeauty:true,locationSession:session,
      onChanged:(e,_,__)=>changed(e))))));
  await tester.pumpAndSettle();
}
