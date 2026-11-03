import 'dart:convert';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';

enum ElementType { text, line, rect, barcode, image }

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
    this.rotation = 0,
    this.kind = BarcodeKind.code128,
    this.showText = true,
    this.imageBytes,
    this.imageAspect = 1,
    this.opacity = 1,
    this.cover = false,
  });

  final int id;
  final ElementType type;
  double x, y, w, h;
  String text; // текст или значение штрих-кода
  double fontSize; // pt
  bool bold;
  double thickness; // мм, для линий и рамок
  double rotation; // градусы по часовой стрелке, вокруг центра элемента
  BarcodeKind kind;
  bool showText;
  Uint8List? imageBytes; // PNG
  double imageAspect; // ширина / высота исходной картинки
  double opacity; // 0..1, для изображений
  bool cover; // true — заполнить область с обрезкой, false — вписать

  String get title => switch (type) {
    ElementType.text => 'Текст',
    ElementType.line => 'Линия',
    ElementType.rect => 'Рамка',
    ElementType.barcode => 'Штрих-код',
    ElementType.image => 'Изображение',
  };

  /// [withImage] = false нужен для быстрого сравнения «были ли изменения»:
  /// картинку не кодируем, вместо неё берём её размер.
  Map<String, dynamic> toJson({bool withImage = true}) => {
    'type': type.name,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'text': text,
    'fontSize': fontSize,
    'bold': bold,
    'thickness': thickness,
    'rotation': rotation,
    'kind': kind.name,
    'showText': showText,
    'imageAspect': imageAspect,
    'opacity': opacity,
    'cover': cover,
    if (imageBytes != null)
      'image': withImage
          ? base64Encode(imageBytes!)
          : 'len:${imageBytes!.length}',
  };

  factory LabelElement.fromJson(int id, Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    final type = ElementType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => ElementType.text,
    );
    var w = d('w', 20);
    var h = d('h', 8);
    var rotation = d('rotation', 0);
    // Старые шаблоны: вертикальная линия хранилась флагом и длиной в h.
    if (type == ElementType.line && j['vertical'] == true) {
      final length = h;
      w = length;
      h = d('thickness', 0.3);
      rotation = 90;
    }
    final img = j['image'] as String?;
    return LabelElement(
      id: id,
      type: type,
      x: d('x', 2),
      y: d('y', 2),
      w: w,
      h: h,
      text: j['text'] as String? ?? '',
      fontSize: d('fontSize', 10),
      bold: j['bold'] as bool? ?? false,
      thickness: d('thickness', 0.3),
      rotation: rotation,
      kind: BarcodeKind.values.firstWhere(
        (k) => k.name == j['kind'],
        orElse: () => BarcodeKind.code128,
      ),
      showText: j['showText'] as bool? ?? true,
      imageBytes: img != null && !img.startsWith('len:')
          ? base64Decode(img)
          : null,
      imageAspect: d('imageAspect', 1),
      opacity: d('opacity', 1),
      cover: j['cover'] as bool? ?? false,
    );
  }
}
