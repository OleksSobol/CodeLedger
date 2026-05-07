import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme_provider.dart';

const _landingRouteKey = 'default_landing_route';
const String defaultLandingRoute = '/';

const landingRouteOptions = <({String value, String label})>[
  (value: '/', label: 'Dashboard'),
  (value: '/time-tracking', label: 'Time Tracking'),
  (value: '/invoices', label: 'Invoices'),
  (value: '/invoices/send', label: 'Send Invoices'),
];

bool isValidLandingRoute(String? route) =>
    route != null && landingRouteOptions.any((o) => o.value == route);

/// Persisted route to navigate to on app start.
final landingRouteProvider =
    AsyncNotifierProvider<LandingRouteNotifier, String>(
        LandingRouteNotifier.new);

class LandingRouteNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final dao = ref.watch(appSettingsDaoProvider);
    final value = await dao.getValue(_landingRouteKey);
    return isValidLandingRoute(value) ? value! : defaultLandingRoute;
  }

  Future<void> setRoute(String route) async {
    if (!isValidLandingRoute(route)) return;
    final dao = ref.read(appSettingsDaoProvider);
    await dao.setValue(_landingRouteKey, route);
    state = AsyncData(route);
  }
}
