import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
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

  static Future<HelpResult> request(String id, String name, String password) =>
      _call('POST', '/request',
          body: {'id': id, 'name': name, 'password': password});

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

  Future<void> _turnOn() async {
    if (_id.length < 6 || _password.length < 4 || _password == '-') {
      showToast(translate('Enable one-time password first'));
      return;
    }
    final name = await _askName();
    if (name == null || !mounted) return;
    await bind.mainSetLocalOption(key: _kHelpNameOption, value: name);
    setState(() => _busy = true);
    final ok = await _send(name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    _since = DateTime.now();
    setState(() {
      _on = true;
      _note = translate('Waiting for the network admin');
    });
    _timer?.cancel();
    _timer = Timer.periodic(_refresh, (_) => _tick());
  }

  Future<bool> _send(String name) async {
    _lastId = _id;
    _lastPw = _password;
    final r = await HelpApi.request(_lastId, name, _lastPw);
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
    final r = await HelpApi.request(_lastId, name, pw);
    if (!mounted) return;
    if (r.ok && r.data['status'] == 'claimed') {
      _finish(translate('Network admin is connecting'));
    }
  }

  void _finish(String message) {
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _on = false;
      _note = '';
    });
    showToast(message);
  }

  Future<void> _turnOff() async {
    _timer?.cancel();
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
  Timer? _timer;

  bool get _signedIn => HelpApi.token != null;

  @override
  void initState() {
    super.initState();
    if (_signedIn) _startPolling();
  }

  @override
  void dispose() {
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
      setState(() => _items = []);
      return;
    }
    if (r.ok) {
      setState(() => _items = (r.data['requests'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['status'] == 'waiting')
          .toList());
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
    await HelpApi.logout();
    if (mounted) setState(() => _items = []);
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
    connect(context, r.data['id'] as String,
        password: r.data['password'] as String, isSharedPassword: false);
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

  String _ago(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final m = DateTime.now().toUtc().difference(t).inMinutes;
    return m < 1 ? translate('Just now') : '$m ${translate('min')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: _signedIn ? _list(context) : _form(context),
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
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20)),
            TextButton(onPressed: _signOut, child: Text(translate('Logout'))),
          ],
        ),
        const SizedBox(height: 6),
        Text(translate('Click a system to connect'),
            style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 12),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text(translate('No systems need help'),
                      style: TextStyle(color: muted)))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    final name = (it['name'] ?? '') as String;
                    return Material(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _connect(it),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.desktop_windows_outlined,
                                  color: theme.primaryColor),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        name.isEmpty
                                            ? it['id'] as String
                                            : name,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        '${it['ip']}  ·  ${it['id']}  ·  ${_ago(it['created_at'] as String)}',
                                        textDirection: TextDirection.ltr,
                                        style: TextStyle(
                                            fontSize: 12, color: muted)),
                                  ],
                                ),
                              ),
                              IconButton(
                                  tooltip: translate('Rename'),
                                  onPressed: () => _rename(it),
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 18)),
                              Icon(Icons.chevron_right, color: muted),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
