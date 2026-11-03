import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'editor_page.dart';

/// Mica работает только на Windows 11 (сборка 22000+). На Windows 10 —
/// обычный сплошной фон.
bool micaEnabled = false;

bool _isWindows11() {
  final m = RegExp(r'Build (\d+)').firstMatch(Platform.operatingSystemVersion);
  final build = int.tryParse(m?.group(1) ?? '') ?? 0;
  return build >= 22000;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await SystemTheme.accentColor.load();
    try {
      await acrylic.Window.initialize();
      micaEnabled = _isWindows11();
    } catch (_) {
      micaEnabled = false;
    }
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1280, 800),
        minimumSize: const Size(1040, 640),
        center: true,
        title: 'Печать стикеров',
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Colors.transparent,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.setPreventClose(true);
  }

  runApp(const BarcodeApp());
}

class BarcodeApp extends StatelessWidget {
  const BarcodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Platform.isWindows
        ? SystemTheme.accentColor.accent.toAccentColor()
        : Colors.blue;
    final transparent = micaEnabled ? Colors.transparent : null;

    return FluentApp(
      title: 'Печать стикеров',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      color: accent,
      theme: FluentThemeData(
        brightness: Brightness.light,
        accentColor: accent,
        scaffoldBackgroundColor: transparent,
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: accent,
        scaffoldBackgroundColor: transparent,
        visualDensity: VisualDensity.standard,
      ),
      builder: (context, child) => _MicaSync(child: child!),
      home: const EditorPage(),
    );
  }
}

/// Подстраивает материал окна (Mica) под текущую тему Windows.
class _MicaSync extends StatefulWidget {
  const _MicaSync({required this.child});
  final Widget child;

  @override
  State<_MicaSync> createState() => _MicaSyncState();
}

class _MicaSyncState extends State<_MicaSync> {
  Brightness? _applied;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = FluentTheme.of(context).brightness;
    if (micaEnabled && b != _applied) {
      _applied = b;
      acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.mica,
        dark: b == Brightness.dark,
      ).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
