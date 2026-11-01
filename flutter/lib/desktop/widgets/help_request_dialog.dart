// "Need network admin help" request dialog for Windows: device name plus an optional note and
// an optional screenshot (captured from the screen or picked from a file).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:window_manager/window_manager.dart';

import '../../common.dart';

class HelpRequestInput {
  final String name;
  final String note;
  final Uint8List? shot; // JPEG
  HelpRequestInput(this.name, this.note, this.shot);
}

Future<HelpRequestInput?> showHelpRequestDialog(
        BuildContext context, String initialName) =>
    showDialog<HelpRequestInput>(
      context: context,
      builder: (_) => _HelpRequestDialog(initialName),
    );

const _kMaxNote = 500;
const _kMaxShotBytes = 900 * 1000; // the server accepts up to 1 MB
const _kMaxSourceBytes = 40 * 1000 * 1000;

const _kCaptureScript = r'''
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class PdDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[PdDpi]::SetProcessDPIAware() | Out-Null
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save('__PATH__', [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
''';

/// Takes a PNG screenshot of all monitors, or returns null.
Future<Uint8List?> _captureScreen() async {
  final file = File(
      '${Directory.systemTemp.path}\\parsidesk_help_${DateTime.now().millisecondsSinceEpoch}.png');
  try {
    final script =
        _kCaptureScript.replaceAll('__PATH__', file.path.replaceAll("'", "''"));
    final utf16 = <int>[];
    for (final c in script.codeUnits) {
      utf16
        ..add(c & 0xff)
        ..add(c >> 8);
    }
    final root = Platform.environment['SystemRoot'] ?? 'C:\\Windows';
    final r = await Process.run(
        '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      base64Encode(utf16),
    ]);
    if (r.exitCode != 0 || !await file.exists()) {
      debugPrint('help screenshot failed: ${r.stderr}');
      return null;
    }
    return await file.readAsBytes();
  } catch (e) {
    debugPrint('help screenshot failed: $e');
    return null;
  } finally {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Shrinks any image to a JPEG small enough for the help server, or null.
Future<Uint8List?> _toJpeg(Uint8List source) => Isolate.run(() {
      final im = img.decodeImage(source);
      if (im == null) return null;
      for (final (width, quality) in [(1600, 70), (1280, 60), (960, 50)]) {
        final out = im.width > width ? img.copyResize(im, width: width) : im;
        final jpg = img.encodeJpg(out, quality: quality);
        if (jpg.length <= _kMaxShotBytes) return Uint8List.fromList(jpg);
      }
      return null;
    });

class _HelpRequestDialog extends StatefulWidget {
  final String initialName;
  const _HelpRequestDialog(this.initialName);

  @override
  State<_HelpRequestDialog> createState() => _HelpRequestDialogState();
}

class _HelpRequestDialogState extends State<_HelpRequestDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  final _note = TextEditingController();
  Uint8List? _shot;
  bool _working = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _setShot(Future<Uint8List?> Function() source) async {
    setState(() => _working = true);
    Uint8List? jpg;
    final raw = await source();
    if (raw != null) jpg = await _toJpeg(raw);
    if (!mounted) return;
    setState(() {
      _working = false;
      if (jpg != null) _shot = jpg;
    });
    if (raw != null && jpg == null) {
      showToast(translate('The screenshot could not be taken'));
    }
  }

  Future<void> _capture() => _setShot(() async {
        // Hide ParsiDesk so the screenshot shows the user's problem, not this dialog.
        try {
          await windowManager.hide();
          await Future.delayed(const Duration(milliseconds: 500));
          final raw = await _captureScreen();
          if (raw == null) {
            showToast(translate('The screenshot could not be taken'));
          }
          return raw;
        } finally {
          await windowManager.show();
          await windowManager.focus();
        }
      });

  Future<void> _pick() => _setShot(() async {
        final res = await FilePicker.platform
            .pickFiles(type: FileType.image, withData: false);
        final path = res?.files.single.path;
        if (path == null) return null;
        final file = File(path);
        if (await file.length() > _kMaxSourceBytes) {
          showToast(translate('The screenshot could not be taken'));
          return null;
        }
        return file.readAsBytes();
      });

  void _submit() => Navigator.pop(
      context, HelpRequestInput(_name.text.trim(), _note.text.trim(), _shot));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.65);
    return AlertDialog(
      title: Text(translate('Need network admin help')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('help_request_tip'),
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: 40,
                decoration:
                    InputDecoration(labelText: translate('Device name')),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                maxLength: _kMaxNote,
                decoration: InputDecoration(
                    labelText: translate('Describe the problem (optional)'),
                    alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              Text(translate('Screenshot (optional)'),
                  style: TextStyle(fontSize: 13, color: muted)),
              const SizedBox(height: 8),
              if (_working)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_shot != null)
                Stack(
                  children: [
                    Container(
                      height: 170,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_shot!, fit: BoxFit.contain),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton.filledTonal(
                        tooltip: translate('Remove'),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _shot = null),
                      ),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _capture,
                      icon: const Icon(Icons.screenshot_monitor_rounded,
                          size: 18),
                      label: Text(translate('Capture my screen')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pick,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: Text(translate('Choose an image')),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translate('Cancel'))),
        ElevatedButton(
            onPressed: _working ? null : _submit,
            child: Text(translate('Send request'))),
      ],
    );
  }
}
