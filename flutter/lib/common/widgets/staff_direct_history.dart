import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/common/widgets/help_history.dart';
import 'package:flutter_hbb/common/widgets/network_help.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:uuid/uuid.dart';

class StaffDirectHistory {
  static final _sessions = <String, Future<HelpResult>>{};

  static void init() {
    platformFFI.registerEventHandler(
        'staff-support-connected', 'staff-direct-history', _connected,
        replace: true);
    platformFFI.registerEventHandler(
        'staff-support-disconnected', 'staff-direct-history', _disconnected,
        replace: true);
  }

  static Future<void> _connected(Map<String, dynamic> event) async {
    if (!StaffAuth.isStaff || StaffAuth.helpToken.isEmpty) return;
    final id = event['id'] as String;
    final key = '$id:${event['session_id']}';
    if (_sessions.containsKey(key) || HelpSessionTracker.isTrackingPeer(id)) {
      return;
    }
    HelpApi.token = StaffAuth.helpToken;
    HelpApi.adminName = StaffAuth.helpAdminName.isNotEmpty
        ? StaffAuth.helpAdminName
        : StaffAuth.username;
    final pending = HelpApi.historyStart(
        id, const Uuid().v4(), event['hostname'] as String? ?? '');
    _sessions[key] = pending;
    final result = await pending;
    if (_sessions[key] != pending) return;
    final hid = result.data['history_id'];
    if (!result.ok || hid is! int) {
      _sessions.remove(key);
      debugPrint(
          'Direct support history could not be recorded (${result.status}).');
      return;
    }
    HelpSessionTracker.start(hid, id, direct: true);
  }

  static Future<void> _disconnected(Map<String, dynamic> event) async {
    final key = '${event['id']}:${event['session_id']}';
    final pending = _sessions.remove(key);
    if (pending == null) return;
    final result = await pending;
    final hid = result.data['history_id'];
    if (result.ok && hid is int) await HelpSessionTracker.finish(hid);
  }
}
