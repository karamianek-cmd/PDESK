import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// Staff-edition login. Parsipol staff sign in with a password; lab users sign in
// with their 4-digit Lab ID alone.
// The Parsipol server holds the directory service account and does the verification;
// only the resulting identity is kept on this device, never a password.
class StaffAuth {
  static const _kBase = 'https://desk.parsipol.com/help/api';
  static const _kUserOption = 'staff-username';
  static const _kNameOption = 'staff-fullname';
  static const _kRoleOption = 'staff-role';
  static const _kModeOption = 'staff-mode';
  static const _kLabIdOption = 'staff-lab-id';
  static const _kLabNameOption = 'staff-lab-name';
  static const _kHelpTokenOption = 'staff-help-token';
  static const _kHelpAdminOption = 'staff-help-admin';

  static final loggedIn = false.obs;
  static String username = '';
  static String fullName = '';
  static String role = '';
  static String mode = 'staff';
  static String labId = '';
  static String labName = '';
  // Help-admin session minted by the server on staff login (no admin password).
  static String helpToken = '';
  static String helpAdminName = '';

  // Presence heartbeat so the super-admin can see who is online and labs can see
  // which staff are available. Staff beat with their help token, labs with Lab ID.
  static Timer? _presenceTimer;
  static const _presencePeriod = Duration(seconds: 60);

  static bool get isLab => loggedIn.value && mode == 'lab';
  static bool get isStaff => loggedIn.value && mode == 'staff';

  static void load() {
    username = bind.mainGetLocalOption(key: _kUserOption);
    fullName = bind.mainGetLocalOption(key: _kNameOption);
    role = bind.mainGetLocalOption(key: _kRoleOption);
    mode = bind.mainGetLocalOption(key: _kModeOption) == 'lab' ? 'lab' : 'staff';
    labId = bind.mainGetLocalOption(key: _kLabIdOption);
    labName = bind.mainGetLocalOption(key: _kLabNameOption);
    helpToken = bind.mainGetLocalOption(key: _kHelpTokenOption);
    helpAdminName = bind.mainGetLocalOption(key: _kHelpAdminOption);
    loggedIn.value = username.isNotEmpty;
    if (isLab) _ensureLabOtp();
    if (loggedIn.value) _startPresence();
  }

  // Lab support needs a running service with one-time passwords enabled.
  static Future<void> _ensureLabOtp() async {
    if (bind.mainGetOptionSync(key: kOptionVerificationMethod) ==
        'use-permanent-password') {
      await bind.mainSetOption(
          key: kOptionVerificationMethod, value: 'use-both-passwords');
    }
    if (bind.mainGetOptionSync(key: kOptionApproveMode) == 'click') {
      await bind.mainSetOption(key: kOptionApproveMode, value: 'both');
    }
    // Starting an installed Windows service can relaunch the application.
    if (bind.mainGetOptionSync(key: kOptionStopService) == 'Y') {
      await bind.mainSetOption(key: kOptionStopService, value: '');
    }
  }

  static void _startPresence() {
    _presenceTimer?.cancel();
    _presenceBeat();
    _presenceTimer = Timer.periodic(_presencePeriod, (_) => _presenceBeat());
  }

  static void _stopPresence() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  static Future<void> _presenceBeat() async {
    if (!loggedIn.value) return;
    final headers = <String, String>{'Content-Type': 'application/json'};
    Map<String, dynamic> body = {};
    if (isStaff && helpToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $helpToken';
    } else if (isLab && labId.isNotEmpty) {
      body = {'lab_id': labId};
    } else {
      return;
    }
    try {
      await http
          .post(Uri.parse('$_kBase/presence/beat'),
              headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  // Human-readable identity shown in Settings / About.
  static String get accountLabel {
    if (mode == 'lab') {
      final name = labName.isNotEmpty ? labName : labId;
      return labName.isNotEmpty && labId.isNotEmpty ? '$name ($labId)' : name;
    }
    final parts = <String>[fullName];
    if (role.isNotEmpty) parts.add('($role)');
    return parts.join(' ');
  }

  // Returns null on success, otherwise an error key for translate().
  static Future<String?> login(String user, String pass) async {
    try {
      final r = await http
          .post(Uri.parse('$_kBase/staff-login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': user, 'password': pass}))
          .timeout(const Duration(seconds: 30));
      final data =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (r.statusCode == 200 && data['ok'] == true) {
        username = user;
        fullName = (data['full_name'] as String?) ?? '';
        role = (data['role'] as String?) ?? '';
        mode = 'staff';
        labId = '';
        labName = '';
        helpToken = (data['admin_token'] as String?) ?? '';
        helpAdminName = (data['admin_username'] as String?) ?? user;
        await _persist();
        loggedIn.value = true;
        _startPresence();
        return null;
      }
      if (r.statusCode == 401) return 'Invalid username or password';
      if (r.statusCode == 403) return 'This account is disabled';
      if (r.statusCode == 429) return 'Too many attempts, try again later';
      return 'Cannot reach the staff server';
    } catch (_) {
      return 'Cannot reach the staff server';
    }
  }

  // Lab login: the 4-digit Lab ID alone signs the device in; the server
  // checks it against the active lab directory.
  static Future<String?> loginLab(String labId) async {
    try {
      final r = await http
          .post(Uri.parse('$_kBase/lab-login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'lab_id': labId}))
          .timeout(const Duration(seconds: 40));
      final data =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (r.statusCode == 200 && data['ok'] == true) {
        username = labId;
        fullName = (data['lab_name'] as String?) ?? '';
        role = '';
        mode = 'lab';
        StaffAuth.labId = labId;
        labName = fullName;
        helpToken = '';
        helpAdminName = '';
        await _persist();
        await _ensureLabOtp();
        loggedIn.value = true;
        _startPresence();
        return null;
      }
      if (r.statusCode == 400) return 'Invalid Lab ID';
      if (r.statusCode == 429) return 'Too many attempts, try again later';
      return 'Cannot reach the staff server';
    } catch (_) {
      return 'Cannot reach the staff server';
    }
  }

  static Future<void> _persist() async {
    await bind.mainSetLocalOption(key: _kUserOption, value: username);
    await bind.mainSetLocalOption(key: _kNameOption, value: fullName);
    await bind.mainSetLocalOption(key: _kRoleOption, value: role);
    await bind.mainSetLocalOption(key: _kModeOption, value: mode);
    await bind.mainSetLocalOption(key: _kLabIdOption, value: labId);
    await bind.mainSetLocalOption(key: _kLabNameOption, value: labName);
    await bind.mainSetLocalOption(key: _kHelpTokenOption, value: helpToken);
    await bind.mainSetLocalOption(key: _kHelpAdminOption, value: helpAdminName);
  }

  static Future<void> logout() async {
    _stopPresence();
    username = '';
    fullName = '';
    role = '';
    mode = 'staff';
    labId = '';
    labName = '';
    helpToken = '';
    helpAdminName = '';
    await _persist();
    loggedIn.value = false;
  }
}

// One ParsiPol staff member selectable as a support target (name + username only).
class StaffEntry {
  final String username;
  final String fullName;
  final bool online;
  const StaffEntry(this.username, this.fullName, {this.online = false});

  String get displayName => fullName.isNotEmpty ? fullName : username;
}

// Cached staff directory for the support picker. The short TTL keeps the online
// flags fresh each time the picker opens without refetching on every rebuild.
class StaffDirectory {
  static List<StaffEntry>? _cache;
  static DateTime? _cachedAt;
  static const _ttl = Duration(seconds: 30);

  static Future<List<StaffEntry>> load() async {
    final cached = _cache;
    final at = _cachedAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _ttl) {
      return cached;
    }
    final r = await http
        .get(Uri.parse('${StaffAuth._kBase}/staff-list'))
        .timeout(const Duration(seconds: 30));
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200 || data['ok'] != true) {
      throw Exception('staff list unavailable');
    }
    final staff = (data['staff'] as List<dynamic>)
        .map((e) => StaffEntry((e['username'] as String?) ?? '',
            (e['full_name'] as String?) ?? '',
            online: e['online'] == true))
        .where((e) => e.username.isNotEmpty)
        .toList();
    _cache = staff;
    _cachedAt = DateTime.now();
    return staff;
  }
}
