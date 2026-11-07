import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

abstract interface class ServerRepo {
  Iterable<Server> get servers;
  Map<String, Server> get defaults;
  Future<void> populate();
  Future<void> add(Server data);
  Future<Server> edit(Server from, Server to);
  Future<void> remove(Server data);
  Future<void> reset();
  Future<void> import(String src);
  /// Without [withCredentials], credential parameters are removed from the
  /// servers' URL suffix (see UrlSuffixCredentials).
  Future<BackupItem> export({bool withCredentials = true});
}
