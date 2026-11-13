import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class _Cursor extends Fake implements CursorModel {
  @override
  Rect? get keyHelpToolsRectToAdjustCanvas => null;
}

class _FFI extends Fake implements FFI {
  @override
  final SessionID sessionId = Uuid().v4obj();
  @override
  final CursorModel cursorModel = _Cursor();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mobile fit leaves room for the bottom toolbar', () {
    final wasMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = wasMobile);
    final ffi = _FFI();
    final canvas = CanvasModel(WeakReference(ffi));
    final media = MediaQueryData.fromView(ui.window);
    final portrait = media.size.height > media.size.width;
    final expected = media.size.height -
        CanvasModel.topToEdge -
        CanvasModel.bottomToEdge -
        media.viewInsets.bottom -
        (portrait ? media.padding.top : 0) -
        kMinInteractiveDimension -
        media.padding.bottom;
    expect(canvas.getSize().height, expected);
  });
}
