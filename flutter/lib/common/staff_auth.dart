import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_hbb/models/platform_model.dart';

// Staff login for the STAFF edition. Credentials are verified by the Parsipol
// server (which holds the staff-directory service account); only the resulting
// identity is kept on this device, never the password.
class StaffAuth {
  static const _kBase = 'https://desk.parsipol.com/help/api';
  static const _kUserOption = 'staff-username';
  static const _kNameOption = 'staff-fullname';
  static const _kRoleOption = 'staff-role';

  static final loggedIn = false.obs;
  static String username = '';
  static String fullName = '';
  static String role = '';

  static void load() {
    username = bind.mainGetLocalOption(key: _kUserOption);
    fullName = bind.mainGetLocalOption(key: _kNameOption);
    role = bind.mainGetLocalOption(key: _kRoleOption);
    loggedIn.value = username.isNotEmpty;
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
        await bind.mainSetLocalOption(key: _kUserOption, value: username);
        await bind.mainSetLocalOption(key: _kNameOption, value: fullName);
        await bind.mainSetLocalOption(key: _kRoleOption, value: role);
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

  static Future<void> logout() async {
    username = '';
    fullName = '';
    role = '';
    await bind.mainSetLocalOption(key: _kUserOption, value: '');
    await bind.mainSetLocalOption(key: _kNameOption, value: '');
    await bind.mainSetLocalOption(key: _kRoleOption, value: '');
    loggedIn.value = false;
  }
}