import 'dart:convert';
import 'dart:io';

import 'models.dart';

class LabelTemplate {
  LabelTemplate(this.name, this.width, this.height, this.elements);
  final String name;
  final double width;
  final double height;
  final List<LabelElement> elements;
}

/// Шаблоны лежат в %APPDATA%\my_barcode\templates\*.json
class TemplateStore {
  static Directory get _dir {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return Directory(
      '$base${Platform.pathSeparator}my_barcode'
      '${Platform.pathSeparator}templates',
    );
  }

  static String _safe(String name) =>
      name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static File _file(String name) =>
      File('${_dir.path}${Platform.pathSeparator}${_safe(name)}.json');

  static Future<void> save(
    String name,
    double w,
    double h,
    List<LabelElement> elements,
  ) async {
    await _dir.create(recursive: true);
    final json = {
      'name': name.trim(),
      'width': w,
      'height': h,
      'elements': [for (final e in elements) e.toJson()],
    };
    await _file(name)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  static Future<List<String>> list() async {
    if (!await _dir.exists()) return [];
    final names = <String>[];
    await for (final f in _dir.list()) {
      if (f is File && f.path.endsWith('.json')) {
        final base = f.uri.pathSegments.last;
        names.add(base.substring(0, base.length - 5));
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static Future<bool> exists(String name) => _file(name).exists();

  static Future<LabelTemplate> load(String name) async {
    final j =
        jsonDecode(await _file(name).readAsString()) as Map<String, dynamic>;
    var id = 1;
    return LabelTemplate(
      name,
      (j['width'] as num).toDouble(),
      (j['height'] as num).toDouble(),
      [
        for (final e in (j['elements'] as List))
          LabelElement.fromJson(id++, e as Map<String, dynamic>),
      ],
    );
  }

  static Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }
}
