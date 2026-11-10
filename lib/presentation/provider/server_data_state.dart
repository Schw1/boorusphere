import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_data_state.g.dart';

@Riverpod(keepAlive: true)
class ServerState extends _$ServerState {
  @override
  Iterable<Server> build() {
    // populate later
    return [];
  }

  ServerSettingState get settings =>
      ref.read(serverSettingStateProvider.notifier);

  Future<void> populate() async {
    final serverSetting = ref.read(serverSettingStateProvider);
    final repo = ref.read(serverRepoProvider);
    await repo.populate();
    state = repo.servers;
    await ServerAuthStore.load(state);

    if (state.isNotEmpty && serverSetting.lastActiveId.isEmpty) {
      final server = state.firstWhere(
        (it) => it.id.startsWith('Safe'),
        orElse: () => state.first,
      );
      await settings.setLastActiveId(server.id);
    }
  }

  Future<void> add(Server data) async {
    final repo = ref.read(serverRepoProvider);
    await repo.add(data);
    state = repo.servers;
  }

  Future<void> remove(Server data) async {
    if (state.length == 1) {
      throw Exception('Last server cannot be deleted');
    }

    final repo = ref.read(serverRepoProvider);
    await repo.remove(data);
    state = repo.servers;
    await ServerAuthStore.remove(data.id);
  }

  Future<void> edit(Server from, Server to) async {
    final repo = ref.read(serverRepoProvider);
    await repo.edit(from, to);
    state = repo.servers;
  }

  Future<void> reset() async {
    final repo = ref.read(serverRepoProvider);
    await repo.reset();
    state = repo.servers;
    await settings.setLastActiveId(state.first.id);
  }
}

extension ServerDataListExt on Iterable<Server> {
  /// Like [getById] but without falling back to another server.
  Server? findById(String id) {
    for (final it in this) {
      if (it.id == id) return it;
    }
    return null;
  }

  Server getById(String id, {Server? or}) {
    return isEmpty
        ? Server.empty
        : firstWhere((it) => it.id == id, orElse: () => or ?? first);
  }
}
