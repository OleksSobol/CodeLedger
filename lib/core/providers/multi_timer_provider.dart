import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme_provider.dart';

const _kMultiTimer = 'multi_timer_enabled';

class MultiTimerNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final dao = ref.watch(appSettingsDaoProvider);
    return (await dao.getValue(_kMultiTimer)) == 'true';
  }

  Future<void> setEnabled(bool v) async {
    await ref.read(appSettingsDaoProvider).setValue(_kMultiTimer, v.toString());
    state = AsyncData(v);
  }
}

final multiTimerProvider =
    AsyncNotifierProvider<MultiTimerNotifier, bool>(MultiTimerNotifier.new);
