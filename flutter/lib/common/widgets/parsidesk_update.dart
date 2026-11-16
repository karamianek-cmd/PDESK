import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

const _kMembersUrl = 'https://desk.parsipol.com/members/';
const _kDownloadEvent = 'parsidesk-download-new-version';
const _kInstallEvent = 'parsidesk-update-me';
const _kCyan = Color(0xFF06B6D4);

bool _notificationShown = false;

/// One-shot startup prompt. The persistent card stays available afterwards.
void triggerParsideskUpdateNotification(String updateUrl) {
  if (isWeb || updateUrl.isEmpty || _notificationShown) return;
  _notificationShown = true;
  showParsideskUpdateDialog();
}

Future<void> showParsideskUpdateDialog() async {
  final version = bind.mainGetNewVersion();
  gFFI.dialogManager.dismissAll();
  await gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Row(children: [
        const Icon(Icons.system_update_alt, color: MyTheme.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(translate('Update available'))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate('A new version is ready to download and install.')),
          if (version.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: MyTheme.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                version,
                style: const TextStyle(
                    color: MyTheme.accent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      actions: [
        dialogButton('Later', onPressed: close, isOutline: true),
        dialogButton('Update now', onPressed: () {
          close();
          startParsideskUpdate();
        }),
      ],
      onCancel: close,
    );
  });
}

/// Begins the update. On Windows this downloads and installs in-app; on other
/// platforms it opens the download page (seamless install is Windows-only).
Future<void> startParsideskUpdate() async {
  if (!isWindows) {
    await launchUrl(Uri.parse(_kMembersUrl));
    return;
  }
  final String url;
  try {
    url = await bind.mainGetCommon(key: 'parsidesk-verified-download-url');
  } catch (e) {
    _showParsideskUpdateError(e.toString());
    return;
  }
  if (url.isEmpty || url.startsWith('error:')) {
    _showParsideskUpdateError(url.replaceFirst('error:', ''));
    return;
  }

  final downloadId = SimpleWrapper('');
  final onCanceled = SimpleWrapper<VoidCallback>(() {});
  Future<void> cancel() async {
    onCanceled.value();
    await bind.mainSetCommon(
        key: 'cancel-downloader', value: downloadId.value);
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if ('error:Downloader not found' ==
          await bind.mainGetCommon(
              key: 'download-data-${downloadId.value}')) {
        break;
      }
    }
  }

  gFFI.dialogManager.dismissAll();
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Downloading update')),
      content: ParsideskUpdateProgress(url, downloadId, onCanceled)
          .marginSymmetric(horizontal: 8)
          .paddingOnly(top: 12),
      actions: [
        dialogButton('Cancel', onPressed: () async {
          await cancel();
          close();
        }, isOutline: true),
      ],
      onCancel: () async {
        await cancel();
        close();
      },
    );
  });
}

void _showParsideskUpdateError(String error) {
  debugPrint('ParsiDesk update error: $error');
  gFFI.dialogManager.dismissAll();
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Row(children: [
        const Icon(Icons.error_outline, color: Colors.redAccent),
        const SizedBox(width: 10),
        Expanded(child: Text(translate('Error'))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate(
              'The update could not be completed. Retry or download it from the website.')),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectionArea(
              child: Text(error,
                  style: const TextStyle(
                      fontSize: 12, color: MyTheme.darkGray)),
            ),
          ],
        ],
      ),
      actions: [
        dialogButton('Download', onPressed: () {
          launchUrl(Uri.parse(_kMembersUrl));
          close();
        }, isOutline: true),
        dialogButton('Retry', onPressed: () {
          close();
          startParsideskUpdate();
        }),
        dialogButton('Close', onPressed: close, isOutline: true),
      ],
      onCancel: close,
    );
  });
}

/// A small, elegant card that remains on the home page until the app updates.
class ParsideskUpdateCard extends StatelessWidget {
  final String updateUrl;
  const ParsideskUpdateCard({Key? key, required this.updateUrl})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final version = bind.mainGetNewVersion();
    final isWide = isDesktop || isWebDesktop;
    final icon = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MyTheme.accent.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.system_update_alt,
          color: MyTheme.accent, size: 22),
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(translate('Update available'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          version.isEmpty
              ? translate('A new version is available.')
              : '${translate('A new version is available.')} ($version)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final button = ElevatedButton(
      onPressed: () => startParsideskUpdate(),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: MyTheme.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(translate('Update now')),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          MyTheme.accent.withOpacity(0.08),
          _kCyan.withOpacity(0.08),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyTheme.accent.withOpacity(0.35)),
      ),
      child: isWide
          ? Row(children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: text),
              const SizedBox(width: 10),
              button,
            ])
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(child: text),
                ]),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: button),
              ],
            ),
    );
  }
}

class ParsideskUpdateProgress extends StatefulWidget {
  final String downloadUrl;
  final SimpleWrapper downloadId;
  final SimpleWrapper onCanceled;
  const ParsideskUpdateProgress(
      this.downloadUrl, this.downloadId, this.onCanceled,
      {Key? key})
      : super(key: key);

  @override
  State<ParsideskUpdateProgress> createState() =>
      _ParsideskUpdateProgressState();
}

class _ParsideskUpdateProgressState extends State<ParsideskUpdateProgress> {
  Timer? _timer;
  int? _totalSize;
  int _downloadedSize = 0;
  bool _downloadFinished = false;
  bool _installing = false;
  int _getDataFailedCount = 0;

  @override
  void initState() {
    super.initState();
    widget.onCanceled.value = () => _cancelQueryTimer();
    platformFFI.registerEventHandler(
        _kDownloadEvent, _kDownloadEvent, _handleDownload,
        replace: true);
    bind.mainSetCommon(
        key: 'parsidesk-download-new-version', value: widget.downloadUrl);
  }

  @override
  void dispose() {
    _cancelQueryTimer();
    platformFFI.unregisterEventHandler(_kDownloadEvent, _kDownloadEvent);
    platformFFI.unregisterEventHandler(_kInstallEvent, _kInstallEvent);
    super.dispose();
  }

  void _cancelQueryTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _handleDownload(Map<String, dynamic> evt) async {
    if (evt.containsKey('id')) {
      widget.downloadId.value = evt['id'] as String;
      _timer = Timer.periodic(
          const Duration(milliseconds: 300), (_) => _updateDownloadData());
    } else {
      _onError(evt['error']?.toString() ?? '$evt');
    }
  }

  void _updateDownloadData() {
    String err = '';
    final data =
        bind.mainGetCommonSync(key: 'download-data-${widget.downloadId.value}');
    if (data.startsWith('error:')) {
      err = data.substring('error:'.length);
    } else {
      try {
        jsonDecode(data).forEach((key, value) {
          if (key == 'total_size') {
            if (value is int) _totalSize = value;
          } else if (key == 'downloaded_size') {
            _downloadedSize = value as int;
          } else if (key == 'finished') {
            _downloadFinished = value as bool;
          } else if (key == 'error') {
            if (value != null) err = value.toString();
          }
        });
        if (err.isEmpty &&
            _downloadFinished &&
            _totalSize != null &&
            _totalSize! > 0 &&
            _downloadedSize >= _totalSize!) {
          _cancelQueryTimer();
          bind.mainSetCommon(
              key: 'remove-downloader', value: widget.downloadId.value);
          setState(() => _installing = true);
          _install();
          return;
        }
      } catch (e) {
        _getDataFailedCount += 1;
        if (_getDataFailedCount > 3) err = e.toString();
      }
    }
    if (err.isNotEmpty) {
      _onError(err);
    } else {
      setState(() {});
    }
  }

  Future<void> _install() async {
    platformFFI.registerEventHandler(_kInstallEvent, _kInstallEvent,
        (evt) async {
      if (evt.containsKey('error')) {
        _onError(evt['error'] as String);
      }
    }, replace: true);
    try {
      await bind.mainSetCommon(
          key: 'parsidesk-update-me', value: widget.downloadUrl);
    } catch (e) {
      _onError(e.toString());
    }
  }

  void _onError(String error) {
    _cancelQueryTimer();
    _showParsideskUpdateError(error);
  }

  double? get _fraction {
    if (_installing) return null;
    if (_totalSize == null || _totalSize == 0) return 0.0;
    return (_downloadedSize / _totalSize!).clamp(0.0, 1.0);
  }

  String _sizeText() {
    if (_totalSize == null || _totalSize == 0) return '';
    final mb = 1048576.0;
    return '${(_downloadedSize / mb).toStringAsFixed(1)} / '
        '${(_totalSize! / mb).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _fraction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 14,
            child: Stack(children: [
              Container(color: MyTheme.accent.withOpacity(0.12)),
              if (fraction == null)
                const LinearProgressIndicator(
                  minHeight: 14,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(MyTheme.accent),
                )
              else
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: fraction,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [MyTheme.accent, _kCyan]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              fraction == null
                  ? translate('Installing update')
                  : '${(fraction * 100).floor()}%',
              style: const TextStyle(
                  color: MyTheme.accent, fontWeight: FontWeight.bold),
            ),
            Text(_sizeText(),
                style: const TextStyle(
                    fontSize: 12, color: MyTheme.darkGray)),
          ],
        ),
        if (fraction == null) ...[
          const SizedBox(height: 8),
          Text(
            translate(
                'The app will restart automatically to finish installing.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}