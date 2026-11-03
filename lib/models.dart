import 'package:barcode/barcode.dart';

enum ElementType { text, line, rect, barcode }

enum BarcodeKind { code128, ean13, code39, qr }

extension BarcodeKindX on BarcodeKind {
  String get title => switch (this) {
        BarcodeKind.code128 => 'Code 128',
        BarcodeKind.ean13 => 'EAN-13',
        BarcodeKind.code39 => 'Code 39',
        BarcodeKind.qr => 'QR-код',
      };

  Barcode get barcode => switch (this) {
        BarcodeKind.code128 => Barcode.code128(),
        BarcodeKind.ean13 => Barcode.ean13(),
        BarcodeKind.code39 => Barcode.code39(),
        BarcodeKind.qr => Barcode.qrCode(),
      };
}

/// Все размеры и координаты — в миллиметрах.
class LabelElement {
  LabelElement({
    required this.id,
    required this.type,
    this.x = 2,
    this.y = 2,
    this.w = 20,
    this.h = 8,
    this.text = '',
    this.fontSize = 10,
    this.bold = false,
    this.thickness = 0.3,
    this.vertical = false,
    this.kind = BarcodeKind.code128,
    this.showText = true,
  });

  final int id;
  final ElementType type;
  double x, y, w, h;
  String text; // текст или значение штрих-кода
  double fontSize; // pt
  bool bold;
  double thickness; // мм, для линий и рамок
  bool vertical;
  BarcodeKind kind;
  bool showText;

  String get title => switch (type) {
        ElementType.text => 'Текст',
        ElementType.line => 'Линия',
        ElementType.rect => 'Рамка',
        ElementType.barcode => 'Штрих-код',
      };

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'text': text,
        'fontSize': fontSize,
        'bold': bold,
        'thickness': thickness,
        'vertical': vertical,
        'kind': kind.name,
        'showText': showText,
      };

  factory LabelElement.fromJson(int id, Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return LabelElement(
      id: id,
      type: ElementType.values.firstWhere((t) => t.name == j['type'],
          orElse: () => ElementType.text),
      x: d('x', 2),
      y: d('y', 2),
      w: d('w', 20),
      h: d('h', 8),
      text: j['text'] as String? ?? '',
      fontSize: d('fontSize', 10),
      bold: j['bold'] as bool? ?? false,
      thickness: d('thickness', 0.3),
      vertical: j['vertical'] as bool? ?? false,
      kind: BarcodeKind.values.firstWhere((k) => k.name == j['kind'],
          orElse: () => BarcodeKind.code128),
      showText: j['showText'] as bool? ?? true,
    );
  }
}
