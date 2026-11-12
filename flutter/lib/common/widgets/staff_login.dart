import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/desktop/widgets/pardis_art.dart';
import 'package:flutter_hbb/desktop/widgets/parsidesk_brand.dart';

// Shows the staff login screen until a staff member or lab user signs in.
class StaffGate extends StatelessWidget {
  final Widget child;
  const StaffGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Obx(() => StaffAuth.loggedIn.value ? child : const StaffLoginPage());
  }
}

class StaffLoginPage extends StatefulWidget {
  const StaffLoginPage({super.key});

  @override
  State<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends State<StaffLoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String _error = '';
  String _mode = 'staff';
  LabEntry? _lab;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final user = _user.text.trim();
    if (_mode == 'staff') {
      final pass = _pass.text;
      if (user.isEmpty || pass.isEmpty) return;
      setState(() {
        _busy = true;
        _error = '';
      });
      final err = await StaffAuth.login(user, pass);
      _pass.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err == null ? '' : translate(err);
      });
      return;
    }
    if (user.isEmpty) return;
    if (_lab == null) {
      setState(() => _error = translate('Select your lab'));
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final macs = await StaffAuth.macAddresses();
    if (!mounted) return;
    if (macs.isEmpty) {
      setState(() {
        _busy = false;
        _error = translate('No network adapter found');
      });
      return;
    }
    final err = await StaffAuth.loginLab(_lab!, user, macs);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? '' : translate(err);
    });
  }

  Future<void> _pickLab() async {
    final picked = await showDialog<LabEntry>(
        context: context, builder: (_) => const _LabPickerDialog());
    if (picked != null && mounted) {
      setState(() {
        _lab = picked;
        _error = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labMode = _mode == 'lab';
    return Scaffold(
      body: Stack(children: [
        const Positioned(
            left: 0, right: 0, bottom: 0, height: 190,
            child: ParsiDeskBottomArt()),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: PdCard(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  margin: EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: ParsiDeskHeader()),
                      const SizedBox(height: 18),
                      Text(translate('Staff login'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(translate('Staff edition'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.textTheme.bodySmall?.color
                                  ?.withOpacity(0.7))),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'staff',
                            groupValue: _mode,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(translate('Parsipol staff'),
                                style: const TextStyle(fontSize: 13.5)),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                      _mode = v!;
                                      _error = '';
                                    }),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'lab',
                            groupValue: _mode,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(translate('Lab user'),
                                style: const TextStyle(fontSize: 13.5)),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                      _mode = v!;
                                      _error = '';
                                    }),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (labMode) ...[
                        InkWell(
                          onTap: _busy ? null : _pickLab,
                          borderRadius:
                              BorderRadius.circular(PdTokens.radiusSmall),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: translate('Lab'),
                              suffixIcon:
                                  const Icon(Icons.arrow_drop_down, size: 22),
                            ),
                            child: Text(
                              _lab?.name ?? translate('Select lab'),
                              style: TextStyle(
                                  fontSize: 14,
                                  color: _lab == null
                                      ? theme.textTheme.bodySmall?.color
                                          ?.withOpacity(0.7)
                                      : null),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _user,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: labMode
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onSubmitted: labMode ? (_) => _signIn() : null,
                        decoration: InputDecoration(
                            labelText: translate('Username')),
                      ),
                      if (!labMode) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.left,
                          obscureText: _hide,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => _signIn(),
                          decoration: InputDecoration(
                            labelText: translate('Password'),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _hide
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 20),
                              onPressed: () =>
                                  setState(() => _hide = !_hide),
                            ),
                          ),
                        ),
                      ],
                      if (_error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error,
                              style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontSize: 13)),
                        ),
                      const SizedBox(height: 20),
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
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// Searchable picker over the lab directory (id + names only).
class _LabPickerDialog extends StatefulWidget {
  const _LabPickerDialog();

  @override
  State<_LabPickerDialog> createState() => _LabPickerDialogState();
}

class _LabPickerDialogState extends State<_LabPickerDialog> {
  final _search = TextEditingController();
  List<LabEntry>? _labs;
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
      final labs = await LabDirectory.load();
      if (!mounted) return;
      setState(() {
        _labs = labs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot load the lab list';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final labs = _labs ?? const <LabEntry>[];
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? labs
        : labs
            .where((l) =>
                l.name.toLowerCase().contains(q) ||
                l.en.toLowerCase().contains(q))
            .toList();
    return AlertDialog(
      title: Text(translate('Select lab')),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(children: [
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              labelText: translate('Search labs'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(translate(_error),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: _load,
                                child: Text(translate('Retry'))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final lab = filtered[i];
                          return ListTile(
                            dense: true,
                            title: Text(lab.name),
                            subtitle: lab.en.isNotEmpty ? Text(lab.en) : null,
                            onTap: () => Navigator.pop(context, lab),
                          );
                        },
                      ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translate('Cancel'))),
      ],
    );
  }
}
