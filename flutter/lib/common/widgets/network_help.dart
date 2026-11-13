import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/common/jalali.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/common/widgets/help_history.dart';
import 'package:flutter_hbb/desktop/widgets/help_request_dialog.dart';
import 'package:flutter_hbb/desktop/widgets/parsidesk_brand.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

// Network-admin help for systems on the Parsipol network.
//
// A client switches "Need network admin help" on and the app registers its ID and its current
// one-time password with the Parsipol server. A network admin signs in from the app, sees the
// waiting systems and connects with one click, without typing a password.

const String _kHelpBase = 'https://desk.parsipol.com/help/api';
const String _kHelpNameOption = 'help-device-name';

class HelpResult {
  final bool ok;
  final int status;
  final Map<String, dynamic> data;
  HelpResult(this.ok, this.status, this.data);
}

class HelpApi {
  static String? token;
  static String? adminName;

  static Future<HelpResult> _call(String method, String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    try {
      final uri = Uri.parse('$_kHelpBase$path');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (auth && token != null) 'Authorization': 'Bearer $token',
      };
      final r = method == 'GET'
          ? await http.get(uri, headers: headers)
          : await http.post(uri,
              headers: headers, body: jsonEncode(body ?? {}));
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      if (auth && r.statusCode == 401) token = null;
      return HelpResult(
          r.statusCode == 200 && data['ok'] == true, r.statusCode, data);
    } catch (_) {
      return HelpResult(false, 0, {});
    }
  }

  // note: null keeps the note stored on the server (refreshes and older apps send none).
  // targetStaff: null broadcasts to every admin; a username routes the request
  // only to that ParsiPol staff member.
  static Future<HelpResult> request(String id, String name, String password,
          {String? note, String? targetStaff}) =>
      _call('POST', '/request', body: {
        'id': id,
        'name': name,
        'password': password,
        if (note != null) 'note': note,
        if (targetStaff != null) 'target_staff': targetStaff,
      });

  // Staff sign in through StaffAuth; the server mints their help-admin token,
  // so the admin panel opens without asking for admin credentials again.
  static void adoptStaffToken() {
    if (token == null && StaffAuth.isStaff && StaffAuth.helpToken.isNotEmpty) {
      token = StaffAuth.helpToken;
      adminName = StaffAuth.helpAdminName.isNotEmpty
          ? StaffAuth.helpAdminName
          : StaffAuth.username;
    }
  }

  static Future<HelpResult> attach(String id, String password, String shot) =>
      _call('POST', '/attach',
          body: {'id': id, 'password': password, 'shot': shot});

  static Future<HelpResult> shot(String id) =>
      _call('POST', '/shot', body: {'id': id}, auth: true);

  static Future<HelpResult> historyList({String q = '', int before = 0}) =>
      _call('POST', '/history/list',
          body: {'q': q, 'before': before, 'limit': 50}, auth: true);

  static Future<HelpResult> historyAlive(List<int> ids) =>
      _call('POST', '/history/alive', body: {'ids': ids}, auth: true);

  static Future<HelpResult> historyEnd(int id) =>
      _call('POST', '/history/end', body: {'id': id}, auth: true);

  static Future<HelpResult> historyNote(int id, String note) =>
      _call('POST', '/history/note',
          body: {'id': id, 'note': note}, auth: true);

  static Future<HelpResult> cancel(String id, String password) =>
      _call('POST', '/cancel', body: {'id': id, 'password': password});

  static Future<bool> login(String username, String password) async {
    final r = await _call('POST', '/admin-login',
        body: {'username': username, 'password': password});
    if (r.ok) {
      token = r.data['token'] as String?;
      adminName = r.data['username'] as String?;
    }
    return r.ok;
  }

  static Future<void> logout() async {
    await _call('POST', '/admin-logout', auth: true);
    token = null;
    adminName = null;
  }

  static Future<HelpResult> list() => _call('GET', '/list', auth: true);

  static Future<HelpResult> claim(String id) =>
      _call('POST', '/claim', body: {'id': id}, auth: true);

  static Future<HelpResult> rename(String id, String name) =>
      _call('POST', '/rename', body: {'id': id, 'name': name}, auth: true);
}

// ---------------------------------------------------------------- client side

class HelpRequestCard extends StatefulWidget {
  const HelpRequestCard({super.key});

  @override
  State<HelpRequestCard> createState() => _HelpRequestCardState();
}

class _HelpRequestCardState extends State<HelpRequestCard> {
  static const _refresh = Duration(seconds: 40);
  static const _maxOn = Duration(minutes: 30);

  bool _on = false;
  bool _busy = false;
  String _note = '';
  Timer? _timer;
  DateTime? _since;
  String _lastId = '';
  String _lastPw = '';
  String _target = '';
  String _targetName = '';

  String get _id =>
      gFFI.serverModel.serverId.text.replaceAll(RegExp(r'\s'), '');
  String get _password => gFFI.serverModel.serverPasswd.text.trim();

  String _defaultName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_on) HelpApi.cancel(_lastId, _lastPw);
    super.dispose();
  }

  Future<String?> _askName() async {
    final saved = bind.mainGetLocalOption(key: _kHelpNameOption);
    final c =
        TextEditingController(text: saved.isEmpty ? _defaultName() : saved);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translate('Need network admin help')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('help_request_tip'),
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 40,
              decoration: InputDecoration(labelText: translate('Device name')),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(translate('Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(translate('OK'))),
        ],
      ),
    );
  }

  Future<StaffEntry?> _pickSupportStaff() => showDialog<StaffEntry>(
      context: context, builder: (_) => const _StaffPickerDialog());

  Future<void> _turnOn() async {
    if (_id.length < 6 || _password.length < 4 || _password == '-') {
      showToast(translate('Enable one-time password first'));
      return;
    }
    // Lab members choose which ParsiPol staff member should help them.
    if (StaffAuth.isLab) {
      final staff = await _pickSupportStaff();
      if (staff == null || !mounted) return;
      _target = staff.username;
      _targetName = staff.displayName;
    }
    // Windows asks for an optional note and screenshot as well.
    HelpRequestInput? input;
    if (isWindows) {
      final saved = bind.mainGetLocalOption(key: _kHelpNameOption);
      input = await showHelpRequestDialog(
          context, saved.isEmpty ? _defaultName() : saved);
    } else {
      final name = await _askName();
      if (name != null) input = HelpRequestInput(name, '', null);
    }
    if (input == null || !mounted) return;
    final name = input.name;
    await bind.mainSetLocalOption(key: _kHelpNameOption, value: name);
    setState(() => _busy = true);
    final ok = await _send(name, note: isWindows ? input.note : null);
    if (ok && input.shot != null) {
      final r =
          await HelpApi.attach(_lastId, _lastPw, base64Encode(input.shot!));
      if (!r.ok) showToast(translate('The screenshot could not be sent'));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    _since = DateTime.now();
    setState(() {
      _on = true;
      _note = _targetName.isEmpty
          ? translate('Waiting for the network admin')
          : '${translate('Waiting for the network admin')} · $_targetName';
    });
    _timer?.cancel();
    _timer = Timer.periodic(_refresh, (_) => _tick());
  }

  Future<bool> _send(String name, {String? note}) async {
    _lastId = _id;
    _lastPw = _password;
    final r = await HelpApi.request(_lastId, name, _lastPw,
        note: note, targetStaff: _target.isEmpty ? null : _target);
    if (!r.ok) {
      showToast(translate('Cannot reach the server'));
      return false;
    }
    if (r.data['status'] == 'claimed') {
      _finish(translate('Network admin is connecting'));
      return false;
    }
    return true;
  }

  Future<void> _tick() async {
    if (!_on) return;
    if (DateTime.now().difference(_since!) > _maxOn) {
      _finish(translate('Help request expired'));
      return;
    }
    final name = bind.mainGetLocalOption(key: _kHelpNameOption);
    final pw = _password;
    if (_id.length < 6 || pw.length < 4 || pw == '-') return;
    _lastId = _id;
    _lastPw = pw;
    final r = await HelpApi.request(_lastId, name, pw,
        targetStaff: _target.isEmpty ? null : _target);
    if (!mounted) return;
    if (r.ok && r.data['status'] == 'claimed') {
      _finish(translate('Network admin is connecting'));
    }
  }

  void _finish(String message) {
    _timer?.cancel();
    _target = '';
    _targetName = '';
    if (!mounted) return;
    setState(() {
      _on = false;
      _note = '';
    });
    showToast(message);
  }

  Future<void> _turnOff() async {
    _timer?.cancel();
    _target = '';
    _targetName = '';
    setState(() {
      _on = false;
      _note = '';
    });
    await HelpApi.cancel(_lastId, _lastPw);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context);
    final muted = cs.textTheme.bodySmall?.color?.withOpacity(0.65);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: cs.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _on ? cs.colorScheme.secondary : cs.dividerColor,
            width: _on ? 1.4 : 1),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent,
              color: _on ? cs.primaryColor : muted, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(translate('Need network admin help'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (_note.isNotEmpty)
                  Text(_note, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(
              value: _on,
              onChanged: (v) => v ? _turnOn() : _turnOff(),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- admin side

class NetworkAdminPanel extends StatefulWidget {
  const NetworkAdminPanel({super.key});

  @override
  State<NetworkAdminPanel> createState() => _NetworkAdminPanelState();
}

class _NetworkAdminPanelState extends State<NetworkAdminPanel> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String _error = '';
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _inProgress = [];
  int _section = 0; // 0 tickets, 1 history
  final _historyKey = GlobalKey<HelpHistoryViewState>();
  Timer? _timer;

  bool get _signedIn => HelpApi.token != null;

  @override
  void initState() {
    super.initState();
    HelpApi.adoptStaffToken();
    if (_signedIn) _startPolling();
    HelpSessionTracker.onEnded = _onSessionEnded;
  }

  void _onSessionEnded(Map<String, dynamic> item) {
    if (!mounted) return;
    _historyKey.currentState?.reload();
    showHistoryEntryDialog(context, item, justEnded: true)
        .then((_) => _historyKey.currentState?.reload());
  }

  @override
  void dispose() {
    if (HelpSessionTracker.onEnded == _onSessionEnded) {
      HelpSessionTracker.onEnded = null;
    }
    _timer?.cancel();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _startPolling() {
    _timer?.cancel();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  Future<void> _load() async {
    final r = await HelpApi.list();
    if (!mounted) return;
    if (r.status == 401) {
      _timer?.cancel();
      setState(() {
        _items = [];
        _inProgress = [];
      });
      return;
    }
    if (r.ok) {
      final all = (r.data['requests'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // The server lists the oldest request first: that one is priority 1.
      setState(() {
        _items = all.where((e) => e['status'] == 'waiting').toList();
        _inProgress = all.where((e) => e['status'] == 'claimed').toList();
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final ok = await HelpApi.login(_user.text.trim(), _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = translate('Wrong username or password');
    });
    if (ok) {
      _pass.clear();
      _startPolling();
    }
  }

  Future<void> _signOut() async {
    _timer?.cancel();
    final wasStaff = StaffAuth.isStaff;
    await HelpApi.logout();
    // Staff hold no separate admin password: signing out ends the whole session.
    if (wasStaff) await StaffAuth.logout();
    if (!mounted) return;
    setState(() {
      _items = [];
      _inProgress = [];
    });
    if (wasStaff) Navigator.of(context).maybePop();
  }

  Future<void> _connect(Map<String, dynamic> item) async {
    final r = await HelpApi.claim(item['id'] as String);
    if (!mounted) return;
    if (!r.ok) {
      showToast(translate('Failed'));
      _load();
      return;
    }
    setState(() => _items.removeWhere((e) => e['id'] == item['id']));
    final hid = r.data['history_id'];
    if (hid is int) HelpSessionTracker.start(hid, r.data['id'] as String);
    connect(context, r.data['id'] as String,
        password: r.data['password'] as String, isSharedPassword: false);
  }

  Future<void> _showShot(Map<String, dynamic> item) async {
    final r = await HelpApi.shot(item['id'] as String);
    if (!mounted) return;
    Uint8List? bytes;
    try {
      if (r.ok) bytes = base64Decode(r.data['image'] as String);
    } catch (_) {}
    if (bytes == null) {
      showToast(translate('Failed'));
      return;
    }
    final name = (item['name'] ?? '') as String;
    final sz = MediaQuery.of(context).size;
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name.isEmpty ? item['id'] as String : name),
        content: SizedBox(
          width: sz.width < 940 ? sz.width - 80 : 900,
          height: sz.height < 640 ? sz.height - 160 : 560,
          child: InteractiveViewer(
              maxScale: 5, child: Image.memory(bytes!, fit: BoxFit.contain)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(translate('Close'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(translate('Accept'))),
        ],
      ),
    );
    if (accept == true && mounted) _connect(item);
  }

  Future<void> _rename(Map<String, dynamic> item) async {
    final c = TextEditingController(text: (item['name'] ?? '') as String);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translate('Rename')),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(labelText: translate('Device name')),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(translate('Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(translate('OK'))),
        ],
      ),
    );
    if (v == null) return;
    await HelpApi.rename(item['id'] as String, v);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: _signedIn
          ? _list(context)
          : StaffAuth.isStaff
              ? _expiredView(context)
              : _form(context),
    );
  }

  Widget _expiredView(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.65);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_clock_outlined, size: 40, color: muted),
        const SizedBox(height: 12),
        Text(translate('Admin session expired'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        ElevatedButton(
            onPressed: () async {
              await HelpApi.logout();
              await StaffAuth.logout();
            },
            child: Text(translate('Login again'))),
      ]),
    );
  }

  Widget _form(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(Icons.admin_panel_settings_outlined,
                size: 44, color: Theme.of(context).primaryColor),
            const SizedBox(height: 10),
            Text(translate('Network admin'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            TextField(
              controller: _user,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              autocorrect: false,
              decoration: InputDecoration(labelText: translate('Username')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              obscureText: _hide,
              autocorrect: false,
              onSubmitted: (_) => _signIn(),
              decoration: InputDecoration(
                labelText: translate('Password'),
                suffixIcon: IconButton(
                  icon: Icon(_hide ? Icons.visibility_off : Icons.visibility,
                      size: 20),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13)),
              ),
            const SizedBox(height: 18),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _busy ? null : _signIn,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(translate('Login')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.support_agent, color: theme.primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(translate('Network admin'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Text(HelpApi.adminName ?? '',
                style: TextStyle(fontSize: 12, color: muted),
                textDirection: TextDirection.ltr),
            IconButton(
                tooltip: translate('Refresh'),
                onPressed: () {
                  _load();
                  _historyKey.currentState?.reload();
                },
                icon: const Icon(Icons.refresh, size: 20)),
            TextButton(onPressed: _signOut, child: Text(translate('Logout'))),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.confirmation_number_outlined, size: 18),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(translate('Tickets')),
                if (_items.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _CountBadge(_items.length),
                ],
              ]),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: Text(translate('History')),
            ),
          ],
          selected: {_section},
          onSelectionChanged: (s) => setState(() => _section = s.first),
        ),
        const SizedBox(height: 12),
        Expanded(
          // Both sections stay alive so switching keeps the search and scroll.
          child: IndexedStack(
            index: _section,
            children: [
              _tickets(context),
              HelpHistoryView(key: _historyKey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tickets(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    if (_items.isEmpty && _inProgress.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 40, color: muted),
          const SizedBox(height: 8),
          Text(translate('No systems need help'),
              style: TextStyle(color: muted)),
        ]),
      );
    }
    return ListView(
      children: [
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                translate(
                    'Oldest request first: priority 1 has waited longest'),
                style: TextStyle(fontSize: 12, color: muted)),
          ),
        for (var i = 0; i < _items.length; i++) ...[
          _ticketCard(context, _items[i], i + 1),
          const SizedBox(height: 8),
        ],
        if (_inProgress.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Text(translate('In progress'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
          ),
          for (final it in _inProgress) _inProgressRow(context, it),
        ],
      ],
    );
  }

  Widget _ticketCard(
      BuildContext context, Map<String, dynamic> it, int priority) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    final f = TehranFormat(Directionality.of(context) == TextDirection.rtl);
    final name = (it['name'] ?? '') as String;
    final wait = it['waiting_sec'] as int?;
    final color = waitColor(wait);
    final first = priority == 1;
    final created = parseServerTime(it['created_at']);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _connect(it),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: first ? color : theme.dividerColor,
                width: first ? 1.6 : 1),
          ),
          child: Row(
            children: [
              // Priority number, coloured by how long the system has waited.
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(f.number(priority),
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(name.isEmpty ? it['id'] as String : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (first) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(translate('Priority'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text('${it['ip']}  ·  ${it['id']}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 2),
                    Text(
                        '${translate('Waiting')}: ${formatDuration(context, wait)}'
                        '${created == null ? '' : '  ·  ${f.time(created)}'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w600)),
                    if ((it['note'] ?? '') != '')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(it['note'] as String,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
              if (it['has_shot'] == true)
                IconButton(
                    tooltip: translate('Screenshot'),
                    onPressed: () => _showShot(it),
                    icon: const Icon(Icons.image_outlined, size: 20)),
              IconButton(
                  tooltip: translate('Rename'),
                  onPressed: () => _rename(it),
                  icon: const Icon(Icons.edit_outlined, size: 18)),
              const SizedBox(width: 4),
              ElevatedButton(
                  onPressed: () => _connect(it),
                  child: Text(translate('Accept'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inProgressRow(BuildContext context, Map<String, dynamic> it) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    final name = (it['name'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.headset_mic_outlined, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name.isEmpty ? it['id'] as String : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text('${translate('Accepted by')} ',
              style: TextStyle(fontSize: 12, color: muted)),
          Text('${it['claimed_by'] ?? ''}',
              textDirection: TextDirection.ltr,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge(this.count);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
            TehranFormat(Directionality.of(context) == TextDirection.rtl)
                .number(count),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

// ------------------------------------------------------------------ entrances

// Right-pane entrance for signed-in ParsiPol staff: opens the admin panel
// already authenticated with the token minted at staff login.
class AdminEntranceButton extends StatelessWidget {
  const AdminEntranceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.65);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Material(
        color: PdTokens.surface(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openAdminPanel(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PdTokens.border(context)),
            ),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PdTokens.accent(context).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.admin_panel_settings_rounded,
                    size: 20, color: PdTokens.accent(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate('Admin panel'),
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(translate('Support requests and history'),
                        style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: muted),
            ]),
          ),
        ),
      ),
    );
  }
}

void openAdminPanel(BuildContext context) {
  HelpApi.adoptStaffToken();
  showDialog(
      context: context,
      builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 720),
              child: const SizedBox.expand(child: NetworkAdminPanel()))));
}

// ------------------------------------------------------- support staff picker

class _StaffPickerDialog extends StatefulWidget {
  const _StaffPickerDialog();

  @override
  State<_StaffPickerDialog> createState() => _StaffPickerDialogState();
}

class _StaffPickerDialogState extends State<_StaffPickerDialog> {
  final _search = TextEditingController();
  List<StaffEntry> _staff = [];
  String _query = '';
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final staff = await StaffDirectory.load();
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = translate('Cannot load the staff list');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.65);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _staff
        : _staff
            .where((s) =>
                s.displayName.toLowerCase().contains(q) ||
                s.username.toLowerCase().contains(q))
            .toList();
    return AlertDialog(
      title: Text(translate('Choose support staff')),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('Who should help you?'),
                style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: translate('Search staff'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error.isNotEmpty
                      ? Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error,
                                    style:
                                        TextStyle(fontSize: 13, color: muted)),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                    onPressed: _load,
                                    child: Text(translate('Retry'))),
                              ]))
                      : shown.isEmpty
                          ? Center(
                              child: Text(translate('No results'),
                                  style: TextStyle(fontSize: 13, color: muted)))
                          : ListView.builder(
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final s = shown[i];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: PdTokens.accent(context)
                                        .withOpacity(0.12),
                                    child: Icon(Icons.person_rounded,
                                        size: 20,
                                        color: PdTokens.accent(context)),
                                  ),
                                  title: Text(s.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(s.username,
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                          fontSize: 12, color: muted)),
                                  onTap: () => Navigator.pop(context, s),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translate('Cancel'))),
      ],
    );
  }
}
