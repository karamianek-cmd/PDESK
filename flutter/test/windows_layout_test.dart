import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/install_page.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/window_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

class _Binding extends Fake implements RustdeskImpl {
  String savedFrame = '';
  final Map<String, String> translations;
  _Binding(this.translations);
  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      translations[name]?.isNotEmpty == true ? translations[name]! : name;
  @override
  String mainGetLocalOption({required String key, dynamic hint}) => '';
  @override
  String mainGetOptionSync({required String key, dynamic hint}) => '';
  @override
  String mainGetBuildinOption({required String key, dynamic hint}) => '';
  @override
  bool mainIsOptionFixed({required String key, dynamic hint}) => false;
  @override
  Future<String> mainGetLastRemoteId({dynamic hint}) async => '';
  @override
  Future<String> mainGetConnectStatus({dynamic hint}) async =>
      '{"status_num":1,"video_conn_count":0}';
  @override
  Future<bool> mainIsUsingPublicServer({dynamic hint}) async => false;
  @override
  String getLocalFlutterOption({required String k, dynamic hint}) => savedFrame;
  @override
  Future<void> setLocalFlutterOption(
          {required String k, required String v, dynamic hint}) async {}
  @override
  String mainGetEnv({required String key, dynamic hint}) => '';
  @override
  bool isIncomingOnly({dynamic hint}) => false;
  @override
  bool isOutgoingOnly({dynamic hint}) => false;
  @override
  bool isCustomClient({dynamic hint}) => false;
  @override
  bool isDisableAb({dynamic hint}) => false;
  @override
  bool isDisableSettings({dynamic hint}) => false;
  @override
  bool isDisableAccount({dynamic hint}) => false;
  @override
  bool isDisableGroupPanel({dynamic hint}) => false;
  @override
  Future<bool> isPresetPassword({dynamic hint}) async => false;
  @override
  bool isDisableInstallation({dynamic hint}) => false;
  @override
  bool mainIsInstalled({dynamic hint}) => false;
  @override
  bool mainIsInstalledLowerVersion({dynamic hint}) => false;
  @override
  String mainGetAppNameSync({dynamic hint}) => 'ParsiDesk';
  @override
  String installInstallPath({dynamic hint}) => r'C:\Program Files\ParsiDesk';
  @override
  String installInstallOptions({dynamic hint}) => '{}';
  @override
  bool installShowRunWithoutInstall({dynamic hint}) => false;
}

Map<String, String> _translations() {
  final result = <String, String>{};
  for (final lang in ['en', 'fa']) {
    final text = File('../src/lang/$lang.rs').readAsStringSync();
    for (final match
        in RegExp(r'\("((?:\\.|[^"\\])*)",\s*"((?:\\.|[^"\\])*)"\)')
            .allMatches(text)) {
      final key = jsonDecode('"${match[1]}"') as String;
      final value = jsonDecode('"${match[2]}"') as String;
      if (value.isNotEmpty) result[key] = value;
    }
  }
  return result;
}

void main() {
  final testBinding = TestWidgetsFlutterBinding.ensureInitialized();
  final binding = _Binding(_translations());
  setUpAll(() async {
    platformFFI.setBindingForTesting(binding);
    isTest = true;
    desktopType = DesktopType.remote;
    await initGlobalFFI();
    for (final entry in {
      'IRANSans': 'assets/fonts/IRANSans/IRANSans-Regular.ttf',
      'Shabnam': 'assets/fonts/Shabnam/Shabnam.ttf',
      'Vazirmatn': 'assets/fonts/Vazirmatn/Vazirmatn-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'Tabbar': 'assets/tabbar.ttf',
    }.entries) {
      final font = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
      await font.load();
    }
    testBinding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), (call) async {
      if (call.method == 'isMaximized' || call.method == 'isFullScreen') {
        return false;
      }
      return null;
    });
  });

  for (final direction in TextDirection.values) {
    testWidgets('connection menu stays beside its full button in $direction',
        (tester) async {
      Get.put(false.obs, tag: 'stop-service');
      addTearDown(() => Get.delete<RxBool>(tag: 'stop-service'));
      final enabled = gFFI.peerTabModel.isEnabled.toList();
      gFFI.peerTabModel.isEnabled.fillRange(0, enabled.length, false);
      addTearDown(() => gFFI.peerTabModel.isEnabled = enabled);
      await tester.pumpWidget(MaterialApp(
        theme: MyTheme.lightTheme,
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: Scaffold(
          body: ChangeNotifierProvider.value(
            value: gFFI.peerTabModel,
            child: const ConnectionPage(),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      final center = tester.getCenter(find.byIcon(IconFont.more));
      for (final point in [center, center + const Offset(16, 0)]) {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 400));
        final menuItem = find.text(binding.translations['Transfer file']!);
        expect(menuItem, findsOneWidget);
        final menu = tester.getRect(menuItem);
        expect(menu.left, lessThan(center.dx + 50));
        expect(menu.right, greaterThan(center.dx - 50));
        expect(menu.top, greaterThan(center.dy + 20));
        await tester.tapAt(const Offset(750, 550));
        await tester.pump(const Duration(milliseconds: 400));
        expect(menuItem, findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !Platform.isWindows);
  }

  testWidgets('portable home sidebar scrolls to the install prompt',
      (tester) async {
    tester.view.physicalSize = const Size(800, 472);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    gFFI.serverModel.serverId.text = '123 456 789';
    gFFI.serverModel.serverPasswd.text = '123456';
    final dynamic state = DesktopHomePage().createState();
    await tester.pumpWidget(MaterialApp(
      theme: MyTheme.lightTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
            body: Builder(
                builder: (context) => state.buildLeftPane(context) as Widget)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    final sidebar = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(sidebar.position.maxScrollExtent, greaterThan(0));
    final install = find.text(binding.translations['Install']!);
    await tester.ensureVisible(install);
    expect(install.hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isWindows);

  testWidgets('installer agreement wraps in a narrow window', (tester) async {
    tester.view.physicalSize = const Size(640, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: MyTheme.lightTheme,
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: InstallPage(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text(binding.translations['agreement_tip']!), findsOneWidget);
    final accept = find.text(binding.translations['Accept and Install']!);
    await tester.ensureVisible(accept);
    expect(accept.hitTestable(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restored main window fits the current work area',
      (tester) async {
    final calls = <MethodCall>[];
    testBinding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter/windowsize'), (call) async {
      if (call.method == 'getScreenList') {
        return [
          {
            'frame': [0.0, 0.0, 1366.0, 768.0],
            'visibleFrame': [0.0, 0.0, 1366.0, 728.0],
            'scaleFactor': 1.0,
          }
        ];
      }
      throw UnimplementedError(call.method);
    });
    testBinding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), (call) async {
      calls.add(call);
      if (call.method != 'setBounds') throw UnimplementedError(call.method);
      return null;
    });

    binding.savedFrame =
        LastWindowPosition(1920.0, 1080.0, 0.0, 0.0, false, false).toString();
    calls.clear();
    expect(await restoreWindowPosition(WindowType.Main), isTrue);
    var sizeCall = calls.lastWhere((c) => c.arguments['width'] != null);
    var positionCall = calls.lastWhere((c) => c.arguments['x'] != null);
    expect(sizeCall.arguments['width'], 1366.0);
    expect(sizeCall.arguments['height'], 728.0);
    expect(positionCall.arguments['x'], 0.0);
    expect(positionCall.arguments['y'], 0.0);

    binding.savedFrame =
        LastWindowPosition(800.0, 600.0, 1350.0, 718.0, false, false)
            .toString();
    calls.clear();
    expect(await restoreWindowPosition(WindowType.Main), isTrue);
    sizeCall = calls.lastWhere((c) => c.arguments['width'] != null);
    positionCall = calls.lastWhere((c) => c.arguments['x'] != null);
    expect(sizeCall.arguments['width'], 800.0);
    expect(sizeCall.arguments['height'], 600.0);
    expect(positionCall.arguments['x'], 566.0);
    expect(positionCall.arguments['y'], 128.0);
    binding.savedFrame = '';
  }, skip: !Platform.isWindows);

  test('fitWindowBoundsToWorkAreas keeps the monitor with most overlap', () {
    const areas = [
      Rect.fromLTWH(0, 0, 1366, 728),
      Rect.fromLTWH(1366, 0, 1920, 1080),
    ];
    expect(
        fitWindowBoundsToWorkAreas(
            const Rect.fromLTWH(1300, 100, 800, 600), areas),
        const Rect.fromLTWH(1366, 100, 800, 600));
    expect(
        fitWindowBoundsToWorkAreas(
            const Rect.fromLTWH(0, 0, 1920, 1080), [areas.first]),
        areas.first);
    expect(fitWindowBoundsToWorkAreas(Rect.zero, const []), isNull);
  });
}
