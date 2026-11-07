import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/data_backup/auto_backup.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_result.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

@RoutePage()
class DataBackupPage extends StatelessWidget {
  const DataBackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.dataBackup.title)),
      body: const SafeArea(child: _Content()),
    );
  }
}

class _Content extends HookConsumerWidget {
  const _Content();

  Future<bool?> _warningDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.t.dataBackup.restore.title),
          icon: const Icon(Icons.restore),
          content: Text(context.t.dataBackup.restore.warning),
          actions: [
            TextButton(
              onPressed: () {
                context.navigator.pop(false);
              },
              child: Text(context.t.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                context.navigator.pop(true);
              },
              child: Text(context.t.restore),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const subtitlePadding = EdgeInsets.only(top: 8);
    ref.listen<BackupResult?>(dataBackupStateProvider, (prev, next) {
      switch (next) {
        case LoadingBackupResult(:final type):
          showDialog(
            context: context,
            builder: (_) => UncontrolledProviderScope(
              container: ProviderScope.containerOf(context),
              child: _LoadingDialog(type: type),
            ),
          );
        case ImportedBackupResult():
          context.scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(context.t.dataBackup.restore.success),
            duration: const Duration(seconds: 1),
          ));
        case ExportedBackupResult(:final path):
          context.scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(context.t.dataBackup.backup.success(dest: path)),
            duration: const Duration(seconds: 2),
          ));
        case ErrorBackupResult():
          context.scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(context.t.dataBackup.restore.invalid),
            duration: const Duration(seconds: 1),
          ));
        default:
      }
    });

    return ListView(
      children: [
        ListTile(
          title: Text(context.t.dataBackup.backup.title),
          subtitle: Padding(
            padding: subtitlePadding,
            child: Text(context.t.dataBackup.backup.desc),
          ),
          onTap: () async {
            final result = await showDialog<BackupOption?>(
              context: context,
              builder: (context) => _BackupSelectionDialog(),
            );
            if (result != null) {
              unawaited(ref
                  .read(dataBackupStateProvider.notifier)
                  .backup(option: result));
            }
          },
        ),
        ListTile(
          title: Text(context.t.dataBackup.restore.title),
          subtitle: Padding(
            padding: subtitlePadding,
            child: Text(context.t.dataBackup.restore.desc),
          ),
          onTap: () {
            ref
                .read(dataBackupStateProvider.notifier)
                .restore(onConfirm: () => _warningDialog(context));
          },
        ),
        const Divider(),
        const _AutoBackupSection(),
      ],
    );
  }
}

class _AutoBackupSection extends HookConsumerWidget {
  const _AutoBackupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(autoBackupProvider);
    // AutoBackup reads its values from the settings box; bump to rebuild.
    final revision = useState(0);
    void refresh() => revision.value++;
    final t = context.t.dataBackup.auto;
    final last = auto.lastRun;
    final lastText = last == null
        ? t.never
        : t.last(time: DateFormat.yMd().add_Hm().format(last));

    return Column(
      children: [
        SwitchListTile(
          title: Text(t.title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${t.desc}\n$lastText'),
          ),
          value: auto.enabled,
          onChanged: (value) async {
            await auto.setEnabled(value);
            refresh();
          },
        ),
        if (auto.enabled) ...[
          ListTile(
            title: Text(t.interval),
            trailing: DropdownButton<AutoBackupInterval>(
              value: auto.interval,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                    value: AutoBackupInterval.daily, child: Text(t.daily)),
                DropdownMenuItem(
                    value: AutoBackupInterval.weekly, child: Text(t.weekly)),
              ],
              onChanged: (value) async {
                if (value == null) return;
                await auto.setInterval(value);
                refresh();
              },
            ),
          ),
          ListTile(
            title: Text(t.keep),
            trailing: DropdownButton<int>(
              value: AutoBackup.keepOptions.contains(auto.keep)
                  ? auto.keep
                  : 3,
              underline: const SizedBox.shrink(),
              items: AutoBackup.keepOptions
                  .map((n) => DropdownMenuItem(
                      value: n, child: Text(t.keepValue(count: '$n'))))
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await auto.setKeep(value);
                refresh();
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _LoadingDialog extends HookConsumerWidget {
  const _LoadingDialog({required this.type});

  final DataBackupType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(dataBackupStateProvider, (previous, next) {
      if (next is! LoadingBackupResult) {
        context.navigator.pop();
      }
    });
    return Dialog(
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
          Text(
            type == DataBackupType.backup
                ? context.t.dataBackup.backup.loading
                : context.t.dataBackup.restore.loading,
          ),
        ],
      ),
    );
  }
}

class _BackupSelectionDialog extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final option = useState(const BackupOption());
    return AlertDialog(
      title: Text(context.t.dataBackup.backup.title),
      icon: const Icon(Icons.restore),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: Text(context.t.servers.title),
              value: option.value.server,
              onChanged: (newValue) {
                option.value = option.value.copyWith(server: newValue ?? true);
              },
            ),
            // API keys in the servers' URL suffix; off by default because they
            // would end up in plain text in the backup file.
            CheckboxListTile(
              contentPadding: const EdgeInsets.only(left: 40, right: 24),
              title: Text(context.t.dataBackup.backup.credentials.title),
              subtitle: Text(
                option.value.credentials
                    ? context.t.dataBackup.backup.credentials.warning
                    : context.t.dataBackup.backup.credentials.desc,
                style: option.value.credentials
                    ? TextStyle(color: context.colorScheme.error)
                    : null,
              ),
              value: option.value.server && option.value.credentials,
              onChanged: option.value.server
                  ? (newValue) {
                      option.value = option.value
                          .copyWith(credentials: newValue ?? false);
                    }
                  : null,
            ),
            CheckboxListTile(
              title: Text(context.t.searchHistory),
              value: option.value.searchHistory,
              onChanged: (newValue) {
                option.value =
                    option.value.copyWith(searchHistory: newValue ?? true);
              },
            ),
            CheckboxListTile(
              title: Text(context.t.tagsBlocker.title),
              value: option.value.blockedTags,
              onChanged: (newValue) {
                option.value =
                    option.value.copyWith(blockedTags: newValue ?? true);
              },
            ),
            CheckboxListTile(
              title: Text(context.t.favorites.title),
              value: option.value.favoritePost,
              onChanged: (newValue) {
                option.value =
                    option.value.copyWith(favoritePost: newValue ?? true);
              },
            ),
            CheckboxListTile(
              title: Text(context.t.settings.title),
              value: option.value.setting,
              onChanged: (newValue) {
                option.value = option.value.copyWith(setting: newValue ?? true);
              },
            ),
            CheckboxListTile(
              title: Text(context.t.monbooru.backup.title),
              subtitle: Text(context.t.monbooru.backup.desc),
              value: option.value.monloader,
              onChanged: (newValue) {
                option.value =
                    option.value.copyWith(monloader: newValue ?? true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            context.navigator.pop();
          },
          child: Text(context.t.cancel),
        ),
        ElevatedButton(
          onPressed: option.value.isValid()
              ? () {
                  final result = option.value.copyWith(
                      credentials:
                          option.value.server && option.value.credentials);
                  context.navigator.pop(result);
                }
              : null,
          child: Text(context.t.backup),
        )
      ],
    );
  }
}
