import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _labId = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String _error = '';
  // 'choose' shows the two entrance buttons; 'staff' and 'lab' show their form.
  String _view = 'choose';

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _labId.dispose();
    super.dispose();
  }

  void _open(String view) {
    if (_busy) return;
    setState(() {
      _view = view;
      _error = '';
    });
  }

  Future<void> _signIn() async {
    if (_busy) return;
    if (_view == 'staff') {
      final user = _user.text.trim();
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
    final id = _labId.text.trim();
    if (id.length != 4) {
      setState(() => _error = translate('Lab ID must be 4 digits'));
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
    final err = await StaffAuth.loginLab(id, macs);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? '' : translate(err);
    });
  }

  @override
  Widget build(BuildContext context) {
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
                constraints: const BoxConstraints(maxWidth: 420),
                child: PdCard(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  margin: EdgeInsets.zero,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _view == 'choose'
                        ? _chooser(context)
                        : _view == 'staff'
                            ? _staffForm(context)
                            : _labForm(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Center(child: ParsiDeskHeader()),
        const SizedBox(height: 18),
        Text(translate('Staff login'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(translate('Staff edition'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
      ],
    );
  }

  Widget _backRow(BuildContext context, String title) {
    return Row(children: [
      IconButton(
        tooltip: translate('Back'),
        onPressed: _busy ? null : () => _open('choose'),
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
      ),
      Expanded(
        child: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  // First page: two distinctive entrances, ParsiPol staff and labs.
  Widget _chooser(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 22),
        _EntranceButton(
          icon: Icons.admin_panel_settings_rounded,
          title: translate('Parsipol staff'),
          subtitle: translate('Username and password'),
          filled: true,
          onTap: _busy ? null : () => _open('staff'),
        ),
        const SizedBox(height: 12),
        _EntranceButton(
          icon: Icons.science_rounded,
          title: translate('Labs'),
          subtitle: translate('4-digit Lab ID'),
          filled: false,
          onTap: _busy ? null : () => _open('lab'),
        ),
      ],
    );
  }

  Widget _staffForm(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backRow(context, translate('Parsipol staff')),
        const SizedBox(height: 16),
        TextField(
          controller: _user,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: translate('Username')),
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
              icon: Icon(_hide ? Icons.visibility_off : Icons.visibility,
                  size: 20),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        _errorText(theme),
        const SizedBox(height: 20),
        _loginButton(),
      ],
    );
  }

  Widget _labForm(BuildContext context) {
    final theme = Theme.of(context);
    final accent = PdTokens.accent(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backRow(context, translate('Labs')),
        const SizedBox(height: 20),
        Text(translate('Enter your 4-digit Lab ID'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.75))),
        const SizedBox(height: 14),
        TextField(
          controller: _labId,
          autofocus: true,
          enabled: !_busy,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: 14,
              color: accent),
          decoration: InputDecoration(
            counterText: '',
            hintText: '0000',
            hintStyle: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: 14,
                color: PdTokens.muted(context).withOpacity(0.35)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: PdTokens.border(context))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent, width: 1.6)),
          ),
          onChanged: (v) {
            if (_error.isNotEmpty) setState(() => _error = '');
            // The Lab ID alone signs the device in once all 4 digits are there.
            if (v.trim().length == 4) _signIn();
          },
          onSubmitted: (_) => _signIn(),
        ),
        _errorText(theme),
        const SizedBox(height: 20),
        _loginButton(),
      ],
    );
  }

  Widget _errorText(ThemeData theme) {
    if (_error.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(_error,
          style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
    );
  }

  Widget _loginButton() {
    return SizedBox(
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
    );
  }
}

// Large entrance tile: filled accent for staff, outlined surface for labs.
class _EntranceButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback? onTap;
  const _EntranceButton(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.filled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = PdTokens.accent(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg =
        filled ? Colors.white : Theme.of(context).textTheme.titleLarge?.color;
    final sub = filled
        ? Colors.white.withOpacity(0.82)
        : Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.75);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: filled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? [const Color(0xFF3D6FD1), const Color(0xFF2B4E9B)]
                        : MyTheme.isPardis
                            ? [const Color(0xFF159A93), const Color(0xFF0E6B66)]
                            : [accent, Color.lerp(accent, Colors.black, 0.22)!])
                : null,
            color: filled ? null : PdTokens.surface(context),
            border: Border.all(
                color: filled ? Colors.transparent : PdTokens.border(context),
                width: 1.2),
            boxShadow: filled
                ? [
                    BoxShadow(
                        color: accent.withOpacity(0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 6))
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? Colors.white.withOpacity(0.16)
                    : accent.withOpacity(0.12),
              ),
              child:
                  Icon(icon, size: 24, color: filled ? Colors.white : accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: fg)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12.5, color: sub)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 22,
                color: filled
                    ? Colors.white.withOpacity(0.8)
                    : PdTokens.muted(context)),
          ]),
        ),
      ),
    );
  }
}
