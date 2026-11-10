import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// Servers pinned to the menu (by id); the others are in its "All servers"
/// list. Kept on this device in a Hive box.
class ServerPins {
  ServerPins(this._pins)
    : pinned = ValueNotifier({
        for (final key in _pins.keys)
          if (key is String && (_pins.get(key) ?? false)) key,
      });

  /// The store on the box opened by [openBox].
  factory ServerPins.fromOpenBox() => ServerPins(Hive.box<bool>(boxName));

  static const boxName = 'server_pins';

  final Box<bool> _pins;

  /// Pinned ids; changes update the menu.
  final ValueNotifier<Set<String>> pinned;

  /// Opens the box; call once at startup, before [fromOpenBox].
  static Future<void> openBox() => Hive.openBox<bool>(boxName);

  Future<Box<bool>> _box() async => _pins;

  /// Backup entry (`server_pins.json`), with the server list.
  static const backupKey = 'server_pins';

  List<String> export() => pinned.value.toList()..sort();

  /// Restores [export]ed pins (added to the ones here).
  Future<void> import(Object? data) async {
    if (data is! List) return;
    final box = await _box();
    final ids = {
      for (final id in data)
        if (id is String && id.isNotEmpty) id,
    };
    for (final id in ids) {
      await box.put(id, true);
    }
    pinned.value = {...pinned.value, ...ids};
  }

  bool isPinned(String id) => pinned.value.contains(id);

  Future<void> toggle(String id) async {
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
