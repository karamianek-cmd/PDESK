import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_hbb/models/platform_model.dart';

// One selectable lab from the central directory (id + names only).
class LabEntry {
  final int id;
  final String name;
  final String en;
  const LabEntry(this.id, this.name, this.en);
}

// Staff-edition login. Parsipol staff sign in with a password; lab users sign in
// with their lab + username from a registered computer. The Parsipol server holds
// the directory service account and does the verification; only the resulting
// identity is kept on this device, never a password.
class StaffAuth {
  static const _kBase = 'https://desk.parsipol.com/help/api';
  static const _kUserOption = 'staff-username';
  static const _kNameOption = 'staff-fullname';
  static const _kRoleOption = 'staff-role';
  static const _kModeOption = 'staff-mode';
  static const _kLabIdOption = 'staff-lab-id';
  static const _kLabNameOption = 'staff-lab-name';

  static final loggedIn = false.obs;
  static String username = '';
  static String fullName = '';
  static String role = '';
  static String mode = 'staff';
  static String labId = '';
  static String labName = '';

  static void load() {
    username = bind.mainGetLocalOption(key: _kUserOption);
    fullName = bind.mainGetLocalOption(key: _kNameOption);
    role = bind.mainGetLocalOption(key: _kRoleOption);
    mode = bind.mainGetLocalOption(key: _kModeOption) == 'lab' ? 'lab' : 'staff';
    labId = bind.mainGetLocalOption(key: _kLabIdOption);
    labName = bind.mainGetLocalOption(key: _kLabNameOption);
    loggedIn.value = username.isNotEmpty;
  }

  // Human-readable identity shown in Settings / About.
  static String get accountLabel {
    final parts = <String>[mode == 'lab' ? username : fullName];
    if (role.isNotEmpty) parts.add('($role)');
    if (mode == 'lab' && labName.isNotEmpty) parts.add('— $labName');
    return parts.join(' ');
  }

  static Future<List<String>> macAddresses() async {
    try {
      final list = jsonDecode(bind.mainGetMacAddresses()) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
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
        await _persist();
        loggedIn.value = true;
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

  // Lab login: no password; the server checks the username is enabled for the lab
  // and that one of this computer's MACs is a registered terminal.
  static Future<String?> loginLab(
      LabEntry lab, String user, List<String> macs) async {
    try {
      final r = await http
          .post(Uri.parse('$_kBase/lab-login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'lab_id': lab.id, 'username': user, 'macs': macs}))
          .timeout(const Duration(seconds: 40));
      final data =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (r.statusCode == 200 && data['ok'] == true) {
        username = user;
        fullName = (data['username'] as String?) ?? user;
        role = (data['role'] as String?) ?? '';
        mode = 'lab';
        labId = '${lab.id}';
        labName = lab.name;
        await _persist();
        loggedIn.value = true;
        return null;
      }
      if (r.statusCode == 401) {
        return data['error'] == 'unregistered'
            ? 'This computer is not registered for this lab'
            : 'Invalid username or password';
      }
      if (r.statusCode == 403) return 'This account is disabled';
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
  }

  static Future<void> logout() async {
    username = '';
    fullName = '';
    role = '';
    mode = 'staff';
    labId = '';
    labName = '';
    await _persist();
    loggedIn.value = false;
  }
}

// Cached lab directory for the login picker. Only id + names are fetched; the
// server keeps GUIDs, service URLs and contact details to itself.
class LabDirectory {
  static List<LabEntry>? _cache;

  static Future<List<LabEntry>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final r = await http
        .get(Uri.parse('${StaffAuth._kBase}/lab-list'))
        .timeout(const Duration(seconds: 40));
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200 || data['ok'] != true) {
      throw Exception('lab list unavailable');
    }
    final labs = (data['labs'] as List<dynamic>)
        .map((e) => LabEntry((e['id'] as num).toInt(),
            (e['name'] as String?) ?? '', (e['en'] as String?) ?? ''))
        .toList();
    _cache = labs;
    return labs;
  }
}
