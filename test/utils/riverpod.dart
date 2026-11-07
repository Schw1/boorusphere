import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show ProviderListenable;

extension ProviderContainerExt on ProviderContainer {
  void setupTestFor<T>(ProviderListenable<T> provider) {
    listen(provider, (previous, value) {}, fireImmediately: true);
  }
}
