import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/task_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfi;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rosa como cor principal
    const shockPink = Color(0xFFFF007F);

    final lightTheme = ThemeData(
      colorScheme: ColorScheme.light(
        primary: shockPink,
        secondary: shockPink,
        background: Colors.white,
        surface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: Colors.black,
        onSurface: Colors.black,
        error: Colors.redAccent,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: shockPink,
        foregroundColor: Colors.white,
        elevation: 2,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: shockPink,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 6,
        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        shadowColor: shockPink.withOpacity(0.15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shockPink.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shockPink.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shockPink, width: 2),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: shockPink,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: shockPink,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );

    final darkTheme = ThemeData(
      colorScheme: ColorScheme.dark(
        primary: shockPink,
        secondary: shockPink,
        background: Colors.black,
        surface: Colors.grey[900]!,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: Colors.white,
        onSurface: Colors.white,
        error: Colors.redAccent,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: shockPink,
        foregroundColor: Colors.white,
        elevation: 2,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: shockPink,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      cardTheme: CardThemeData(
        color: Colors.grey[900],
        elevation: 6,
        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        shadowColor: shockPink.withOpacity(0.15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[900],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shockPink.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shockPink.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shockPink, width: 2),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: shockPink,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: shockPink,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TaskProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Task Manager Offline-First',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeProvider.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
