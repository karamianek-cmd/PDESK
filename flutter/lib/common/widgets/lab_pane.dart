import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/desktop/widgets/parsidesk_brand.dart';

// Home pane for lab devices: the lab name is the hero, set in Shabnam.
// Lab devices only receive support connections, so there is no remote-ID box.
class LabNamePane extends StatelessWidget {
  const LabNamePane({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = PdTokens.accent(context);
    final muted = PdTokens.muted(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: dark
                          ? [const Color(0xFF3D6FD1), const Color(0xFF2B4E9B)]
                          : MyTheme.isPardis
                              ? [
                                  const Color(0xFF159A93),
                                  const Color(0xFF0E6B66)
                                ]
                              : [
                                  accent,
                                  Color.lerp(accent, Colors.black, 0.22)!
                                ],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: accent.withOpacity(0.32),
                          blurRadius: 26,
                          offset: const Offset(0, 10))
                    ],
                  ),
                  child: const Icon(Icons.science_rounded,
                      size: 34, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(translate('Lab device'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: muted)),
                const SizedBox(height: 10),
                Text(
                  StaffAuth.labName.isNotEmpty
                      ? StaffAuth.labName
                      : StaffAuth.labId,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontFamily: 'Shabnam',
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                      color: Theme.of(context).textTheme.titleLarge?.color),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 72,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                        colors: [accent, accent.withOpacity(0.25)]),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withOpacity(0.25)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(translate('Lab ID'),
                        style: TextStyle(fontSize: 12.5, color: muted)),
                    const SizedBox(width: 8),
                    Text(StaffAuth.labId,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: accent)),
                  ]),
                ),
                const SizedBox(height: 30),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            translate(
                                'This device only receives support connections'),
                            style: TextStyle(
                                fontSize: 13, height: 1.8, color: muted)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}