// ParsiDesk support toolbox: one-click fixes on a Windows peer.
// The peer runs the action and answers with a "support_tool" event.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

const _kSystemInfo = 'system_info';
const _kFlushDns = 'flush_dns';
const _kResetNetwork = 'reset_network';
const _kSafeMode = 'safe_mode';
const _kNormalMode = 'normal_mode';

final Map<String, Completer<Map<String, dynamic>>> _pending = {};

String _pendingKey(SessionID sessionId, String action) => '$sessionId/$action';

/// Called by FfiModel when the peer answers a support tool request.
void onSupportToolResult(SessionID sessionId, Map<String, dynamic> evt) {
  final completer =
      _pending.remove(_pendingKey(sessionId, evt['action']?.toString() ?? ''));
  if (completer != null && !completer.isCompleted) completer.complete(evt);
}

/// Resolves to null when the peer does not answer (old version or no network).
Future<Map<String, dynamic>?> _request(FFI ffi, String action) {
  final key = _pendingKey(ffi.sessionId, action);
  final completer = _pending[key] ?? Completer<Map<String, dynamic>>();
  _pending[key] = completer;
  bind.sessionSupportTool(sessionId: ffi.sessionId, action: action);
  return completer.future
      .then<Map<String, dynamic>?>((v) => v)
      .timeout(const Duration(seconds: 40), onTimeout: () {
    _pending.remove(key);
    return null;
  });
}

bool supportToolsAvailable(FFI ffi) =>
    ffi.ffiModel.pi.platform == kPeerPlatformWindows &&
    ffi.connType == ConnType.defaultConn &&
    !ffi.ffiModel.viewOnly &&
    ffi.ffiModel.keyboard;

class SupportToolItem {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  SupportToolItem(this.label, this.icon, this.onPressed);
}

List<SupportToolItem> supportToolItems(FFI ffi) {
  final canRestart = ffi.ffiModel.permissions['restart'] != false;
  return [
    SupportToolItem('System information', Icons.info_outline_rounded,
        () => _showSystemInfo(ffi)),
    SupportToolItem('Open Task Manager', Icons.view_list_rounded, () {
      bind.sessionInputKey(
          sessionId: ffi.sessionId,
          name: 'VK_ESCAPE',
          down: false,
          press: true,
          alt: false,
          ctrl: true,
          shift: true,
          command: false);
      showToast(translate('Task Manager was opened on the remote computer'));
    }),
    SupportToolItem('Flush DNS', Icons.dns_rounded,
        () => _run(ffi, _kFlushDns, 'Flush DNS', 'The DNS cache was cleared')),
    SupportToolItem('Reset network adapter', Icons.settings_ethernet_rounded,
        () async {
      if (await _confirm(ffi, 'Reset network adapter',
          'The network adapters of the remote computer will restart. The connection drops for a few seconds, then reconnect.')) {
        _run(ffi, _kResetNetwork, 'Reset network adapter',
            'The network adapters are restarting. Reconnect in a few seconds.');
      }
    }),
    if (canRestart)
      SupportToolItem('Restart in safe mode', Icons.health_and_safety_rounded,
          () async {
        if (await _confirm(ffi, 'Restart in safe mode',
            'The remote computer will restart in safe mode with networking. ParsiDesk starts there too, so you can reconnect. When you are done, use Restart in normal mode.')) {
          _run(ffi, _kSafeMode, 'Restart in safe mode',
              'The remote computer is restarting. Reconnect in a minute.');
        }
      }),
    if (canRestart)
      SupportToolItem('Restart in normal mode', Icons.restart_alt_rounded,
          () async {
        if (await _confirm(ffi, 'Restart in normal mode',
            'The remote computer will restart in normal mode.')) {
          _run(ffi, _kNormalMode, 'Restart in normal mode',
              'The remote computer is restarting. Reconnect in a minute.');
        }
      }),
  ];
}

String _failureText(Map<String, dynamic>? res) {
  if (res == null)
    return translate(
        'The remote computer did not answer. It may be running an older version of ParsiDesk.');
  final text = res['text']?.toString() ?? '';
  return text.isEmpty
      ? translate('The action failed on the remote computer')
      : translate(text);
}

bool _isOk(Map<String, dynamic>? res) =>
    res != null && (res['ok'] == true || res['ok'] == 'true');

Future<bool> _confirm(FFI ffi, String title, String text) async {
  final res = await ffi.dialogManager
      .show<bool>((setState, close, context) => CustomAlertDialog(
            title: Row(children: [
              Icon(Icons.warning_rounded, color: Colors.orange, size: 28),
              Flexible(child: Text(translate(title)).paddingOnly(left: 10)),
            ]),
            content: Text(translate(text)),
            actions: [
              dialogButton('Cancel',
                  icon: Icon(Icons.close_rounded),
                  onPressed: close,
                  isOutline: true),
              dialogButton('OK',
                  icon: Icon(Icons.done_rounded), onPressed: () => close(true)),
            ],
            onCancel: close,
            onSubmit: () => close(true),
          ));
  return res == true;
}

/// Shows a waiting dialog that turns into the result once the peer answers.
void _run(FFI ffi, String action, String title, String okText) {
  _resultDialog(ffi, title, _request(ffi, action), (res) {
    if (_isOk(res)) {
      return Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.green),
        Flexible(child: Text(translate(okText)).paddingOnly(left: 8)),
      ]);
    }
    return _failureRow(res);
  });
}

Widget _failureRow(Map<String, dynamic>? res) => Row(children: [
      Icon(Icons.error_rounded, color: Colors.redAccent),
      Flexible(child: SelectableText(_failureText(res)).paddingOnly(left: 8)),
    ]);

void _resultDialog(FFI ffi, String title, Future<Map<String, dynamic>?> future,
    Widget Function(Map<String, dynamic>? res) body,
    {List<Widget> Function(Map<String, dynamic>? res)? extraActions,
    double maxWidth = 500}) {
  bool done = false;
  Map<String, dynamic>? result;
  StateSetter? update;
  future.then((res) {
    done = true;
    result = res;
    update?.call(() {});
  });
  ffi.dialogManager.show((setState, close, context) {
    update = setState;
    return CustomAlertDialog(
      title: Text(translate(title)),
      contentBoxConstraints: BoxConstraints(maxWidth: maxWidth),
      content: done
          ? body(result)
          : Row(children: [
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              Flexible(
                  child: Text(translate('Waiting for the remote computer...'))
                      .paddingOnly(left: 12)),
            ]),
      actions: [
        if (done && extraActions != null) ...extraActions(result),
        dialogButton('Close', onPressed: close),
      ],
      onCancel: close,
      onSubmit: close,
    );
  });
}

// ---------------------------------------------------------------------------
// System information panel

void _showSystemInfo(FFI ffi) {
  Map<String, dynamic>? parse(Map<String, dynamic>? res) {
    if (!_isOk(res)) return null;
    try {
      final v = jsonDecode(res!['text']?.toString() ?? '');
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  _resultDialog(ffi, 'System information', _request(ffi, _kSystemInfo), (res) {
    final info = parse(res);
    if (info == null) return _failureRow(_isOk(res) ? null : res);
    return _SystemInfoView(info);
  }, extraActions: (res) {
    final info = parse(res);
    if (info == null) return [];
    return [
      dialogButton('Copy', icon: Icon(Icons.copy_rounded), isOutline: true,
          onPressed: () {
        Clipboard.setData(ClipboardData(text: _systemInfoText(info)));
        showToast(translate('Copied'));
      }),
    ];
  }, maxWidth: 560);
}

List _asList(dynamic v) => v is List ? v : (v is Map ? [v] : []);

int _asInt(dynamic v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

String _str(dynamic v) => v?.toString().trim() ?? '';

String _gb(int bytes) => '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';

String _uptime(int minutes) => translate('{} days, {} hours, {} minutes')
    .replaceFirst('{}', '${minutes ~/ 1440}')
    .replaceFirst('{}', '${minutes % 1440 ~/ 60}')
    .replaceFirst('{}', '${minutes % 60}');

String _bootMode(String boot) => boot.toLowerCase().contains('fail-safe')
    ? translate('Safe mode')
    : translate('Normal');

String _windows(Map<String, dynamic> info) => [
      _str(info['os']),
      _str(info['version']),
      if (_str(info['build']).isNotEmpty) 'Build ${_str(info['build'])}',
      _str(info['arch']),
    ].where((e) => e.isNotEmpty).join(' · ');

String _usage(int total, int free) => translate('{} free of {}')
    .replaceFirst('{}', _gb(free))
    .replaceFirst('{}', _gb(total));

/// Plain text for pasting into a ticket or chat.
String _systemInfoText(Map<String, dynamic> info) {
  final lines = <String>[
    '${translate('Computer name')}: ${_str(info['computer'])}',
    '${translate('Signed-in user')}: ${_str(info['user'])}',
    'Windows: ${_windows(info)}',
    '${translate('Boot mode')}: ${_bootMode(_str(info['boot']))}',
    '${translate('Uptime')}: ${_uptime(_asInt(info['uptime_minutes']))}',
    '${translate('Processor')}: ${_str(info['cpu'])} (${_asInt(info['cores'])})',
    '${translate('Memory')}: ${_usage(_asInt(info['ram_total']), _asInt(info['ram_free']))}',
  ];
  for (final d in _asList(info['disks'])) {
    lines.add(
        '${translate('Disk')} ${_str(d['name'])}: ${_usage(_asInt(d['total']), _asInt(d['free']))}');
  }
  for (final n in _asList(info['networks'])) {
    lines.add(
        '${_str(n['name'])}: IP ${_str(n['ip'])}, ${translate('Gateway')} ${_str(n['gateway'])}, DNS ${_str(n['dns'])}');
  }
  return lines.join('\n');
}

class _SystemInfoView extends StatelessWidget {
  final Map<String, dynamic> info;
  const _SystemInfoView(this.info);

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    // Technical values (IPs, builds, names) read left to right.
    Widget ltr(String text, {TextStyle? style}) => Directionality(
        textDirection: TextDirection.ltr,
        child: SelectableText(text, style: style));
    Widget row(IconData icon, String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: hint),
            SizedBox(
                width: 130,
                child: Text(translate(label), style: TextStyle(color: hint))
                    .paddingSymmetric(horizontal: 8)),
            Expanded(child: value),
          ]),
        );
    Widget usage(int total, int free) {
      final used = total <= 0 ? 0.0 : (total - free) / total;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_usage(total, free)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: used.clamp(0.0, 1.0),
            minHeight: 6,
            color: used > 0.9 ? Colors.redAccent : MyTheme.accent,
            backgroundColor: hint.withOpacity(0.2),
          ),
        ),
      ]);
    }

    final boot = _str(info['boot']);
    final inSafeMode = boot.toLowerCase().contains('fail-safe');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 460),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          row(Icons.computer_rounded, 'Computer name',
              ltr(_str(info['computer']))),
          row(Icons.person_rounded, 'Signed-in user', ltr(_str(info['user']))),
          row(Icons.window_rounded, 'Windows', ltr(_windows(info))),
          row(
              Icons.power_settings_new_rounded,
              'Boot mode',
              Text(_bootMode(boot),
                  style: inSafeMode
                      ? const TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.bold)
                      : null)),
          row(Icons.timer_outlined, 'Uptime',
              Text(_uptime(_asInt(info['uptime_minutes'])))),
          row(Icons.memory_rounded, 'Processor',
              ltr('${_str(info['cpu'])} (${_asInt(info['cores'])})')),
          row(Icons.storage_rounded, 'Memory',
              usage(_asInt(info['ram_total']), _asInt(info['ram_free']))),
          for (final d in _asList(info['disks']))
            row(Icons.save_rounded, '${translate('Disk')} ${_str(d['name'])}',
                usage(_asInt(d['total']), _asInt(d['free']))),
          for (final n in _asList(info['networks']))
            row(
                Icons.lan_rounded,
                'Network',
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ltr(_str(n['name']),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ltr('IP: ${_str(n['ip'])}'),
                  ltr('${translate('Gateway')}: ${_str(n['gateway'])}'),
                  ltr('DNS: ${_str(n['dns'])}'),
                ])),
        ]),
      ),
    );
  }
}
