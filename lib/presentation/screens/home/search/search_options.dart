part of 'search_bar.dart';

// Option buttons under the search field: sort, language, random, rating.

/// Sort order of the current server, from what its engine supports (see
/// Server.sortOptions). Random order or an `order:`/`sort:` tag in the
/// search take precedence.
class _SortButton extends ConsumerWidget {
  const _SortButton({required this.server});

  final Server server;

  static String describe(BuildContext context, String sort) {
    final t = context.t.sortOrder;
    return switch (sort) {
      'popular-today' => t.today,
      'popular-week' => t.week,
      'popular-month' => t.month,
      'popular' => t.allTime,
      'rank' => t.rank,
      'score' => t.score,
      'favcount' => t.favorites,
      'oldest' => t.oldest,
      'size' => t.size,
      _ => t.recent,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(
      serverSettingStateProvider.select(
        (it) => it.searchSorts[server.id] ?? '',
      ),
    );
    final options = server.sortOptions;
    final sort = options.contains(stored) ? stored : '';
    final t = context.t.sortOrder;
    final label = '${t.label}: ${describe(context, sort)}';

    return TextButton.icon(
      onPressed: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.label),
            icon: const Icon(Icons.sort),
            contentPadding: const EdgeInsets.only(top: 16, bottom: 16),
            content: RadioGroup(
              groupValue: sort,
              onChanged: (x) => context.navigator.pop(x),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    RadioListTile<String>(
                      value: option,
                      title: Text(describe(context, option)),
                    ),
                ],
              ),
            ),
          ),
        );
        if (selected != null) {
          await ref
              .read(serverSettingStateProvider.notifier)
              .setSort(server.id, selected);
        }
      },
      icon: Icon(
        Icons.sort,
        size: 16,
        color: sort.isNotEmpty
            ? context.colorScheme.primary
            : context.colorScheme.onSurface,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        minimumSize: const Size(1, 1),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          width: 1,
          color: sort.isNotEmpty
              ? context.colorScheme.primary
              : context.colorScheme.surfaceContainerHighest,
        ),
        elevation: 0,
      ),
      label: Text(
        label.toLowerCase(),
        style: TextStyle(color: context.colorScheme.onSurface),
      ),
    );
  }
}

/// nhentai only: show galleries of one language. A `language:` tag in the
/// search takes precedence.
class _LanguageButton extends ConsumerWidget {
  const _LanguageButton({required this.server});

  final Server server;

  static String describe(BuildContext context, String language) {
    final t = context.t.languageFilter;
    return switch (language) {
      'english' => t.english,
      'japanese' => t.japanese,
      'chinese' => t.chinese,
      _ => t.all,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(
      serverSettingStateProvider.select(
        (it) => it.searchLanguages[server.id] ?? '',
      ),
    );
    final t = context.t.languageFilter;
    final active = language.isNotEmpty;

    return TextButton.icon(
      onPressed: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.label),
            icon: const Icon(Icons.translate),
            contentPadding: const EdgeInsets.only(top: 16, bottom: 16),
            content: RadioGroup(
              groupValue: language,
              onChanged: (x) => context.navigator.pop(x),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in NhentaiJsonParser.languages)
                    RadioListTile<String>(
                      value: option,
                      title: Text(describe(context, option)),
                    ),
                ],
              ),
            ),
          ),
        );
        if (selected != null) {
          await ref
              .read(serverSettingStateProvider.notifier)
              .setLanguage(server.id, selected);
        }
      },
      icon: Icon(
        Icons.translate,
        size: 16,
        color: active
            ? context.colorScheme.primary
            : context.colorScheme.onSurface,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        minimumSize: const Size(1, 1),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          width: 1,
          color: active
              ? context.colorScheme.primary
              : context.colorScheme.surfaceContainerHighest,
        ),
        elevation: 0,
      ),
      label: Text(
        '${t.label}: ${describe(context, language)}'.toLowerCase(),
        style: TextStyle(color: context.colorScheme.onSurface),
      ),
    );
  }
}

class _RandomButton extends ConsumerWidget {
  const _RandomButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final random = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRandom),
    );
    final t = context.t.randomOrder;
    final label = '${t.label}: ${random ? t.on : t.off}';

    return TextButton.icon(
      onPressed: () =>
          ref.read(serverSettingStateProvider.notifier).setRandom(!random),
      icon: Icon(
        Icons.shuffle_rounded,
        size: 16,
        color: random
            ? context.colorScheme.primary
            : context.colorScheme.onSurface,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        minimumSize: const Size(1, 1),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          width: 1,
          color: random
              ? context.colorScheme.primary
              : context.colorScheme.surfaceContainerHighest,
        ),
        elevation: 0,
      ),
      label: Text(
        label.toLowerCase(),
        style: TextStyle(color: context.colorScheme.onSurface),
      ),
    );
  }
}

class _RatingButton extends ConsumerWidget {
  const _RatingButton();

  String rateDesc(BuildContext context, BooruRating rating) {
    final desc = rating.describe(context);
    return desc.isEmpty ? context.t.rating.all : desc;
  }

  Future<BooruRating?> selectRating(BuildContext context, BooruRating current) {
    return showDialog<BooruRating>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.t.rating.title),
          icon: const Icon(Icons.star),
          contentPadding: const EdgeInsets.only(top: 16, bottom: 16),
          content: RadioGroup(
            groupValue: current,
            onChanged: (x) => context.navigator.pop(x),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: BooruRating.values
                  .map(
                    (e) => RadioListTile(
                      value: e,
                      title: Text(rateDesc(context, e)),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRating),
    );
    final label = '${context.t.rating.title}: ${rateDesc(context, rating)}';

    return TextButton(
      onPressed: () async {
        final selected = await selectRating(context, rating);
        if (selected != null) {
          await ref
              .read(serverSettingStateProvider.notifier)
              .setRating(selected);
        }
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        minimumSize: const Size(1, 1),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          width: 1,
          color: context.colorScheme.surfaceContainerHighest,
        ),
        elevation: 0,
      ),
      child: Text(
        label.toLowerCase(),
        style: TextStyle(color: context.colorScheme.onSurface),
      ),
    );
  }
}
