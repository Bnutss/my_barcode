import 'dart:io';
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
          ByteData.sublistView(await File('${dir}arial.ttf').readAsBytes()));
      _bold = pw.Font.ttf(
          ByteData.sublistView(await File('${dir}arialbd.ttf').readAsBytes()));
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
  final format =
      PdfPageFormat(widthMm * mm, heightMm * mm, marginAll: 0);

  for (var i = 0; i < copies; i++) {
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [for (final e in elements) _element(e)],
      ),
    ));
  }
  return doc.save();
}

pw.Widget _element(LabelElement e) {
  final child = switch (e.type) {
    ElementType.text => pw.SizedBox(
        width: e.w * mm,
        child: pw.Text(
          e.text,
          style: pw.TextStyle(
            font: e.bold ? _bold : _regular,
            fontSize: e.fontSize,
          ),
        ),
      ),
    ElementType.line => pw.Container(
        width: (e.vertical ? e.thickness : e.w) * mm,
        height: (e.vertical ? e.h : e.thickness) * mm,
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
  };
  return pw.Positioned(left: e.x * mm, top: e.y * mm, child: child);
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
