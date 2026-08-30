import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/services/local_streaming_server.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/course_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/bookmark_provider.dart';
import 'providers/download_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/widgets/app_layout_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preload saved theme synchronously before runApp to prevent any blue/white flash
  ThemeMode initialThemeMode = ThemeMode.light;
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(AppConstants.keyThemeMode);
    if (savedMode == 'dark') {
      initialThemeMode = ThemeMode.dark;
    } else {
      initialThemeMode = ThemeMode.light;
    }
  } catch (_) {}

  // Set default preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Start embedded local streaming HTTP proxy for Range requests
  await LocalStreamingServer.instance.start();

  runApp(TeleLearnApp(initialThemeMode: initialThemeMode));
}

class TeleLearnApp extends StatelessWidget {
  final ThemeMode initialThemeMode;

  const TeleLearnApp({super.key, this.initialThemeMode = ThemeMode.light});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(initialMode: initialThemeMode)),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CourseProvider()),
        ChangeNotifierProvider(create: (_) => ProgressProvider()),
        ChangeNotifierProvider(create: (_) => BookmarkProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()),
      ],
      child: Consumer2<ThemeProvider, AuthProvider>(
        builder: (context, themeProvider, authProvider, _) {
          return MaterialApp(
            title: 'TeleLearn',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: authProvider.isLoading
                ? const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                : (authProvider.isLoggedIn
                    ? const AppLayoutScaffold()
                    : const LoginScreen()),
          );
        },
      ),
    );
  }
}
