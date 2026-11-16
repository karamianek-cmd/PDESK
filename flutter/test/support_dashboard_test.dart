import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/common/widgets/network_help.dart';
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

const _features = {
  'support_queue': true,
  'history': true,
  'online': true,
  'support_requests': true,
  'staff_approval': false,
};

const _presence = {
  'ok': true,
  'staff': [
    {'username': 'alice', 'full_name': 'Online staff', 'online': true},
    {'username': 'bob', 'full_name': 'Offline staff', 'online': false},
    {'username': 'carol', 'full_name': 'Unknown staff'},
  ],
  'labs': [
    {'id': 1234, 'name': 'Online lab', 'online': true},
    {'id': 5678, 'name': 'Offline lab', 'online': false},
    {'id': 9012, 'name': 'Unknown lab'},
  ],
};

http.Response _reply(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

Widget _host(Widget child, {bool rtl = false, double scale = 1}) => MaterialApp(
      theme: MyTheme.pardisTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: child),
          ),
        ),
      ),
    );

void _resetAuth() {
  HelpApi.token = null;
  HelpApi.adminName = null;
  StaffAuth.loggedIn.value = false;
  StaffAuth.username = '';
  StaffAuth.fullName = '';
  StaffAuth.role = '';
  StaffAuth.mode = 'staff';
  StaffAuth.labId = '';
  StaffAuth.labName = '';
  StaffAuth.helpToken = '';
  StaffAuth.helpAdminName = '';
}

void main() {
  setUp(() {
    _resetAuth();
    platformFFI.setBindingForTesting(_Binding());
    StaffAuth.loggedIn.value = true;
    StaffAuth.username = 'alice';
    HelpApi.token = 'test-staff-token';
    HelpApi.adminName = 'alice';
  });
  tearDown(_resetAuth);

  testWidgets('ordinary staff can browse history and online-only directory',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var openedConnections = false;
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(_host(NetworkAdminPanel(
          dashboard: true,
          onOpenConnections: () => openedConnections = true,
        )));
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(find.text('Support requests'), findsOneWidget);
        expect(find.text('Support history'), findsOneWidget);
        expect(find.text('Who is online'), findsOneWidget);
        expect(find.byTooltip('App features'), findsNothing);
        await tester.tap(find.text('Connect by code'));
        expect(openedConnections, isTrue);

        await tester.tap(find.text('Support history'));
        await tester.pumpAndSettle();
        expect(find.text('Resolved lab PC'), findsOneWidget);
        expect(find.text('Printer fixed'), findsOneWidget);
        expect(find.text('No support sessions yet'), findsNothing);

        await tester.tap(find.text('Who is online'));
        await tester.pumpAndSettle();
        expect(find.text('Online staff'), findsOneWidget);
        expect(find.text('Online lab'), findsOneWidget);
        expect(find.text('1 Online'), findsNWidgets(2));
        for (final name in [
          'Offline staff',
          'Unknown staff',
          'Offline lab',
          'Unknown lab'
        ]) {
          expect(find.text(name), findsNothing);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
        () => MockClient((request) async {
              switch (request.url.path) {
                case '/help/api/features':
                  return _reply({'ok': true, 'features': _features});
                case '/help/api/list':
                  return _reply({'ok': true, 'requests': []});
                case '/help/api/history/list':
                  return _reply({
                    'ok': true,
                    'items': [
                      {
                        'hid': 12,
                        'id': '123456789',
                        'name': 'Resolved lab PC',
                        'ip': '192.0.2.1',
                        'accepted_by': 'alice',
                        'accepted_at': '2026-11-12T10:00:00Z',
                        'duration_sec': 300,
                        'admin_note': 'Printer fixed',
                        'open': false,
                      }
                    ],
                    'more': false,
                    'stats': {'today': 1, 'month': 1},
                  });
                case '/help/api/presence':
                  return _reply(_presence);
                default:
                  return _reply({'ok': false}, 404);
              }
            }));
  });

  testWidgets('narrow RTL respects section and public request permissions',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var features = {..._features, 'support_queue': false, 'history': false};
    final policyRequests = <http.Request>[];
    await http.runWithClient(() async {
      try {
        Widget dashboard(String key) => _host(
              Column(children: [
                Expanded(
                    child: NetworkAdminPanel(
                  key: ValueKey('dashboard-$key'),
                  dashboard: true,
                  onOpenConnections: () {},
                )),
                HelpRequestCard(key: ValueKey('request-$key')),
              ]),
              rtl: true,
              scale: 1.3,
            );
        await tester.pumpWidget(dashboard('online'));
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsOneWidget);
        expect(find.text('Support requests'), findsNothing);
        expect(find.text('Support history'), findsNothing);
        expect(find.text('Online staff'), findsOneWidget);
        expect(find.text('Request support'), findsOneWidget);
        expect(tester.takeException(), isNull);

        features = {for (final key in _features.keys) key: false};
        await tester.pumpWidget(dashboard('disabled'));
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.text('Request support'), findsNothing);
        expect(find.text('Online staff'), findsNothing);
        expect(
            find.text('Features disabled by administrator'), findsNWidgets(2));
        expect(
            policyRequests.where(
                (r) => r.headers['authorization'] == 'Bearer test-staff-token'),
            hasLength(2));
        expect(
            policyRequests
                .where((r) => !r.headers.containsKey('authorization')),
            hasLength(2));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
        () => MockClient((request) async {
              if (request.url.path == '/help/api/features') {
                policyRequests.add(request);
                return _reply({'ok': true, 'features': features});
              }
              if (request.url.path == '/help/api/presence')
                return _reply(_presence);
              return _reply({'ok': false}, 404);
            }));
  });

  testWidgets('narrow RTL dashboard keeps Shabnam and English LTR numbers',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(_host(
            NetworkAdminPanel(dashboard: true, onOpenConnections: () {}),
            rtl: true, scale: 1.3));
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(find.text('Parsipol support')))
            .textTheme.bodyMedium?.fontFamily, 'Shabnam');
        expect(find.text('1'), findsNWidgets(2));
        expect(tester.widget<Text>(find.text('(1234)')).textDirection,
            TextDirection.ltr);
        expect(tester.widget<Text>(find.text('192.0.2.10  ·  123456789'))
            .textDirection, TextDirection.ltr);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Support history'));
        await tester.pumpAndSettle();
        expect(find.text('Printer fixed'), findsOneWidget);
        expect(tester.widget<Text>(find.text('7')).textDirection,
            TextDirection.ltr);
        expect(tester.widget<Text>(find.text('13:30')).textDirection,
            TextDirection.ltr);
        expect(tester.widgetList<Text>(find.byType(Text)).any((text) =>
            RegExp(r'[۰-۹٠-٩]').hasMatch(text.data ?? '')), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/features')) {
        return _reply({'ok': true, 'features': _features});
      }
      if (request.url.path.endsWith('/history/list')) {
        return _reply({
          'ok': true,
          'items': [{
            'hid': 12, 'id': '123456789', 'name': 'Resolved lab PC',
            'ip': '192.0.2.10', 'accepted_by': 'alice',
            'accepted_at': '2026-11-12T10:00:00Z', 'duration_sec': 300,
            'admin_note': 'Printer fixed', 'open': false,
          }],
          'stats': {'today': 7, 'month': 23, 'avg_wait_sec': 300,
            'avg_duration_sec': 600}, 'more': false,
        });
      }
      return _reply({'ok': true, 'requests': [{
        'id': '123456789', 'name': 'Lab PC', 'status': 'waiting',
        'ip': '192.0.2.10', 'lab_name': 'Lab', 'lab_id': 1234,
        'waiting_sec': 180, 'note': 'Needs help', 'has_shot': true,
      }]});
    }));
  });

  testWidgets('admin switch stays unchanged on failure and commits on success',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    HelpApi.adminName = HelpApi.superAdmin;
    final roles = {
      'staff': {'support_queue': true, 'history': true, 'online': true},
      'labs': {'support_requests': true, 'staff_approval': false},
    };
    final responses = [Completer<http.Response>(), Completer<http.Response>()];
    final postedRoles = <dynamic>[];
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(_host(const AppFeatureSettings()));
        await tester.pumpAndSettle();
        expect(find.text('Parsipol staff'), findsOneWidget);
        expect(find.text('Labs'), findsOneWidget);
        final toggle = find
            .widgetWithText(SwitchListTile, 'Handle support requests')
            .first;
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

        await tester.tap(toggle);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        responses[0].complete(_reply({'ok': false}, 500));
        await tester.pumpAndSettle();
        expect(find.text('Changes could not be saved'), findsOneWidget);
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

        await tester.tap(toggle);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        responses[1].complete(_reply({'ok': true}));
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(find.text('Changes could not be saved'), findsNothing);
        expect(postedRoles, [
          for (var i = 0; i < 2; i++)
            {
              'staff': {'support_queue': false, 'history': true, 'online': true},
              'labs': {'support_requests': true, 'staff_approval': false}
            }
        ]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
        () => MockClient((request) async {
              if (request.url.path != '/help/api/features/manage') {
                return _reply({'ok': false}, 404);
              }
              if (request.method == 'GET')
                return _reply({'ok': true, 'roles': roles});
              postedRoles.add(jsonDecode(request.body)['roles']);
              return responses[postedRoles.length - 1].future;
            }));
  });
}
