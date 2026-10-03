import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'store.dart';
import 'workspace.dart';
import 'design.dart';
import 'showcase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = GritStore();
  final preview = Uri.base.queryParameters['preview'] == 'true';
  await s.init(enableCloud: !preview);
  if (preview) {
    s.prefs = null;
    s.cloud = false;
    s.previewMode = true;
    s.name = 'Alex';
    loadShowcase(s);
    // Review first-run surfaces without replacing a real local workspace.
    final review = Uri.base.queryParameters['screen'];
    if (review == 'welcome') {
      s.onboarded = false;
      s.name = '';
    }
    if (review == 'empty' || review == 'welcome') {
      s.tasks.clear();
      s.events.clear();
      s.activity.clear();
    }
  }
  runApp(GritApp(store: s));
}

class GritApp extends StatelessWidget {
  const GritApp({super.key, required this.store});
  final GritStore store;
  ThemeData theme(bool dark) {
    final text = dark ? const Color(0xFFECECE7) : ink;
    return ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS
            ? '.SF UI Text'
            : null,
        scaffoldBackgroundColor: dark
            ? store.oledBlack
                ? Colors.black
                : const Color(0xFF1C1C1E)
            : const Color(0xFFF8F8FA),
        colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: dark ? Brightness.dark : Brightness.light,
            primary: dark ? const Color(0xFFEC9685) : accent,
            surface: dark
                ? store.oledBlack
                    ? const Color(0xFF121214)
                    : const Color(0xFF242426)
                : Colors.white),
        cupertinoOverrideTheme: CupertinoThemeData(
            primaryColor: dark ? const Color(0xFFEC9685) : accent,
            brightness: dark ? Brightness.dark : Brightness.light),
        dividerColor: dark ? const Color(0xFF383837) : const Color(0xFFEDEDE9),
        textTheme: TextTheme(
            bodyMedium: TextStyle(color: text, fontSize: 17, height: 1.35),
            bodyLarge: TextStyle(color: text, fontSize: 17, height: 1.35),
            headlineLarge: TextStyle(
                color: text,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2),
            titleLarge: TextStyle(
                color: text,
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5)),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: dark ? const Color(0xFF282827) : const Color(0xFFF7F7F5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none)),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)))),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
                foregroundColor: dark ? const Color(0xFFEC9685) : accent)),
        dialogTheme: DialogThemeData(
            backgroundColor: dark ? const Color(0xFF20201F) : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22))),
        snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                dark ? const Color(0xFFEEEEEA) : const Color(0xFF333430),
            contentTextStyle: TextStyle(color: dark ? ink : Colors.white)),
        tooltipTheme: TooltipThemeData(
            decoration: BoxDecoration(
                color: ink, borderRadius: BorderRadius.circular(7))));
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
      listenable: store,
      builder: (c, _) => MaterialApp(
          title: 'GRIT · A little more clarity',
          debugShowCheckedModeBanner: false,
          theme: theme(false),
          darkTheme: theme(true),
          themeMode: store.appearance == 'System'
              ? ThemeMode.system
              : store.appearance == 'Dark'
                  ? ThemeMode.dark
                  : ThemeMode.light,
          home: store.onboarded
              ? Workspace(store: store)
              : Welcome(store: store)));
}

class Welcome extends StatefulWidget {
  const Welcome({super.key, required this.store});
  final GritStore store;
  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  final name = TextEditingController();
  double capacity = 240;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const GritMark(),
                            const SizedBox(height: 48),
                            const QuietIllustration(size: 110),
                            const SizedBox(height: 25),
                            const Text('Make time for\nwhat matters.',
                                style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.6,
                                    height: 1.13)),
                            const SizedBox(height: 18),
                            Text(
                                'Make a home for your plans, projects, and everyday life. Start small. Find your rhythm.',
                                style: TextStyle(
                                    color: secondary(c), fontSize: 16)),
                            const SizedBox(height: 30),
                            TextField(
                                controller: name,
                                decoration: const InputDecoration(
                                    labelText: 'Your first name',
                                    helperText:
                                        'Optional. Make this space yours.')),
                            const SizedBox(height: 20),
                            Text(
                                'Time for yourself · ${capacity ~/ 60}h ${capacity.toInt() % 60}m',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            CupertinoSlider(
                                value: capacity,
                                min: 30,
                                max: 480,
                                divisions: 15,
                                onChanged: (v) => setState(() => capacity = v)),
                            Text(
                                'A gentle planning limit, not a target. Change it anytime in Settings.',
                                style: TextStyle(
                                    color: secondary(c),
                                    fontSize: 14,
                                    height: 1.5)),
                            const SizedBox(height: 20),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                    onPressed: () {
                                      widget.store.name =
                                          name.text.trim().isEmpty
                                              ? 'Friend'
                                              : name.text.trim();
                                      widget.store.capacity = capacity.toInt();
                                      widget.store.onboarded = true;
                                      widget.store.save();
                                    },
                                    child: const Text('Create my space  →'))),
                            const SizedBox(height: 8),
                            Center(
                                child: TextButton(
                                    onPressed: () {
                                      widget.store.name =
                                          name.text.trim().isEmpty
                                              ? 'Alex'
                                              : name.text.trim();
                                      widget.store.capacity = capacity.toInt();
                                      loadShowcase(widget.store);
                                    },
                                    child: const Text(
                                        'Explore a sample workspace'))),
                            const SizedBox(height: 24),
                            Center(
                                child: Text(
                                    'Start without an account. Your plans stay on this device; backups help you keep them safe.',
                                    style: TextStyle(
                                        color: secondary(c), fontSize: 13),
                                    textAlign: TextAlign.center))
                          ]))))));
}
