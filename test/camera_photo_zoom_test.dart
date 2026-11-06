import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const native = MethodChannel('story_editor_pro');
  final calls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({}); calls.clear();
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initializeCamera' => {'textureId':42,'previewWidth':1080.0,'previewHeight':1920.0},
        'getCameraControls' => {'minZoom':1.0,'maxZoom':4.0,'minExposure':-2.0,'maxExposure':2.0,'focus':true,'exposure':true},
        _ => true,
      };
    });
    messenger.setMockMethodCallHandler(const MethodChannel('story_editor_pro/ar'), (call) async =>
      call.method == 'getCapabilities' ? {'available':false} : null);
    messenger.setMockMethodCallHandler(const MethodChannel('story_editor_pro/ar_events'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (_) async => 0);
  });
  tearDown(() {
    for(final name in ['story_editor_pro','story_editor_pro/ar','story_editor_pro/ar_events','flutter.baseflow.com/permissions/methods']) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });
  testWidgets('pinching photo preview changes native zoom without starting a recording', (tester) async {
    tester.view.physicalSize = const Size(400, 800); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: StoryEditorConfigProvider(
      config: StoryEditorConfig(cameraPermissionManagedByHost:true), child: StoryCameraScreen())));
    await tester.pump(); await tester.pump(const Duration(milliseconds:100)); await tester.pump();
    final preview=find.byKey(const ValueKey('camera-preview-gestures'));
    expect(preview,findsOneWidget);
    final center=tester.getCenter(preview)-const Offset(0,30);
    final left=await tester.startGesture(center-const Offset(35,0),pointer:1);
    final right=await tester.startGesture(center+const Offset(35,0),pointer:2);
    await tester.pump();
    await left.moveTo(center-const Offset(85,0)); await right.moveTo(center+const Offset(85,0));
    await tester.pump(const Duration(milliseconds:100));
    await left.up(); await right.up(); await tester.pump();
    final zoom=calls.where((c)=>c.method=='setZoomLevel').toList();
    expect(zoom,isNotEmpty); final zoomedIn=(zoom.last.arguments as Map)['level'] as double;
    expect(zoomedIn,greaterThan(1));
    final leftOut=await tester.startGesture(center-const Offset(85,0),pointer:3);
    final rightOut=await tester.startGesture(center+const Offset(85,0),pointer:4);
    await tester.pump();
    await leftOut.moveTo(center-const Offset(35,0));await rightOut.moveTo(center+const Offset(35,0));
    await tester.pump(const Duration(milliseconds:100));await leftOut.up();await rightOut.up();await tester.pump();
    final zoomedOut=(calls.lastWhere((c)=>c.method=='setZoomLevel').arguments as Map)['level'] as double;
    expect(zoomedOut,lessThan(zoomedIn));expect(zoomedOut,greaterThanOrEqualTo(1));
    expect(calls.where((c)=>c.method.toLowerCase().contains('startrecord')),isEmpty);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump(const Duration(seconds:1));
  });
}
