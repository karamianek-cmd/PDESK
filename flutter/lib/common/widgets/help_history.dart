// Support history for the network-admin panel: session timing and the History section.

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/jalali.dart';
import 'package:flutter_hbb/common/widgets/network_help.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

// ------------------------------------------------------------- session timing

class _Tracked {
  final int hid;
  final String peerId;
  final DateTime started = DateTime.now();
  bool seenOpen = false;
  _Tracked(this.hid, this.peerId);
}

/// Reports to the help server while a remote window opened from a ticket stays
/// open, and when it closes. If the app quits, the server closes the session
/// itself at the last report.
class HelpSessionTracker {
  static const _period = Duration(seconds: 20);
  static const _openGrace = Duration(seconds: 90);
  static final List<_Tracked> _active = [];
  static Timer? _timer;

  /// Set by the admin panel to offer a note when a session ends.
  static void Function(Map<String, dynamic> item)? onEnded;

  static void start(int hid, String peerId) {
    if (!isDesktop) return;
    _active.add(_Tracked(hid, peerId));
    _timer ??= Timer.periodic(_period, (_) => _tick());
  }

  static Future<Set<String>> _openPeers() async {
    final peers = <String>{};
    for (final wid in await rustDeskWinManager.getAllSubWindowIds()) {
      try {
        final r = await DesktopMultiWindow.invokeMethod(
            wid, kWindowEventGetRemoteList, null);
        if (r is String) peers.addAll(r.split(',').where((e) => e.isNotEmpty));
      } catch (_) {}
    }
    return peers;
  }

  static Future<void> _tick() async {
    if (HelpApi.token == null || _active.isEmpty) {
      _active.clear();
      _timer?.cancel();
      _timer = null;
      return;
    }
    final open = await _openPeers();
    final alive = <int>[];
    final ended = <_Tracked>[];
    for (final s in _active) {
      if (open.contains(s.peerId)) {
        s.seenOpen = true;
        alive.add(s.hid);
      } else if (s.seenOpen ||
          DateTime.now().difference(s.started) > _openGrace) {
        ended.add(s);
      } else {
        alive.add(s.hid); // the window is still opening
      }
    }
    if (alive.isNotEmpty) await HelpApi.historyAlive(alive);
    for (final s in ended) {
      _active.remove(s);
      final r = await HelpApi.historyEnd(s.hid);
      final item = r.data['item'];
      if (r.ok && item is Map) onEnded?.call(Map<String, dynamic>.from(item));
    }
  }
}

// ------------------------------------------------------------------ helpers

bool _isPersian(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl;

String formatDuration(BuildContext context, int? sec) {
  if (sec == null) return '—';
  final f = TehranFormat(_isPersian(context));
  final m = (sec + 30) ~/ 60;
  if (m < 1) return translate('Less than a minute');
  if (m < 60) return f.number('$m ${translate('min')}');
  return f.number(translate('{} h {} min')
      .replaceFirst('{}', '${m ~/ 60}')
      .replaceFirst('{}', '${m % 60}'));
}

Color waitColor(int? sec) {
  final m = (sec ?? 0) ~/ 60;
  if (m >= 15) return Colors.redAccent;
  if (m >= 5) return Colors.orange;
  return MyTheme.accent;
}

// ------------------------------------------------------------- history view

class HelpHistoryView extends StatefulWidget {
  const HelpHistoryView({super.key});

  @override
  State<HelpHistoryView> createState() => HelpHistoryViewState();
}

class HelpHistoryViewState extends State<HelpHistoryView> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _stats = {};
  bool _more = false;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> reload() => _load(append: false);

  Future<void> _load({required bool append}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final before = append && _items.isNotEmpty ? _items.last['hid'] as int : 0;
    final r = await HelpApi.historyList(q: _search.text.trim(), before: before);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = !r.ok;
      if (!r.ok) return;
      final items = (r.data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _items = append ? [..._items, ...items] : items;
      _more = r.data['more'] == true;
      _stats = Map<String, dynamic>.from(r.data['stats'] as Map? ?? {});
    });
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), reload);
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final saved = await showHistoryEntryDialog(context, item);
    if (saved != null && mounted) {
      setState(() => item['admin_note'] = saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    final f = TehranFormat(_isPersian(context));

    // Entries grouped under one heading per Tehran day.
    final rows = <Widget>[];
    JalaliDate? day;
    for (final it in _items) {
      final at = parseServerTime(it['accepted_at']);
      if (at == null) continue;
      final d = f.jalaliDay(at);
      if (d != day) {
        day = d;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(f.dayTitle(at),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
        ));
      }
      rows.add(_HistoryTile(item: it, onTap: () => _open(it)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatsRow(stats: _stats),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: _onSearch,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: translate('Search by name, ID, IP, admin or note'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Text(
                          translate(_failed
                              ? 'Cannot reach the server'
                              : 'No support sessions yet'),
                          style: TextStyle(color: muted)))
              : ListView(
                  children: [
                    ...rows,
                    if (_more)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : OutlinedButton(
                                  onPressed: () => _load(append: true),
                                  child: Text(translate('Load more'))),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final f = TehranFormat(_isPersian(context));
    Widget tile(IconData icon, String label, String value, Color color) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Row(children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(translate(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withOpacity(0.7))),
                  ],
                ),
              ),
            ]),
          ),
        );
    final open = (stats['open'] as int?) ?? 0;
    return Row(children: [
      tile(Icons.today_rounded, 'Today', f.number(stats['today'] ?? 0),
          MyTheme.accent),
      const SizedBox(width: 8),
      tile(Icons.date_range_rounded, 'Last 30 days',
          f.number(stats['month'] ?? 0), Colors.teal),
      const SizedBox(width: 8),
      tile(
          Icons.hourglass_bottom_rounded,
          'Average wait',
          formatDuration(context, stats['avg_wait_sec'] as int?),
          Colors.orange),
      const SizedBox(width: 8),
      tile(
          open > 0 ? Icons.play_circle_outline : Icons.timer_outlined,
          open > 0 ? 'Sessions in progress' : 'Average session',
          open > 0
              ? f.number(open)
              : formatDuration(context, stats['avg_duration_sec'] as int?),
          open > 0 ? Colors.green : Colors.indigo),
    ]);
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  const _HistoryTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    final f = TehranFormat(_isPersian(context));
    final at = parseServerTime(item['accepted_at']);
    final name = (item['name'] ?? '') as String;
    final open = item['open'] == true;
    final note = (item['admin_note'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(children: [
              SizedBox(
                width: 48,
                child: Text(at == null ? '' : f.time(at),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? item['id'] as String : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(
                        '${item['ip']}  ·  ${item['id']}  ·  ${item['accepted_by']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 12, color: muted)),
                    if (note.isNotEmpty)
                      Text(note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: theme.colorScheme.primary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Chip(
                text: open
                    ? translate('In progress')
                    : formatDuration(context, item['duration_sec'] as int?),
                color: open ? Colors.green : Colors.indigo,
                icon: open ? Icons.circle : Icons.timer_outlined,
              ),
              const SizedBox(width: 4),
              Icon(note.isEmpty ? Icons.note_add_outlined : Icons.sticky_note_2,
                  size: 18, color: note.isEmpty ? muted : MyTheme.accent),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _Chip({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: icon == Icons.circle ? 8 : 14, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ---------------------------------------------------------- entry details

/// Shows one support session and lets the admin edit its note.
/// Returns the saved note, or null when nothing was saved.
Future<String?> showHistoryEntryDialog(
    BuildContext context, Map<String, dynamic> item,
    {bool justEnded = false}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _HistoryEntryDialog(item: item, justEnded: justEnded),
  );
}

class _HistoryEntryDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool justEnded;
  const _HistoryEntryDialog({required this.item, required this.justEnded});

  @override
  State<_HistoryEntryDialog> createState() => _HistoryEntryDialogState();
}

class _HistoryEntryDialogState extends State<_HistoryEntryDialog> {
  late final _note =
      TextEditingController(text: (widget.item['admin_note'] ?? '') as String);
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hid = widget.item['hid'];
    if (hid is! int) return;
    setState(() => _saving = true);
    final text = _note.text.trim();
    final r = await HelpApi.historyNote(hid, text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
      Navigator.pop(context, text);
    } else {
      showToast(translate('Failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    final f = TehranFormat(_isPersian(context));
    String when(String key) {
      final t = parseServerTime(it[key]);
      return t == null ? '—' : f.dateTime(t);
    }

    final name = (it['name'] ?? '') as String;
    final requestNote = (it['request_note'] ?? '') as String;
    final noteBy = (it['note_by'] ?? '') as String;
    Widget row(String label, String value, {bool ltr = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 120,
                child: Text(translate(label),
                    style: TextStyle(fontSize: 13, color: muted))),
            Expanded(
                child: SelectableText(value,
                    textDirection: ltr ? TextDirection.ltr : null,
                    style: const TextStyle(fontSize: 13))),
          ]),
        );

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.history_rounded, color: theme.primaryColor),
        const SizedBox(width: 8),
        Expanded(
            child: Text(widget.justEnded
                ? translate('Support session ended')
                : (name.isEmpty ? it['id'] as String : name))),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.justEnded) row('Device name', name),
              row('ID', '${it['id']}', ltr: true),
              row('IP', '${it['ip']}', ltr: true),
              row('Requested at', when('requested_at')),
              row('Accepted at', when('accepted_at')),
              row(
                  'Ended at',
                  it['open'] == true
                      ? translate('In progress')
                      : when('ended_at')),
              row('Wait time', formatDuration(context, it['wait_sec'] as int?)),
              row('Session length',
                  formatDuration(context, it['duration_sec'] as int?)),
              row('Accepted by', '${it['accepted_by']}', ltr: true),
              if (requestNote.isNotEmpty) row('User note', requestNote),
              if (it['had_shot'] == true)
                row('Screenshot', translate('Sent with the request')),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                autofocus: widget.justEnded,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: translate('Admin note'),
                  hintText:
                      translate('What was the problem and how was it solved?'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (noteBy.isNotEmpty)
                Text(
                    '${translate('Last edited by')} $noteBy · ${when('note_at')}',
                    style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translate(widget.justEnded ? 'Later' : 'Close'))),
        ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(translate('Save note'))),
      ],
    );
  }
}
