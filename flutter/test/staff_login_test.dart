import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/common/widgets/staff_login.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Binding extends Fake implements RustdeskImpl {
  final localOptions = <String, String>{};
  final options = <String, String>{};

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;

  @override
  String mainGetLocalOption({required String key, dynamic hint}) =>
      localOptions[key] ?? '';

  @override
  String mainGetOptionSync({required String key, dynamic hint}) =>
      options[key] ?? '';

  @override
  Future<void> mainSetLocalOption(
      {required String key, required String value, dynamic hint}) async {
    localOptions[key] = value;
  }

  @override
  Future<void> mainSetOption(
      {required String key, required String value, dynamic hint}) async {
    options[key] = value;
  }

  @override
  Future<String> mainGetMyId({dynamic hint}) async => '123456789';
}

const _grey = Color(0xFFEFECE4);

void main() {
  testWidgets('lab identity reaches the host service and clears on logout',
      (tester) async {
    final binding = _Binding();
    binding.localOptions.addAll({
      'staff-username': '1234',
      'staff-mode': 'lab',
      'staff-lab-id': '1234',
    });
    platformFFI.setBindingForTesting(binding);
    await http.runWithClient(() async {
      StaffAuth.load();
      await tester.pump();
      expect(binding.options[kOptionStaffLabId], '1234');
      await StaffAuth.logout();
      expect(binding.options[kOptionStaffLabId], '');
      expect(binding.localOptions['staff-lab-id'], '');
    }, () => MockClient((request) async => http.Response('{"ok":true}', 200)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff entrance stays accent-coloured on hover, text in Shabnam',
      (tester) async {
    platformFFI.setBindingForTesting(_Binding());
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(hoverColor: _grey),
      home: const StaffLoginPage(),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    final title = find.text('Parsipol staff');
    final tile = find.ancestor(of: title, matching: find.byType(AnimatedContainer));
    Color tileColor() =>
        ((tester.widget<AnimatedContainer>(tile).decoration as BoxDecoration)
            .color)!;
    final idle = tileColor();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(title));
    await tester.pump(const Duration(milliseconds: 400));

    final hovered = tileColor();
    expect(hovered, isNot(idle));
    expect(hovered, isNot(_grey));
    expect(hovered.computeLuminance(), lessThan(idle.computeLuminance()));
    final inks = tester
        .widgetList<InkWell>(find.ancestor(of: title, matching: find.byType(InkWell)));
    expect(inks.single.hoverColor, Colors.transparent);

    final heading = tester.widget<RichText>(find.descendant(
        of: find.text('Staff login'), matching: find.byType(RichText)));
    expect(heading.text.style?.fontFamily, 'Shabnam');
    expect(find.text('Staff edition'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
