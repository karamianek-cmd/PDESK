// ParsiDesk auto-reconnect (Windows remote sessions).
//
// When a session that was already showing the remote screen drops with a
// network error, keep retrying behind a "Reconnecting..." card instead of
// showing the error box. Anything that needs the user (password, login error,
// closed by the peer) or a drop that lasts longer than [_maxOutage] goes back
// to the normal message box flow.

import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';

import '../common.dart';
import '../common/jalali.dart';
import '../consts.dart';
import 'model.dart';

const _tag = 'auto-reconnect';
const _maxOutage = Duration(minutes: 5);
const _delays = [1, 2, 3, 5, 5, 10]; // seconds; the last one repeats

// Errors that a retry cannot fix.
const _permanent = [
  'manually',
  'restricted',
  'incoming only',
  'not allowed',
  'mismatch',
  'not exist',
];

class AutoReconnect {
  final FfiModel model;
  AutoReconnect(this.model);

  bool _connectedOnce = false;
  DateTime? _since;
  int _attempt = 0;
  DateTime? _nextAt;
  Timer? _retry;
  Timer? _clock;
  StateSetter? _update;

  bool get active => _since != null;

  bool get _enabled =>
      isWindows && model.parent.target?.connType == ConnType.defaultConn;

  /// The remote screen arrived: the session is (again) fully connected.
  void onConnected() {
    _connectedOnce = true;
    if (!active) return;
    _stop();
    BotToast.showText(
        text: translate('Reconnected'),
        duration: const Duration(seconds: 2),
        onlyOne: true);
  }

  /// Returns true when the message was handled here and must not be shown.
  bool onMsgBox(String type, String title, String text) {
    if (!_enabled || model.parent.target?.closed == true) {
      _stop();
      return false;
    }
    final connError = type == 'error' && title == 'Connection Error';
    final lower = text.toLowerCase();
    final permanent = _permanent.any(lower.contains);
    if (!active) {
      if (!connError || !_connectedOnce || permanent) return false;
      _since = DateTime.now();
      _attempt = 0;
      _show();
      _schedule();
      return true;
    }
    // Progress messages while a reconnect attempt runs.
    if (type == 'restarting-show' || text == kMsgboxTextWaitingForImage) {
      return true;
    }
    if (!connError ||
        permanent ||
        DateTime.now().difference(_since!) > _maxOutage) {
      _stop();
      return false;
    }
    _schedule();
    return true;
  }

  void _schedule() {
    final secs = _delays[_attempt.clamp(0, _delays.length - 1)];
    _nextAt = DateTime.now().add(Duration(seconds: secs));
    _retry?.cancel();
    _retry = Timer(Duration(seconds: secs), _tryNow);
    _update?.call(() {});
  }

  void _tryNow() {
    if (!active || model.parent.target?.closed == true) return;
    _retry?.cancel();
    _attempt++;
    _nextAt = null;
    _update?.call(() {});
    model.reconnectQuietly();
  }

  void _stop() {
    _retry?.cancel();
    _clock?.cancel();
    _retry = null;
    _clock = null;
    _since = null;
    _nextAt = null;
    _update = null;
    model.parent.target?.dialogManager.dismissByTag(_tag);
  }

  void _show() {
    final ffi = model.parent.target;
    if (ffi == null) return;
    final dialogManager = ffi.dialogManager;
    dialogManager.dismissAll();
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (model.parent.target?.closed != false) {
        _stop();
      } else {
        _update?.call(() {});
      }
    });
    final name = model.pi.hostname.isEmpty ? ffi.id : model.pi.hostname;
    dialogManager.show((setState, close, context) {
      _update = setState;
      return CustomAlertDialog(
        title: Row(children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 12),
          Flexible(child: Text(translate('Reconnecting...'))),
        ]),
        content: _ReconnectBody(
          name: name,
          attempt: _attempt,
          since: _since,
          nextAt: _nextAt,
        ),
        actions: [
          dialogButton('Close session', isOutline: true, onPressed: () {
            _stop();
            ffi.dialogManager.dismissAll();
            closeConnection(id: ffi.id);
          }),
          dialogButton('Reconnect now',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _nextAt == null ? null : _tryNow),
        ],
      );
    }, tag: _tag);
  }
}

class _ReconnectBody extends StatelessWidget {
  final String name;
  final int attempt;
  final DateTime? since;
  final DateTime? nextAt;
  const _ReconnectBody(
      {required this.name,
      required this.attempt,
      required this.since,
      required this.nextAt});

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7);
    final down =
        since == null ? 0 : DateTime.now().difference(since!).inSeconds;
    final mmss =
        '${(down ~/ 60).toString().padLeft(2, '0')}:${(down % 60).toString().padLeft(2, '0')}';
    final next = nextAt == null
        ? null
        : (nextAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.wifi_off_rounded, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(translate('The connection to {} dropped.')
                .replaceFirst('{}', name)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
            translate(
                'ParsiDesk keeps trying to reconnect. The session resumes by itself.'),
            style: TextStyle(fontSize: 13, color: muted)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill(context, Icons.timer_outlined,
              '${translate('Disconnected for')} $mmss'),
          if (attempt > 0)
            _pill(context, Icons.repeat_rounded,
                translate('Attempt {}').replaceFirst('{}', '$attempt')),
          _pill(
              context,
              Icons.schedule_rounded,
              next == null
                  ? translate('Trying now...')
                  : translate('Next try in {} s')
                      .replaceFirst('{}', '${next < 0 ? 0 : next}')),
        ]),
      ],
    );
  }

  Widget _pill(BuildContext context, IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
              Directionality.of(context) == TextDirection.rtl
                  ? faDigits(text)
                  : text,
              style: const TextStyle(fontSize: 12)),
        ]),
      );
}
