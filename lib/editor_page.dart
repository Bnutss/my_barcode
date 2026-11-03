import 'dart:convert';
import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, KeyUpEvent, LogicalKeyboardKey, Uint8List;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:window_manager/window_manager.dart';

import 'main.dart' show micaEnabled;
import 'models.dart';
import 'pdf_builder.dart';
import 'templates.dart';

const double _ptToMm = 25.4 / 72;

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WindowListener {
  double labelW = 60;
  double labelH = 40;
  final List<LabelElement> elements = [];
  int _nextId = 1;
  int? selectedId;

  List<Printer> printers = [];
  Printer? printer;
  int copies = 1;
  bool printing = false;

  String? templateName;
  String _saved = '';

  final Map<int, TextEditingController> _ctls = {};
  final FocusNode _pageFocus = FocusNode(debugLabel: 'editor');

  FluentThemeData get t => FluentTheme.of(context);

  LabelElement? get selected {
    for (final e in elements) {
      if (e.id == selectedId) return e;
    }
    return null;
  }

  // ---------------------------------------------------------------- lifecycle

  @override
  void initState() {
    super.initState();
    _add(ElementType.text,
        text: 'Товар', x: 3, y: 3, w: 54, fontSize: 12, bold: true);
    _add(ElementType.line, x: 3, y: 11, w: 54);
    _add(ElementType.barcode, text: '123456789012', x: 5, y: 14, w: 50, h: 20);
    selectedId = null;
    _saved = _snapshot();
    if (Platform.isWindows) windowManager.addListener(this);
    _loadPrinters();
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
    _pageFocus.dispose();
    for (final c in _ctls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (await _confirmDiscard()) {
      // Сначала прячем окно, чтобы закрытие выглядело мгновенным, и завершаем
      // процесс сразу: остановка движка Flutter вручную занимает заметное время.
      await windowManager.hide();
      exit(0);
    }
  }

  Future<void> _loadPrinters() async {
    try {
      final list = await Printing.listPrinters();
      if (!mounted) return;
      setState(() {
        printers = list;
        printer = list.where((p) => p.name == printer?.name).firstOrNull ??
            list.where((p) => p.isDefault).firstOrNull ??
            list.firstOrNull;
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------------ model

  void _add(
    ElementType type, {
    String text = '',
    double x = 3,
    double y = 3,
    double w = 20,
    double h = 8,
    double fontSize = 10,
    bool bold = false,
  }) {
    final e = LabelElement(
      id: _nextId++,
      type: type,
      x: x,
      y: y,
      w: w,
      h: h,
      text: type == ElementType.text && text.isEmpty ? 'Текст' : text,
      fontSize: fontSize,
      bold: bold,
    );
    if (type == ElementType.barcode && text.isEmpty) e.text = '123456789012';
    if (type == ElementType.line) e.h = 0.3;
    setState(() {
      elements.add(e);
      selectedId = e.id;
    });
  }

  void _duplicate(LabelElement src) {
    final e = LabelElement.fromJson(_nextId++, src.toJson())
      ..x = src.x + 2
      ..y = src.y + 2;
    setState(() {
      elements.add(e);
      selectedId = e.id;
    });
  }

  void _remove(LabelElement e) {
    setState(() {
      elements.remove(e);
      _ctls.remove(e.id)?.dispose();
      selectedId = null;
    });
  }

  String _snapshot() => jsonEncode({
        'w': labelW,
        'h': labelH,
        'e': [for (final e in elements) e.toJson()],
      });

  bool get dirty => _snapshot() != _saved;

  TextEditingController _ctl(LabelElement e) =>
      _ctls.putIfAbsent(e.id, () => TextEditingController(text: e.text));

  double _r(double v) => (v * 10).round() / 10;

  // ----------------------------------------------------------------- dialogs

  void _notify(String msg, {InfoBarSeverity severity = InfoBarSeverity.info}) {
    if (!mounted) return;
    displayInfoBar(
      context,
      duration: const Duration(seconds: 4),
      builder: (ctx, close) => InfoBar(
        title: Text(msg),
        severity: severity,
        onClose: close,
      ),
    );
  }

  /// true — можно продолжать (сохранили, отказались от изменений или их нет).
  Future<bool> _confirmDiscard() async {
    if (!dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Есть несохранённые изменения'),
        constraints: const BoxConstraints(maxWidth: 360),
        content: Text(templateName == null
            ? 'Макет не сохранён как шаблон. Сохранить?'
            : 'Изменения в шаблоне «$templateName» не сохранены. Сохранить?'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Сохранить')),
          Button(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Не сохранять')),
          Button(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Отмена')),
        ],
      ),
    );
    if (choice == 'discard') return true;
    if (choice == 'save') {
      await _saveTemplate();
      return !dirty;
    }
    return false;
  }

  Future<void> _saveTemplate() async {
    final c = TextEditingController(text: templateName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Сохранить шаблон'),
        constraints: const BoxConstraints(maxWidth: 340),
        content: InfoLabel(
          label: 'Название',
          child: TextBox(
            controller: c,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Сохранить')),
          Button(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      if (name.trim() != templateName && await TemplateStore.exists(name)) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => ContentDialog(
            title: Text('Шаблон «${name.trim()}» уже есть'),
            content: const Text('Перезаписать?'),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Перезаписать')),
              Button(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Нет')),
            ],
          ),
        );
        if (ok != true) return;
      }
      await TemplateStore.save(name, labelW, labelH, elements);
      setState(() {
        templateName = name.trim();
        _saved = _snapshot();
      });
      _notify('Шаблон сохранён', severity: InfoBarSeverity.success);
    } catch (e) {
      _notify('Не удалось сохранить: $e', severity: InfoBarSeverity.error);
    }
  }

  Future<void> _loadTemplate() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    List<String> names;
    try {
      names = await TemplateStore.list();
    } catch (e) {
      _notify('Не удалось прочитать шаблоны: $e',
          severity: InfoBarSeverity.error);
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => ContentDialog(
          title: const Text('Открыть шаблон'),
          constraints: const BoxConstraints(maxWidth: 360),
          content: SizedBox(
            height: 240,
            child: names.isEmpty
                ? const Center(child: Text('Сохранённых шаблонов нет'))
                : ListView(children: [
                    for (final n in names)
                      ListTile(
                        leading: const Icon(FluentIcons.document),
                        title: Text(n),
                        onPressed: () => Navigator.pop(ctx, n),
                        trailing: Tooltip(
                          message: 'Удалить шаблон',
                          child: IconButton(
                            icon: const Icon(FluentIcons.delete),
                            onPressed: () async {
                              await TemplateStore.delete(n);
                              setD(() => names.remove(n));
                            },
                          ),
                        ),
                      ),
                  ]),
          ),
          actions: [
            Button(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Закрыть')),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      final tpl = await TemplateStore.load(picked);
      setState(() {
        labelW = tpl.width;
        labelH = tpl.height;
        elements
          ..clear()
          ..addAll(tpl.elements);
        _nextId = elements.length + 1;
        selectedId = null;
        for (final c in _ctls.values) {
          c.dispose();
        }
        _ctls.clear();
        templateName = picked;
        _saved = _snapshot();
      });
    } catch (e) {
      _notify('Файл шаблона повреждён: $e', severity: InfoBarSeverity.error);
    }
  }

  // ------------------------------------------------------- preview and print

  Future<void> _preview() async {
    try {
      final bytes = await buildLabelPdf(
          widthMm: labelW, heightMm: labelH, elements: elements);
      Uint8List? png;
      await for (final page
          in Printing.raster(bytes, pages: [0], dpi: 300)) {
        png = await page.toPng();
        break;
      }
      if (png == null || !mounted) return;
      final data = png;
      await showDialog(
        context: context,
        builder: (ctx) => ContentDialog(
          title: Text('Предпросмотр · ${_fmt(labelW)} × ${_fmt(labelH)} мм'),
          constraints: const BoxConstraints(maxWidth: 640),
          content: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Color(0x40000000))
                ],
              ),
              child: Image.memory(data, fit: BoxFit.contain),
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Закрыть')),
          ],
        ),
      );
    } catch (e) {
      _notify('Не удалось построить предпросмотр: $e',
          severity: InfoBarSeverity.error);
    }
  }

  Future<void> _print() async {
    if (printer == null) {
      _notify('Выберите принтер', severity: InfoBarSeverity.warning);
      return;
    }
    setState(() => printing = true);
    try {
      final bytes = await buildLabelPdf(
        widthMm: labelW,
        heightMm: labelH,
        elements: elements,
        copies: copies,
      );
      final ok = await Printing.directPrintPdf(
        printer: printer!,
        name: 'Стикер',
        format: PdfPageFormat(labelW * mm, labelH * mm, marginAll: 0),
        onLayout: (_) async => bytes,
      );
      _notify(
        ok ? 'Отправлено на печать: $copies шт.' : 'Принтер не принял задание',
        severity: ok ? InfoBarSeverity.success : InfoBarSeverity.error,
      );
    } catch (e) {
      _notify('Ошибка печати: $e', severity: InfoBarSeverity.error);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  // --------------------------------------------------------------- keyboard

  bool _typing() {
    final c = FocusManager.instance.primaryFocus?.context;
    return c != null &&
        (c.widget is EditableText ||
            c.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent ev) {
    if (ev is KeyUpEvent) return KeyEventResult.ignored;
    final k = ev.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && k == LogicalKeyboardKey.keyS) {
      _saveTemplate();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyO) {
      _loadTemplate();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyP) {
      _print();
      return KeyEventResult.handled;
    }
    final e = selected;
    if (e == null || _typing()) return KeyEventResult.ignored;
    final step = HardwareKeyboard.instance.isShiftPressed ? 5.0 : 0.5;
    if (k == LogicalKeyboardKey.delete) {
      _remove(e);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => e.x = _r(e.x - step));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => e.x = _r(e.x + step));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => e.y = _r(e.y - step));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => e.y = _r(e.y + step));
    } else if (ctrl && k == LogicalKeyboardKey.keyD) {
      _duplicate(e);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // -------------------------------------------------------------------- build

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Color get _bg => micaEnabled ? Colors.transparent : t.scaffoldBackgroundColor;
  Color get _panelBg => micaEnabled
      ? t.resources.cardBackgroundFillColorDefault
      : t.resources.solidBackgroundFillColorSecondary;
  Color get _stroke => t.resources.dividerStrokeColorDefault;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _pageFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        color: _bg,
        child: Column(
          children: [
            _titleBar(),
            _commandBar(),
            Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: 252, child: _leftPanel()),
                  Container(width: 1, color: _stroke),
                  Expanded(child: _canvas()),
                  Container(width: 1, color: _stroke),
                  SizedBox(width: 308, child: _propsPanel()),
                ],
              ),
            ),
            _statusBar(),
          ],
        ),
      ),
    );
  }

  Widget _titleBar() {
    final title = Row(
      children: [
        const SizedBox(width: 12),
        Image.asset(
          'assets/images/AA.png',
          width: 16,
          height: 16,
          cacheWidth: 48,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) =>
              Icon(FluentIcons.tag, size: 14, color: t.accentColor),
        ),
        const SizedBox(width: 8),
        Text(
          'Печать стикеров',
          style: t.typography.caption,
        ),
        if (templateName != null) ...[
          Text('  ·  ', style: t.typography.caption),
          Text('$templateName${dirty ? ' •' : ''}',
              style: t.typography.caption
                  ?.copyWith(color: t.resources.textFillColorSecondary)),
        ] else if (dirty)
          Text('  •', style: t.typography.caption),
      ],
    );
    return SizedBox(
      height: 32,
      child: Platform.isWindows
          ? WindowCaption(
              brightness: t.brightness,
              backgroundColor: Colors.transparent,
              title: Align(alignment: Alignment.centerLeft, child: title),
            )
          : Align(alignment: Alignment.centerLeft, child: title),
    );
  }

  Widget _commandBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Открыть шаблон (Ctrl+O)',
            child: Button(
              onPressed: _loadTemplate,
              child: const Row(children: [
                Icon(FluentIcons.open_file, size: 14),
                SizedBox(width: 8),
                Text('Открыть'),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Сохранить шаблон (Ctrl+S)',
            child: Button(
              onPressed: _saveTemplate,
              child: const Row(children: [
                Icon(FluentIcons.save, size: 14),
                SizedBox(width: 8),
                Text('Сохранить'),
              ]),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 250,
            child: ComboBox<String>(
              isExpanded: true,
              placeholder: const Text('Выберите принтер'),
              value: printer?.name,
              items: [
                for (final p in printers)
                  ComboBoxItem(
                    value: p.name,
                    child: Row(children: [
                      const Icon(FluentIcons.print, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
              ],
              onChanged: (n) => setState(
                  () => printer = printers.firstWhere((p) => p.name == n)),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Обновить список принтеров',
            child: IconButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: _loadPrinters,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Копий'),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: NumberBox<int>(
              value: copies,
              min: 1,
              max: 999,
              mode: SpinButtonPlacementMode.inline,
              onChanged: (v) => setState(() => copies = v ?? 1),
            ),
          ),
          const SizedBox(width: 12),
          Button(
            onPressed: _preview,
            child: const Row(children: [
              Icon(FluentIcons.view, size: 14),
              SizedBox(width: 8),
              Text('Просмотр'),
            ]),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Печать (Ctrl+P)',
            child: FilledButton(
              onPressed: printing ? null : _print,
              child: Row(children: [
                if (printing)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2))
                else
                  const Icon(FluentIcons.print, size: 14),
                const SizedBox(width: 8),
                const Text('Печать'),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    final e = selected;
    final style = t.typography.caption
        ?.copyWith(color: t.resources.textFillColorSecondary);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _stroke))),
      child: Row(
        children: [
          Text('Стикер ${_fmt(labelW)} × ${_fmt(labelH)} мм', style: style),
          const SizedBox(width: 16),
          Text('Элементов: ${elements.length}', style: style),
          if (e != null) ...[
            const SizedBox(width: 16),
            Text('${e.title}: X ${_fmt(e.x)}, Y ${_fmt(e.y)} мм', style: style),
          ],
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Стрелки — сдвиг, Shift — крупнее, Del — удалить',
              style: style,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: _stroke),
          const SizedBox(width: 12),
          Text('Asad Abdullajonov Programm',
              style: style?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- left panel

  IconData _iconFor(ElementType type) => switch (type) {
        ElementType.text => FluentIcons.font,
        ElementType.line => FluentIcons.line,
        ElementType.rect => FluentIcons.rectangle_shape,
        ElementType.barcode => FluentIcons.generic_scan,
      };

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: t.typography.bodyStrong),
      );

  Widget _leftPanel() {
    return Container(
      color: _panelBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          _header('Размер стикера, мм'),
          Row(children: [
            Expanded(
              child: NumField(
                label: 'Ширина',
                value: labelW,
                min: 10,
                max: 300,
                onChanged: (v) => setState(() => labelW = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                label: 'Высота',
                value: labelH,
                min: 10,
                max: 300,
                onChanged: (v) => setState(() => labelH = v),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in const [
              [60.0, 40.0],
              [58.0, 40.0],
              [40.0, 30.0],
              [100.0, 50.0],
            ])
              ToggleButton(
                checked: labelW == p[0] && labelH == p[1],
                onChanged: (_) => setState(() {
                  labelW = p[0];
                  labelH = p[1];
                }),
                child: Text('${_fmt(p[0])}×${_fmt(p[1])}'),
              ),
          ]),
          _header('Добавить'),
          Row(children: [
            Expanded(child: _addTile(ElementType.text, 'Текст')),
            const SizedBox(width: 8),
            Expanded(child: _addTile(ElementType.barcode, 'Штрих-код')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _addTile(ElementType.line, 'Линия')),
            const SizedBox(width: 8),
            Expanded(child: _addTile(ElementType.rect, 'Рамка')),
          ]),
          _header('Слои'),
          if (elements.isEmpty)
            Text('Стикер пуст. Добавьте элемент выше.',
                style: t.typography.caption
                    ?.copyWith(color: t.resources.textFillColorSecondary)),
          for (final e in elements.reversed)
            ListTile.selectable(
              selected: e.id == selectedId,
              leading: Icon(_iconFor(e.type), size: 16),
              title: Text(
                e.type == ElementType.text || e.type == ElementType.barcode
                    ? (e.text.isEmpty ? e.title : e.text)
                    : e.title,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => setState(() => selectedId = e.id),
            ),
        ],
      ),
    );
  }

  Widget _addTile(ElementType type, String label) {
    return SizedBox(
      height: 80,
      child: Button(
        onPressed: () => _add(type),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconFor(type), size: 20),
            const SizedBox(height: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- canvas

  Widget _canvas() {
    return Container(
      color: micaEnabled
          ? Colors.transparent
          : t.resources.solidBackgroundFillColorTertiary,
      child: LayoutBuilder(builder: (context, c) {
        final scale = (((c.maxWidth - 80) / labelW)
                .clamp(1.0, 40.0))
            .clamp(0.0, ((c.maxHeight - 100) / labelH).clamp(1.0, 40.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => selectedId = null);
            _pageFocus.requestFocus();
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: labelW * scale,
                  height: labelH * scale,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: const [
                      BoxShadow(
                          blurRadius: 16,
                          offset: Offset(0, 4),
                          color: Color(0x33000000)),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: () => setState(() => selectedId = null),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        for (final e in elements) _canvasElement(e, scale),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_fmt(labelW)} × ${_fmt(labelH)} мм',
                  style: t.typography.caption
                      ?.copyWith(color: t.resources.textFillColorSecondary),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Size _elementSize(LabelElement e) {
    switch (e.type) {
      case ElementType.line:
        return e.vertical ? Size(e.thickness, e.h) : Size(e.w, e.thickness);
      case ElementType.text:
        return Size(e.w, e.fontSize * _ptToMm * 1.25);
      default:
        return Size(e.w, e.h);
    }
  }

  Widget _canvasElement(LabelElement e, double s) {
    final size = _elementSize(e);
    final isSel = e.id == selectedId;
    final accent = t.accentColor;
    Widget content;
    switch (e.type) {
      case ElementType.text:
        content = Text(
          e.text,
          style: TextStyle(
            color: Colors.black,
            fontSize: e.fontSize * _ptToMm * s,
            fontWeight: e.bold ? FontWeight.bold : FontWeight.normal,
            height: 1.0,
            fontFamily: 'Arial',
          ),
        );
      case ElementType.line:
        content = Container(color: Colors.black);
      case ElementType.rect:
        content = Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: e.thickness * s),
          ),
        );
      case ElementType.barcode:
        final bc = e.kind.barcode;
        content = (e.text.isEmpty || !bc.isValid(e.text))
            ? Container(
                color: Colors.red.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Text('Неверное значение',
                    style: TextStyle(color: Colors.red, fontSize: 11)),
              )
            : BarcodeWidget(
                barcode: bc,
                data: e.text,
                drawText: e.showText && e.kind != BarcodeKind.qr,
                style: TextStyle(fontSize: 7 * _ptToMm * s),
                color: Colors.black,
              );
    }

    // Невидимая область побольше, чтобы тонкую линию было легко схватить.
    const pad = 6.0;
    return Positioned(
      left: e.x * s - pad,
      top: e.y * s - pad,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          setState(() => selectedId = e.id);
          _pageFocus.requestFocus();
        },
        onPanStart: (_) {
          setState(() => selectedId = e.id);
          _pageFocus.requestFocus();
        },
        onPanUpdate: (d) => setState(() {
          e.x = _r(e.x + d.delta.dx / s);
          e.y = _r(e.y + d.delta.dy / s);
        }),
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Padding(
            padding: const EdgeInsets.all(pad),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: size.width * s,
                  height: size.height * s,
                  decoration: isSel
                      ? BoxDecoration(
                          border: Border.all(color: accent, width: 1.5))
                      : null,
                  child: ClipRect(child: content),
                ),
                if (isSel)
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        if (e.type == ElementType.line) {
                          if (e.vertical) {
                            e.h = _r(e.h + d.delta.dy / s).clamp(1, 500);
                          } else {
                            e.w = _r(e.w + d.delta.dx / s).clamp(1, 500);
                          }
                        } else {
                          e.w = _r(e.w + d.delta.dx / s).clamp(1, 500);
                          if (e.type != ElementType.text) {
                            e.h = _r(e.h + d.delta.dy / s).clamp(1, 500);
                          }
                        }
                      }),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: accent, width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- properties panel

  static String _hint(BarcodeKind k) => switch (k) {
        BarcodeKind.code128 => 'Любые символы латиницы и цифры',
        BarcodeKind.ean13 => '12 или 13 цифр (контрольная считается сама)',
        BarcodeKind.code39 => 'Заглавные A–Z, цифры, пробел и - . \$ / + %',
        BarcodeKind.qr => 'Любой текст или ссылка',
      };

  Widget _propsPanel() {
    final e = selected;
    return Container(
      color: _panelBg,
      child: e == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.touch_pointer,
                        size: 28, color: t.resources.textFillColorSecondary),
                    const SizedBox(height: 12),
                    Text('Выберите элемент на стикере',
                        textAlign: TextAlign.center,
                        style: t.typography.body?.copyWith(
                            color: t.resources.textFillColorSecondary)),
                  ],
                ),
              ),
            )
          : _props(e),
    );
  }

  Widget _props(LabelElement e) {
    final isLine = e.type == ElementType.line;
    final invalid = e.type == ElementType.barcode &&
        (e.text.isEmpty || !e.kind.barcode.isValid(e.text));
    return ListView(
      key: ValueKey(e.id),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(children: [
            Icon(_iconFor(e.type), size: 18),
            const SizedBox(width: 8),
            Text(e.title, style: t.typography.subtitle),
            const Spacer(),
            Tooltip(
              message: 'Дублировать (Ctrl+D)',
              child: IconButton(
                icon: const Icon(FluentIcons.copy),
                onPressed: () => _duplicate(e),
              ),
            ),
            Tooltip(
              message: 'Удалить (Del)',
              child: IconButton(
                icon: Icon(FluentIcons.delete, color: Colors.red),
                onPressed: () => _remove(e),
              ),
            ),
          ]),
        ),
        if (e.type == ElementType.text || e.type == ElementType.barcode) ...[
          _header('Содержимое'),
          InfoLabel(
            label: e.type == ElementType.text ? 'Текст' : 'Значение',
            child: TextBox(
              controller: _ctl(e),
              placeholder: e.type == ElementType.text
                  ? 'Введите текст'
                  : 'Введите число или код',
              onChanged: (v) => setState(() => e.text = v),
            ),
          ),
        ],
        if (e.type == ElementType.barcode) ...[
          const SizedBox(height: 12),
          InfoLabel(
            label: 'Тип штрих-кода',
            child: ComboBox<BarcodeKind>(
              isExpanded: true,
              value: e.kind,
              items: [
                for (final k in BarcodeKind.values)
                  ComboBoxItem(value: k, child: Text(k.title)),
              ],
              onChanged: (k) => setState(() {
                e.kind = k!;
                if (k == BarcodeKind.ean13 && !k.barcode.isValid(e.text)) {
                  e.text = '123456789012';
                  _ctl(e).text = e.text;
                }
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (invalid) ...[
              Icon(FluentIcons.error_badge, size: 14, color: Colors.red),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                invalid
                    ? 'Неверное значение. ${_hint(e.kind)}'
                    : _hint(e.kind),
                style: t.typography.caption?.copyWith(
                    color: invalid
                        ? Colors.red
                        : t.resources.textFillColorSecondary),
              ),
            ),
          ]),
          if (e.kind != BarcodeKind.qr) ...[
            const SizedBox(height: 12),
            ToggleSwitch(
              checked: e.showText,
              onChanged: (v) => setState(() => e.showText = v),
              content: const Text('Цифры под кодом'),
            ),
          ],
        ],
        if (e.type == ElementType.text) ...[
          _header('Шрифт'),
          NumField(
            label: 'Размер, pt',
            value: e.fontSize,
            min: 3,
            max: 100,
            onChanged: (v) => setState(() => e.fontSize = v),
          ),
          const SizedBox(height: 12),
          ToggleSwitch(
            checked: e.bold,
            onChanged: (v) => setState(() => e.bold = v),
            content: const Text('Жирный'),
          ),
        ],
        if (isLine || e.type == ElementType.rect) ...[
          _header('Линия'),
          NumField(
            label: 'Толщина, мм',
            value: e.thickness,
            min: 0.1,
            max: 5,
            onChanged: (v) => setState(() => e.thickness = v),
          ),
        ],
        if (isLine) ...[
          const SizedBox(height: 12),
          ToggleSwitch(
            checked: e.vertical,
            onChanged: (v) => setState(() => e.vertical = v),
            content: const Text('Вертикальная'),
          ),
        ],
        _header('Положение, мм'),
        Row(children: [
          Expanded(
            child: NumField(
                label: 'X',
                value: e.x,
                min: -500,
                max: 500,
                onChanged: (v) => setState(() => e.x = v)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NumField(
                label: 'Y',
                value: e.y,
                min: -500,
                max: 500,
                onChanged: (v) => setState(() => e.y = v)),
          ),
        ]),
        ...[
          _header('Размер, мм'),
          Row(children: [
            if (!(isLine && e.vertical))
              Expanded(
                child: NumField(
                    label: isLine ? 'Длина' : 'Ширина',
                    value: e.w,
                    min: 0.5,
                    max: 500,
                    onChanged: (v) => setState(() => e.w = v)),
              ),
            if (!(isLine && e.vertical) &&
                e.type != ElementType.text &&
                !isLine)
              const SizedBox(width: 8),
            if (e.type != ElementType.text && !(isLine && !e.vertical))
              Expanded(
                child: NumField(
                    label: isLine ? 'Длина' : 'Высота',
                    value: e.h,
                    min: 0.5,
                    max: 500,
                    onChanged: (v) => setState(() => e.h = v)),
              ),
          ]),
        ],
      ],
    );
  }
}

/// Числовое поле Fluent с подписью.
class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1000,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return InfoLabel(
      label: label,
      child: NumberBox<double>(
        value: value,
        min: min,
        max: max,
        precision: 1,
        smallChange: 0.5,
        largeChange: 5,
        mode: SpinButtonPlacementMode.inline,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
