import 'package:boorusphere/domain/provider.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fullscreen_state.g.dart';

@riverpod
class FullscreenState extends _$FullscreenState {
  List<DeviceOrientation> _lastOrientations = [];
  int _sdkVersion = 0;

  @override
  bool build() {
    // Read here: Riverpod 3 forbids using ref inside onDispose (see reset).
    _sdkVersion = ref.read(envRepoProvider).sdkVersion;
    ref.onDispose(reset);
    _lastOrientations = [];
    return false;
  }

  Future<void> toggle({bool shouldLandscape = false}) async {
    state = !state;
    final orientations = state && shouldLandscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : <DeviceOrientation>[];

    if (orientations != _lastOrientations) {
      _lastOrientations = orientations;
      await SystemChrome.setPreferredOrientations(orientations);
    }

    state
        ? await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive)
        : await unfullscreen();
  }

  Future<void> unfullscreen() async {
    if (_sdkVersion < 29) {
      // SDK 28 and below ignores edgeToEdge, so we have to manually reenable them
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [
        SystemUiOverlay.top,
        SystemUiOverlay.bottom,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void reset() {
    SystemChrome.setPreferredOrientations([]);
    unfullscreen();
  }
}
