import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/landing_route_provider.dart';

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

    // One-shot redirect on cold start to the user's preferred landing route.
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
