import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/landing_route_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/sync_service_provider.dart';
import 'features/auth/presentation/pages/login_page.dart';

class CodeLedgerApp extends ConsumerStatefulWidget {
  const CodeLedgerApp({super.key});

  @override
  ConsumerState<CodeLedgerApp> createState() => _CodeLedgerAppState();
}

class _CodeLedgerAppState extends ConsumerState<CodeLedgerApp> {
  bool _appliedLandingRoute = false;

  @override
  Widget build(BuildContext context) {
    final themeModeAsync = ref.watch(themeModeProvider);
    final themeMode = themeModeAsync.value ?? ThemeMode.system;
    ref.watch(autoSyncProvider);

    if (kIsWeb) {
      final authAsync = ref.watch(authProvider);
      return authAsync.when(
        loading: () => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        error: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: const LoginPage(),
        ),
        data: (session) => session == null
            ? MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                home: const LoginPage(),
              )
            : _buildMainApp(themeMode),
      );
    }

    return _buildMainApp(themeMode);
  }

  Widget _buildMainApp(ThemeMode themeMode) {
    final landingAsync = ref.watch(landingRouteProvider);
    if (!_appliedLandingRoute) {
      landingAsync.whenData((route) {
        if (_appliedLandingRoute) return;
        _appliedLandingRoute = true;
        if (route != defaultLandingRoute) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            appRouter.go(route);
          });
        }
      });
    }

    return MaterialApp.router(
      title: 'CodeLedger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en')],
    );
  }
}
