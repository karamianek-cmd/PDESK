import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

// Windows design tokens for the ParsiDesk interface.
class PdTokens {
  static const double radius = 14;
  static const double radiusSmall = 10;

  static Color surface(BuildContext c) =>
      _dark(c) ? const Color(0xFF171B23) : Colors.white;
  static Color border(BuildContext c) =>
      _dark(c) ? const Color(0xFF262C38) : const Color(0xFFE5E9F0);
  static Color muted(BuildContext c) =>
      _dark(c) ? const Color(0xFF9AA4B5) : const Color(0xFF64748B);
  static Color accent(BuildContext c) =>
      _dark(c) ? const Color(0xFF5B8DEF) : MyTheme.accent;
}

// Rounded neutral surface used for the ID, password and brand blocks.
class PdCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  const PdCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.fromLTRB(14, 10, 10, 10),
      this.margin = const EdgeInsets.fromLTRB(14, 6, 14, 6)});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: PdTokens.surface(context),
        borderRadius: BorderRadius.circular(PdTokens.radius),
        border: Border.all(color: PdTokens.border(context)),
      ),
      child: child,
    );
  }
}

// ParsiDesk symbol and name, with a subtle "by ParsiPol" attribution.
class ParsiDeskHeader extends StatelessWidget {
  const ParsiDeskHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = _dark(context);
    final text = Theme.of(context).textTheme.titleLarge?.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                  dark
                      ? 'assets/parsidesk-symbol-dark.png'
                      : 'assets/parsidesk-symbol.png',
                  width: 34,
                  height: 34,
                  filterQuality: FilterQuality.medium),
              const SizedBox(width: 10),
              Text('ParsiDesk',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: text)),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => launchUrl(Uri.parse('https://parsipol.com')),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                      dark
                          ? 'assets/parsipol-symbol-dark.png'
                          : 'assets/parsipol-symbol.png',
                      width: 14,
                      height: 14),
                  const SizedBox(width: 6),
                  Text(translate('Made by Parsipol'),
                      style: TextStyle(
                          fontSize: 12, color: PdTokens.muted(context))),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () =>
                launchUrl(Uri.parse('https://desk.parsipol.com/#guide')),
            child: Text(translate('Usage guide'),
                style: TextStyle(
                    fontSize: 12,
                    color: PdTokens.accent(context),
                    fontWeight: FontWeight.w500)),
          ).marginOnly(top: 2),
        ],
      ),
    );
  }
}
