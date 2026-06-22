import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/root_screen.dart';
import 'core/services/database_service.dart';
import 'core/services/widget_service.dart';
import 'core/services/config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await initializeDateFormatting('ro_RO', null);
  await Hive.initFlutter();
  await DatabaseService().initialize();
  await WidgetService().initialize();
  await WidgetService().updateWidget();

  // Încarcă tema salvată (persistă între porniri, până o schimbă utilizatorul).
  final savedTheme = await ConfigService().theme;
  themeNotifier.value = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;

  runApp(const MyApp());
}

/// Cheie globală de navigare — folosită pentru a deschide panourile
/// (task-uri / cumpărături) când se apasă pe widget-ul din ecranul principal.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// „Context" global al temei aplicației. `MaterialApp` ascultă acest notifier,
/// deci schimbarea lui re-temă instant întreaga aplicație (chat + voce).
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(
  ThemeMode.light,
);

/// Schimbă tema aplicației ȘI o salvează (persistă până e schimbată din nou).
Future<void> setAppTheme(bool dark) async {
  themeNotifier.value = dark ? ThemeMode.dark : ThemeMode.light;
  await ConfigService().setTheme(dark ? 'dark' : 'light');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'ASIS - Asistent Personal',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          primarySwatch: Colors.indigo,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.indigo,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        home: const RootScreen(),
      ),
    );
  }
}
