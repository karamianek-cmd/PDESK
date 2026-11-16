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

  // The server enforces cross-staff history and feature-management access.
  static const superAdmin = 'm.ghiasi';
  static bool get isSuperAdmin =>
      (adminName ?? '').toLowerCase() == superAdmin;

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
          {String? note, String? targetStaff, int? labId, String? labName}) =>
      _call('POST', '/request', body: {
        'id': id,
        'name': name,
        'password': password,
        if (note != null) 'note': note,
        if (targetStaff != null) 'target_staff': targetStaff,
        if (labId != null) 'lab_id': labId,
        if (labName != null) 'lab_name': labName,
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

  static Future<HelpResult> historyStart(
          String id, String sessionKey, String name) =>
      _call('POST', '/history/start',
              body: {'id': id, 'session_key': sessionKey, 'name': name}, auth: true)
          .timeout(const Duration(seconds: 15),
              onTimeout: () => HelpResult(false, 0, {}));

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

  static Future<HelpResult> presence() =>
      _call('GET', '/presence', auth: true);

  static Future<HelpResult> features({bool staff = true}) =>
      _call('GET', '/features', auth: staff).timeout(const Duration(seconds: 15),
          onTimeout: () => HelpResult(false, 0, {}));

  static Future<HelpResult> managedFeatures() =>
      _call('GET', '/features/manage', auth: true).timeout(
          const Duration(seconds: 15),
          onTimeout: () => HelpResult(false, 0, {}));

  static Future<HelpResult> saveFeatures(Map<String, dynamic> roles) =>
      _call('POST', '/features/manage', body: {'roles': roles}, auth: true)
          .timeout(const Duration(seconds: 15),
              onTimeout: () => HelpResult(false, 0, {}));

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
  bool _available = false;
  bool _policyLoading = true;
  bool _policyFailed = false;
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

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<bool> _loadPolicy() async {
    final r = await HelpApi.features(staff: false);
    if (!mounted) return false;
    setState(() {
      _policyLoading = false;
      _policyFailed = !r.ok;
      _available = r.ok && r.data['features']?['support_requests'] == true;
    });
    return _available;
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
    setState(() => _busy = true);
    final available = await _loadPolicy();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!available) return;
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
        note: note,
        targetStaff: _target.isEmpty ? null : _target,
        labId: StaffAuth.isLab ? int.tryParse(StaffAuth.labId) : null,
        labName: StaffAuth.isLab ? StaffAuth.labName : null);
    if (!r.ok) {
      showToast(translate(r.status == 403
          ? 'Features disabled by administrator' : 'Cannot reach the server'));
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
        targetStaff: _target.isEmpty ? null : _target,
        labId: StaffAuth.isLab ? int.tryParse(StaffAuth.labId) : null,
        labName: StaffAuth.isLab ? StaffAuth.labName : null);
    if (!mounted) return;
    if (r.status == 403) {
      await _turnOff();
      if (mounted) {
        setState(() => _available = false);
        showToast(translate('Features disabled by administrator'));
      }
    } else if (r.ok && r.data['status'] == 'claimed') {
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.support_agent_rounded, color: cs.primaryColor, size: 26),
          const SizedBox(width: 10),
          Expanded(child: Text(translate('Parsipol support'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
        ]),
        if (_note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_note, style: TextStyle(fontSize: 12, color: muted)),
        ],
        const SizedBox(height: 10),
        if (_busy || _policyLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (_on)
          OutlinedButton.icon(onPressed: _turnOff,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(translate('Cancel')))
        else if (_available)
          FilledButton.icon(onPressed: _turnOn,
              icon: const Icon(Icons.support_agent_rounded, size: 18),
              label: Text(translate('Request support')))
        else ...[
          Text(translate(_policyFailed ? 'Cannot reach the server'
              : 'Features disabled by administrator'),
              style: TextStyle(fontSize: 12, color: muted)),
          TextButton(onPressed: _loadPolicy, child: Text(translate('Refresh'))),
        ],
      ]),
    );
  }
}

// ----------------------------------------------------------------- admin side

class NetworkAdminPanel extends StatefulWidget {
  final bool dashboard;
  final VoidCallback? onOpenConnections;
  const NetworkAdminPanel(
      {super.key, this.dashboard = false, this.onOpenConnections});

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
  int _section = 0;
  Map<String, dynamic>? _features;
  bool _loading = false;
  bool _failed = false;
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

  bool _allows(String feature) =>
      HelpApi.isSuperAdmin || _features?[feature] == true;

  List<int> get _sections => [
        if (_allows('support_queue')) 0,
        if (_allows('history')) 1,
        if (_allows('online')) 2,
      ];

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final policy = await HelpApi.features();
    if (!mounted) return;
    if (!policy.ok) {
      if (policy.status == 401) _timer?.cancel();
      setState(() {
        _loading = false;
        _failed = true;
        _features = null;
        _items = [];
        _inProgress = [];
      });
      return;
    }
    setState(() {
      _features = Map<String, dynamic>.from(policy.data['features'] as Map);
      _failed = false;
      if (!_sections.contains(_section)) {
        _section = _sections.isEmpty ? 0 : _sections.first;
      }
    });
    final r = _allows('support_queue')
        ? await HelpApi.list().timeout(const Duration(seconds: 15),
            onTimeout: () => HelpResult(false, 0, {}))
        : null;
    if (!mounted) return;
    if (r?.status == 401) _timer?.cancel();
    setState(() {
      _loading = false;
      _failed = r != null && !r.ok;
      final all = (r?.data['requests'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _items = all.where((e) => e['status'] == 'waiting').toList();
      _inProgress = all.where((e) => e['status'] == 'claimed').toList();
    });
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
    final accent = PdTokens.accent(context);
    final muted = PdTokens.muted(context);
    final tabs = [
      (0, 'Support requests', Icons.inbox_rounded),
      (1, 'Support history', Icons.history_rounded),
      (2, 'Who is online', Icons.people_alt_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [accent, Color.lerp(accent, const Color(0xFF14232A), 0.45)!],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
            boxShadow: [BoxShadow(color: accent.withOpacity(0.14),
                blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.16))),
                child: const Icon(Icons.support_agent_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(translate(widget.dashboard ? 'Parsipol support' : 'Network admin'),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 21, fontWeight: FontWeight.w700, height: 1.5)),
                  const SizedBox(height: 4),
                  Text(HelpApi.isSuperAdmin
                      ? translate('Super administrator')
                      : StaffAuth.fullName.isNotEmpty
                          ? StaffAuth.fullName
                          : HelpApi.adminName ?? '',
                      textDirection: !HelpApi.isSuperAdmin && StaffAuth.fullName.isEmpty
                          ? TextDirection.ltr : null,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12,
                          color: Colors.white.withOpacity(0.82))),
                ]),
              ),
              IconButton(
                color: Colors.white,
                disabledColor: Colors.white54,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(8),
                tooltip: translate('Refresh'),
                onPressed: _loading ? null : () {
                  _load();
                  _historyKey.currentState?.reload();
                },
                icon: const Icon(Icons.refresh_rounded, size: 20)),
              if (HelpApi.isSuperAdmin)
                IconButton(color: Colors.white,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: const EdgeInsets.all(8),
                    tooltip: translate('App features'),
                    onPressed: () => showAppFeatures(context),
                    icon: const Icon(Icons.tune_rounded, size: 20)),
              if (!widget.dashboard)
                IconButton(color: Colors.white, tooltip: translate('Logout'),
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded, size: 20)),
            ]),
            if (widget.dashboard && widget.onOpenConnections != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: Colors.white.withOpacity(0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: widget.onOpenConnections,
                icon: const Icon(Icons.desktop_windows_outlined, size: 18),
                label: Text(translate('Connect by code'))),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        if (_features != null)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final tab in tabs)
              if (_sections.contains(tab.$1))
                ChoiceChip(
                  showCheckmark: false,
                  selected: _section == tab.$1,
                  selectedColor: accent,
                  backgroundColor: theme.cardColor.withOpacity(0.94),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: _section == tab.$1
                          ? accent : PdTokens.border(context))),
                  labelStyle: TextStyle(fontWeight: FontWeight.w600,
                      color: _section == tab.$1 ? Colors.white : theme.textTheme.bodyMedium?.color),
                  avatar: Icon(tab.$3, size: 18,
                      color: _section == tab.$1 ? Colors.white : accent),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(translate(tab.$2), maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                    if (tab.$1 == 0 && _items.isNotEmpty) ...[
                      const SizedBox(width: 6), _CountBadge(_items.length),
                    ],
                  ]),
                  onSelected: (_) => setState(() => _section = tab.$1)),
          ]),
        const SizedBox(height: 16),
        Expanded(
          child: _features == null
              ? Center(child: _loading
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(translate('Cannot reach the server'),
                          style: TextStyle(color: muted)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: Text(translate('Retry'))),
                    ]))
              : _sections.isEmpty
                  ? Center(child: Text(translate('Features disabled by administrator'),
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium))
                  : switch (_section) {
                      1 => HelpHistoryView(key: _historyKey),
                      2 => const _PresenceView(),
                      _ => _tickets(context),
                    },
        ),
      ],
    );
  }

  Widget _tickets(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    if (_items.isEmpty && _inProgress.isEmpty && _failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(translate('Cannot reach the server')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: Text(translate('Retry'))),
        ]),
      );
    }
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
    final muted = PdTokens.muted(context);
    const f = TehranFormat(false);
    final name = (it['name'] ?? '') as String;
    final wait = it['waiting_sec'] as int?;
    final color = (wait ?? 0) < 300 ? PdTokens.accent(context) : waitColor(wait);
    final first = priority == 1;
    final created = parseServerTime(it['created_at']);
    final labName = (it['lab_name'] ?? '') as String;
    final labId = it['lab_id'] as int? ?? 0;
    return Material(
      color: theme.cardColor.withOpacity(0.96),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _connect(it),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: first ? color.withOpacity(0.55) : PdTokens.border(context),
                width: first ? 1.4 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('$priority', textDirection: TextDirection.ltr,
                    style: TextStyle(color: color,
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(name.isEmpty ? it['id'] as String : name,
                  textDirection: name.isEmpty ? TextDirection.ltr : null,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              if (first) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(translate('Priority'), style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Text('${it['ip']}  ·  ${it['id']}',
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 12, color: muted, letterSpacing: 0.3)),
            if (labName.isNotEmpty || labId > 0) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                Text('${translate('Lab')}: $labName',
                    style: TextStyle(fontSize: 12, color: muted)),
                if (labId > 0) Text('($labId)', textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 12, color: muted)),
              ]),
            ],
            if ((it['note'] ?? '') != '') ...[
              const SizedBox(height: 8),
              Text(it['note'] as String, maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.6)),
            ],
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12, runSpacing: 6, children: [
              Text('${translate('Waiting')}: ${formatDuration(context, wait)}'
                  '${created == null ? '' : '  ·  \u2066${f.time(created)}\u2069'}',
                  style: TextStyle(fontSize: 12, color: color,
                      fontWeight: FontWeight.w600)),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (it['has_shot'] == true)
                  IconButton(tooltip: translate('Screenshot'),
                      onPressed: () => _showShot(it),
                      icon: Icon(Icons.image_outlined, size: 20, color: muted)),
                IconButton(tooltip: translate('Rename'),
                    onPressed: () => _rename(it),
                    icon: Icon(Icons.edit_outlined, size: 18, color: muted)),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                    onPressed: () => _connect(it),
                    icon: const Icon(Icons.desktop_windows_outlined, size: 16),
                    label: Text(translate('Accept'))),
              ]),
            ]),
          ]),
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
          color: const Color(0xFF14232A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$count', textDirection: TextDirection.ltr,
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
                                  title: Row(children: [
                                    Flexible(
                                      child: Text(s.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (s.online) ...[
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: translate('Online'),
                                        child: const Icon(Icons.lightbulb,
                                            size: 16, color: Colors.green),
                                      ),
                                    ],
                                  ]),
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

// ------------------------------------------------------------ online directory
class _PresenceView extends StatefulWidget {
  const _PresenceView();

  @override
  State<_PresenceView> createState() => _PresenceViewState();
}

class _PresenceViewState extends State<_PresenceView> {
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _labs = [];
  bool _loading = false;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final r = await HelpApi.presence().timeout(const Duration(seconds: 15),
        onTimeout: () => HelpResult(false, 0, {}));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = !r.ok;
      if (!r.ok) {
        _staff = [];
        _labs = [];
        return;
      }
      _staff = (r.data['staff'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['online'] == true)
          .toList();
      _labs = (r.data['labs'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['online'] == true)
          .toList();
      _staff.sort((a, b) => ((a['full_name'] ?? '') as String)
          .compareTo((b['full_name'] ?? '') as String));
      _labs.sort((a, b) => ((a['name'] ?? '') as String)
          .compareTo((b['name'] ?? '') as String));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    const f = TehranFormat(false);
    final staffOnline = _staff.where((e) => e['online'] == true).length;
    final labsOnline = _labs.where((e) => e['online'] == true).length;

    if (_failed && _staff.isEmpty && _labs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: muted),
          const SizedBox(height: 8),
          Text(translate('Cannot reach the server'),
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: Text(translate('Retry'))),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(Icons.wifi_tethering_rounded, color: theme.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(translate('Who is online'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (_loading)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
                tooltip: translate('Refresh'),
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              if (staffOnline == 0 && labsOnline == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(translate('No one is online'),
                      style: TextStyle(fontSize: 13, color: muted)),
                ),
              _sectionHeader(
                  translate('Parsipol staff'), staffOnline, f, muted),
              ..._staff.map((e) => _presenceTile(
                  (e['full_name'] ?? '') as String,
                  (e['username'] ?? '') as String,
                  Icons.support_agent_rounded,
                  muted)),
              const SizedBox(height: 12),
              _sectionHeader(translate('Labs'), labsOnline, f, muted),
              ..._labs.map((e) => _presenceTile((e['name'] ?? '') as String,
                  '${e['id'] ?? ''}', Icons.science_outlined, muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
      String title, int online, TehranFormat f, Color? muted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
        ),
        Text('${f.number(online)} ${translate('Online')}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _presenceTile(
      String title, String subtitle, IconData icon, Color? muted) {
    final accent = PdTokens.accent(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PdTokens.border(context))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: accent.withOpacity(0.09),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: accent, size: 22)),
        title: Text(title.isEmpty ? subtitle : title,
            textDirection: title.isEmpty ? TextDirection.ltr : null,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: title.isEmpty
            ? null
            : Text(subtitle,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted, letterSpacing: 0.3)),
        trailing: Tooltip(message: translate('Online'),
            child: const Icon(Icons.circle, size: 9, color: Color(0xFF23846C))),
      ),
    );
  }
}

Future<void> showAppFeatures(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 640,
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(children: [
          Align(alignment: AlignmentDirectional.centerEnd,
              child: IconButton(tooltip: translate('Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close))),
          const Expanded(child: AppFeatureSettings()),
        ]),
      ),
    ));

class AppFeatureSettings extends StatefulWidget {
  const AppFeatureSettings({super.key});

  @override
  State<AppFeatureSettings> createState() => _AppFeatureSettingsState();
}

class _AppFeatureSettingsState extends State<AppFeatureSettings> {
  Map<String, dynamic>? _roles;
  bool _busy = false;
  String _error = '';
  static const _labels = {
    'support_queue': 'Handle support requests',
    'history': 'Support history',
    'online': 'Who is online',
    'support_requests': 'Request support',
    'staff_approval': 'Staff approval bypass',
  };

  @override
  void initState() {
    super.initState();
    HelpApi.adoptStaffToken();
    _load();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _error = ''; });
    final r = await HelpApi.managedFeatures();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _roles = Map<String, dynamic>.from(r.data['roles'] as Map);
      } else {
        _error = translate(r.status == 403
            ? 'Only the super administrator can manage features'
            : 'Cannot reach the server');
      }
    });
  }

  Future<void> _save(String role, String feature, bool enabled) async {
    final roles = {for (final e in _roles!.entries)
      e.key: Map<String, dynamic>.from(e.value as Map)};
    roles[role]![feature] = enabled;
    setState(() { _busy = true; _error = ''; });
    final r = await HelpApi.saveFeatures(roles);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _roles = roles;
      } else {
        _error = translate('Changes could not be saved');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = PdTokens.accent(context);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Icon(Icons.tune_rounded, color: accent),
        const SizedBox(width: 10),
        Expanded(child: Text(translate('App features'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
        IconButton(tooltip: translate('Refresh'), onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded)),
      ]),
      const SizedBox(height: 10),
      Text(translate('Changes apply on the next refresh. Active sessions and security remain protected.'),
          style: TextStyle(color: PdTokens.muted(context), height: 1.6)),
      if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(minHeight: 2)),
      if (_error.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(_error, style: TextStyle(color: theme.colorScheme.error)),
        if (_roles == null)
          Align(alignment: AlignmentDirectional.centerStart,
              child: TextButton(onPressed: _busy ? null : _load,
                  child: Text(translate('Retry')))),
      ],
      if (_roles != null)
        for (final role in ['staff', 'labs']) ...[
          const SizedBox(height: 20),
          Row(children: [
            Icon(role == 'staff' ? Icons.support_agent_rounded : Icons.science_outlined,
                color: accent, size: 20),
            const SizedBox(width: 8),
            Text(translate(role == 'staff' ? 'Parsipol staff' : 'Labs'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor)),
            child: Column(children: [
              for (final feature in (_roles![role] as Map).keys)
                SwitchListTile.adaptive(
                  title: Text(translate(_labels[feature] ?? feature)),
                  subtitle: feature == 'staff_approval'
                      ? Text(translate('Bypasses click-only approval for verified staff with a valid password.'))
                      : feature == 'history'
                          ? Text(translate('Hides browsing only; sessions are still recorded.'))
                          : null,
                  value: _roles![role][feature] == true,
                  onChanged: _busy ? null : (v) => _save(role, feature as String, v)),
            ]),
          ),
        ],
    ]);
  }
}
