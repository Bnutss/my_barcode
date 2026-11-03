import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';

const double mm = PdfPageFormat.mm;

pw.Font? _regular;
pw.Font? _bold;

/// Берём системный Arial (есть кириллица). Если нет — стандартный Helvetica.
Future<void> _loadFonts() async {
  if (_regular != null) return;
  try {
    final dir = Platform.isWindows ? 'C:\\Windows\\Fonts\\' : null;
    if (dir != null && File('${dir}arial.ttf').existsSync()) {
      _regular = pw.Font.ttf(
        ByteData.sublistView(await File('${dir}arial.ttf').readAsBytes()),
      );
      _bold = pw.Font.ttf(
        ByteData.sublistView(await File('${dir}arialbd.ttf').readAsBytes()),
      );
      return;
    }
  } catch (_) {}
  _regular = pw.Font.helvetica();
  _bold = pw.Font.helveticaBold();
}

Future<Uint8List> buildLabelPdf({
  required double widthMm,
  required double heightMm,
  required List<LabelElement> elements,
  int copies = 1,
}) async {
  await _loadFonts();
  final doc = pw.Document();
  final format = PdfPageFormat(widthMm * mm, heightMm * mm, marginAll: 0);

  for (var i = 0; i < copies; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) =>
            pw.Stack(children: [for (final e in elements) _element(e)]),
      ),
    );
  }
  return doc.save();
}

/// Высота строки текста в мм — та же оценка, что и на холсте редактора,
/// чтобы повёрнутый текст вращался вокруг одного и того же центра.
double textBoxHeightMm(LabelElement e) => e.fontSize * 25.4 / 72 * 1.25;

pw.Widget _element(LabelElement e) {
  pw.Widget child = switch (e.type) {
    ElementType.text => pw.SizedBox(
      width: e.w * mm,
      height: textBoxHeightMm(e) * mm,
      child: pw.Align(
        alignment: pw.Alignment.topLeft,
        child: pw.Text(
          e.text,
          style: pw.TextStyle(
            font: e.bold ? _bold : _regular,
            fontSize: e.fontSize,
          ),
        ),
      ),
    ),
    ElementType.line => pw.Container(
      width: e.w * mm,
      height: e.thickness * mm,
      color: PdfColors.black,
    ),
    ElementType.rect => pw.Container(
      width: e.w * mm,
      height: e.h * mm,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: e.thickness * mm),
      ),
    ),
    ElementType.barcode => _barcode(e),
    ElementType.image => _image(e),
  };
  if (e.rotation % 360 != 0) {
    // В PDF ось Y направлена вверх, поэтому знак угла обратный экранному.
    child = pw.Transform.rotate(
      angle: -e.rotation * math.pi / 180,
      alignment: pw.Alignment.center,
      child: child,
    );
  }
  return pw.Positioned(left: e.x * mm, top: e.y * mm, child: child);
}

pw.Widget _image(LabelElement e) {
  final bytes = e.imageBytes;
  final box = pw.SizedBox(width: e.w * mm, height: e.h * mm);
  if (bytes == null) return box;
  pw.Widget img = pw.SizedBox(
    width: e.w * mm,
    height: e.h * mm,
    child: pw.ClipRect(
      child: pw.Image(
        pw.MemoryImage(bytes),
        width: e.w * mm,
        height: e.h * mm,
        fit: e.cover ? pw.BoxFit.cover : pw.BoxFit.contain,
      ),
    ),
  );
  if (e.opacity < 1) img = pw.Opacity(opacity: e.opacity, child: img);
  return img;
}

pw.Widget _barcode(LabelElement e) {
  final bc = e.kind.barcode;
  if (e.text.isEmpty || !bc.isValid(e.text)) {
    return pw.SizedBox(width: e.w * mm, height: e.h * mm);
  }
  return pw.BarcodeWidget(
    barcode: bc,
    data: e.text,
    width: e.w * mm,
    height: e.h * mm,
    drawText: e.showText && e.kind != BarcodeKind.qr,
    textStyle: pw.TextStyle(font: _regular, fontSize: 7),
  );
}
