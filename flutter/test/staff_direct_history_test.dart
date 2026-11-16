import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/common/widgets/help_history.dart';
import 'package:flutter_hbb/common/widgets/network_help.dart';
import 'package:flutter_hbb/common/widgets/staff_direct_history.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;

  @override
  String mainGetLocalOption({required String key, dynamic hint}) => '';
}

Map<String, dynamic> event(String name) => {
      'name': 'staff-support-$name',
      'id': '123456789',
      'session_id': '42',
      'hostname': 'Lab PC',
    };

void main() {
  setUp(() {
    StaffAuth.loggedIn.value = true;
    StaffAuth.mode = 'staff';
    StaffAuth.username = 'support';
    StaffAuth.helpToken = 'test-staff-token';
    HelpApi.token = null;
    StaffDirectHistory.init();
  });
  tearDown(() {
    StaffAuth.loggedIn.value = false;
    StaffAuth.username = '';
    StaffAuth.helpToken = '';
    StaffAuth.mode = 'staff';
    HelpApi.token = null;
    HelpApi.adminName = null;
    HelpSessionTracker.onEnded = null;
  });

  testWidgets(
      'direct session records once, stays alive and ends without a password',
      (tester) async {
    final requests = <http.Request>[];
    Map<String, dynamic>? ended;
    HelpSessionTracker.onEnded = (item) => ended = item;
    await http.runWithClient(() async {
      await platformFFI.tryHandle(event('connected'));
      await platformFFI.tryHandle(event('connected'));
      await tester.pump(const Duration(seconds: 5));
      await platformFFI.tryHandle(event('disconnected'));
      await tester.pump(const Duration(seconds: 5));
    },
        () => MockClient((request) async {
              requests.add(request);
              return http.Response(
                  jsonEncode({
                    'ok': true,
                    'history_id': 12,
                    'item': {'hid': 12, 'open': false},
                  }),
                  200);
            }));
    expect(requests.map((r) => r.url.path), [
      '/help/api/history/start',
      '/help/api/history/alive',
      '/help/api/history/end',
    ]);
    final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(body.keys, unorderedEquals(['id', 'session_key', 'name']));
    expect(body['id'], '123456789');
    expect(body['name'], 'Lab PC');
    expect(body['session_key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(requests.first.headers['authorization'], 'Bearer test-staff-token');
    expect(jsonDecode(requests[1].body), {
      'ids': [12]
    });
    expect(jsonDecode(requests.last.body), {'id': 12});
    expect(ended, {'hid': 12, 'open': false});
  });

  testWidgets('disconnect during history start ends the returned record',
      (tester) async {
    final response = Completer<http.Response>();
    final paths = <String>[];
    await http.runWithClient(() async {
      final connected = platformFFI.tryHandle(event('connected'));
      await tester.pump();
      final disconnected = platformFFI.tryHandle(event('disconnected'));
      response.complete(http.Response('{"ok":true,"history_id":13}', 200));
      await Future.wait([connected, disconnected]);
      await tester.pump(const Duration(seconds: 6));
    },
        () => MockClient((request) async {
              paths.add(request.url.path);
              return request.url.path.endsWith('/start')
                  ? await response.future
                  : http.Response('{"ok":true}', 200);
            }));
    expect(paths, ['/help/api/history/start', '/help/api/history/end']);
  });

  testWidgets('main window prompts for a note without Helpdesk open',
      (tester) async {
    platformFFI.setBindingForTesting(_Binding());
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: globalKey,
      home: const Scaffold(body: Text('Main page')),
    ));
    await http.runWithClient(() async {
      await platformFFI.tryHandle(event('connected'));
      await platformFFI.tryHandle(event('disconnected'));
      await tester.pumpAndSettle();
      expect(find.text('Main page'), findsOneWidget);
      expect(find.byType(NetworkAdminPanel), findsNothing);
      expect(find.text('Support session ended'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          tester.widget<TextField>(find.byType(TextField)).autofocus, isTrue);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    },
        () => MockClient((request) async => http.Response(
            jsonEncode({
              'ok': true,
              'history_id': 14,
              'item': {'hid': 14, 'id': '123456789', 'open': false},
            }),
            200)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lab and signed-out connections do not create staff history',
      (tester) async {
    final requests = <http.Request>[];
    await http.runWithClient(() async {
      StaffAuth.mode = 'lab';
      await platformFFI.tryHandle(event('connected'));
      StaffAuth.mode = 'staff';
      StaffAuth.loggedIn.value = false;
      await platformFFI.tryHandle(event('connected'));
    },
        () => MockClient((request) async {
              requests.add(request);
              return http.Response('{"ok":true}', 200);
            }));
    expect(requests, isEmpty);
  });
}
