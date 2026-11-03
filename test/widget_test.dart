import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_barcode/editor_page.dart';
import 'package:my_barcode/models.dart';
import 'package:my_barcode/pdf_builder.dart';

void main() {
  test('PDF стикера строится', () async {
    final bytes = await buildLabelPdf(widthMm: 60, heightMm: 40, elements: [
      LabelElement(id: 1, type: ElementType.text, text: 'Test'),
      LabelElement(
          id: 2, type: ElementType.barcode, text: '123456789012', w: 50, h: 20),
    ]);
    expect(bytes.isNotEmpty, true);
  });

  test('Шаблон сохраняется и загружается', () async {
    final e = LabelElement(
        id: 1, type: ElementType.barcode, text: '123456789012', x: 5, w: 40);
    final back = LabelElement.fromJson(7, e.toJson());
    expect(back.id, 7);
    expect(back.type, ElementType.barcode);
    expect(back.text, '123456789012');
    expect(back.x, 5);
    expect(back.w, 40);
  });

  testWidgets('Редактор отрисовывается без ошибок', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FluentApp(
      themeMode: ThemeMode.dark,
      darkTheme: FluentThemeData(brightness: Brightness.dark),
      home: const EditorPage(),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Печать'), findsOneWidget);
    await tester.tap(find.text('Штрих-код').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  test('Старая вертикальная линия превращается в линию с поворотом 90°', () {
    final e = LabelElement.fromJson(1, {
      'type': 'line',
      'x': 5,
      'y': 5,
      'w': 0.3,
      'h': 30,
      'thickness': 0.3,
      'vertical': true,
    });
    expect(e.rotation, 90);
    expect(e.w, 30);
    expect(e.h, 0.3);
  });

  test('Изображение и поворот сохраняются в шаблоне', () {
    final e = LabelElement(
      id: 1,
      type: ElementType.image,
      imageBytes: Uint8List.fromList([1, 2, 3, 4]),
      imageAspect: 1.5,
      opacity: 0.4,
      cover: true,
      rotation: 33,
    );
    final back = LabelElement.fromJson(2, e.toJson());
    expect(back.imageBytes, [1, 2, 3, 4]);
    expect(back.imageAspect, 1.5);
    expect(back.opacity, 0.4);
    expect(back.cover, true);
    expect(back.rotation, 33);
    // Для быстрой проверки изменений картинка не кодируется целиком.
    expect(e.toJson(withImage: false)['image'], 'len:4');
  });

  testWidgets('Линию можно повернуть кнопкой', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FluentApp(home: const EditorPage()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Линия').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Поворот'), findsOneWidget);
    await tester.tap(find.text('90°'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('+15°'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
