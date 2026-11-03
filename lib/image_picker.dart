import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Выбор файла изображения.
///
/// На Windows системное окно «Открыть файл» показывает отдельный процесс
/// PowerShell. Если проводник на компьютере подвисает (недоступный сетевой диск,
/// медленное расширение, антивирус), зависает только этот процесс, а сама
/// программа остаётся живой. Через плагин окно открывалось бы в главном потоке
/// и замораживало всё приложение.
class ImagePicker {
  Process? _process;

  /// Окно выбора сейчас открыто (или пытается открыться).
  bool get busy => _process != null;

  /// Закрыть окно выбора, если оно ещё висит.
  void cancel() {
    _process?.kill();
    _process = null;
  }

  static const _script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Windows.Forms.Application]::EnableVisualStyles()
$owner = New-Object System.Windows.Forms.Form
$owner.FormBorderStyle = 'None'
$owner.Opacity = 0
$owner.TopMost = $true
$owner.ShowInTaskbar = $false
$owner.StartPosition = 'CenterScreen'
$owner.Size = New-Object System.Drawing.Size(1, 1)
$owner.Show()
$owner.Activate()
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Title = 'Выберите изображение'
$d.Filter = 'Изображения|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|Все файлы|*.*'
$d.InitialDirectory = [Environment]::GetFolderPath('MyPictures')
if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::Out.Write($d.FileName)
}
$owner.Close()
''';

  /// Возвращает путь к файлу или null, если пользователь отменил выбор.
  /// Бросает исключение, если окно выбора не удалось запустить.
  Future<String?> pickImagePath() async {
    if (!Platform.isWindows) {
      final f = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Изображения',
            extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
          ),
        ],
      );
      return f?.path;
    }

    // -EncodedCommand: UTF-16LE в base64, чтобы кириллица и кавычки не ломались.
    final units = _script.codeUnits;
    final bytes = <int>[
      for (final u in units) ...[u & 0xFF, u >> 8],
    ];
    final process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-WindowStyle',
      'Hidden',
      '-EncodedCommand',
      base64Encode(bytes),
    ]);
    _process = process;
    try {
      final stderr = process.stderr.transform(utf8.decoder).join();
      final out = await process.stdout.transform(utf8.decoder).join();
      final code = await process.exitCode;
      if (!identical(_process, process)) return null; // отменено
      final path = out.replaceAll('\uFEFF', '').trim();
      if (code != 0 && path.isEmpty) {
        throw 'PowerShell завершился с ошибкой: ${(await stderr).trim()}';
      }
      return path.isEmpty ? null : path;
    } finally {
      if (identical(_process, process)) _process = null;
    }
  }
}
