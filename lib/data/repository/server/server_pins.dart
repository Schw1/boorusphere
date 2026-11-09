import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// Servers pinned to the menu (by id); the others are in its "All servers"
/// list. Kept on this device in a Hive box.
class ServerPins {
  ServerPins._();

  static const boxName = 'server_pins';

  /// Pinned ids; changes update the menu.
  static final pinned = ValueNotifier<Set<String>>(const {});

  static Future<Box<bool>> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box<bool>(boxName)
      : await Hive.openBox<bool>(boxName);

  static Future<void> open() async {
    final box = await _box();
    pinned.value = {
      for (final key in box.keys)
        if (key is String && box.get(key) == true) key,
    };
  }

  static bool isPinned(String id) => pinned.value.contains(id);

  static Future<void> toggle(String id) async {
    final box = await _box();
    if (isPinned(id)) {
      await box.delete(id);
      pinned.value = {...pinned.value}..remove(id);
    } else {
      await box.put(id, true);
      pinned.value = {...pinned.value, id};
    }
  }
}
