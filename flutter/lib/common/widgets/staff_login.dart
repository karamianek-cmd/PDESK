import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/desktop/widgets/pardis_art.dart';
import 'package:flutter_hbb/desktop/widgets/parsidesk_brand.dart';

// Shows the staff login screen until a staff member signs in.
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

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final user = _user.text.trim();
    final pass = _pass.text;
    if (user.isEmpty || pass.isEmpty || _busy) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      const SizedBox(height: 20),
                      TextField(
                        controller: _user,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                            labelText: translate('Username')),
                      ),
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