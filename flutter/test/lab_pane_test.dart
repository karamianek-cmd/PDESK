import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/common/widgets/lab_pane.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

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
  Future<void> mainSetOption(
      {required String key, required String value, dynamic hint}) async {
    options[key] = value;
  }
}

void main() {
  test('remembered lab login restores one-time-password modes', () async {
    final binding = _Binding();
    binding.localOptions.addAll({
      'staff-username': '0021',
      'staff-mode': 'lab',
      'staff-lab-id': '0021',
      'staff-lab-name': 'پارسه تهران',
    });
    binding.options.addAll({
      kOptionVerificationMethod: 'use-permanent-password',
      kOptionApproveMode: 'click',
    });
    platformFFI.setBindingForTesting(binding);
    addTearDown(() {
      StaffAuth.username = '';
      StaffAuth.fullName = '';
      StaffAuth.role = '';
      StaffAuth.mode = 'staff';
      StaffAuth.labId = '';
      StaffAuth.labName = '';
      StaffAuth.helpToken = '';
      StaffAuth.helpAdminName = '';
      StaffAuth.loggedIn.value = false;
    });

    StaffAuth.load();
    await Future<void>.delayed(Duration.zero);

    expect(StaffAuth.isLab, isTrue);
    expect(binding.options[kOptionVerificationMethod], 'use-both-passwords');
    expect(binding.options[kOptionApproveMode], 'both');
  });

  testWidgets('lab pane renders the Persian name and ID without an error pane',
      (tester) async {
    platformFFI.setBindingForTesting(_Binding());
    final previousName = StaffAuth.labName;
    final previousId = StaffAuth.labId;
    addTearDown(() {
      StaffAuth.labName = previousName;
      StaffAuth.labId = previousId;
    });
    StaffAuth.labName = 'پارسه تهران';
    StaffAuth.labId = '0021';

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LabNamePane()),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('پارسه تهران'), findsOneWidget);
    expect(find.text('0021'), findsOneWidget);
    final name = tester.widget<Text>(find.text('پارسه تهران'));
    expect(name.textDirection, TextDirection.rtl);
    expect(name.style?.fontFamily, 'Shabnam');
  });
}
