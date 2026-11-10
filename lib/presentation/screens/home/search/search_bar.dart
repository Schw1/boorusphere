import 'package:boorusphere/data/repository/booru/parser/nhentai_json_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/home/drawer/home_drawer_controller.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/blur_backdrop.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeSearchBar extends HookConsumerWidget {
  const HomeSearchBar({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchBar = ref.watch(searchBarControllerProvider);
    final delta = useState([0.0, 0.0]);
    final collapsed = !searchBar.isOpen && delta.value.first > 0;
    final isBlurAllowed = ref.watch(
      uiSettingStateProvider.select((ui) => ui.blur),
    );
    final onScrolling = useCallback(() {
      final position = scrollController.position;
      final threshold = innerHeight;
      if (delta.value.first > 0 &&
          position.viewportDimension > position.maxScrollExtent) {
        // reset back to default (!collapsed) because there's nothing to scroll
        delta.value = [0, 0];
        return;
      }

      if (position.extentBefore < threshold ||
          position.extentAfter < threshold) {
        // we're already at the edge of the scrollable content
        // there's no need to change the collapsed state
        return;
      }

      final current = position.pixels;
      final offset = (delta.value.first + current - delta.value.last);
      final boundary = offset.clamp(-threshold, threshold);
      delta.value = [boundary, current];
    }, []);

    useEffect(() {
      scrollController.addListener(onScrolling);
      return () {
        scrollController.removeListener(onScrolling);
      };
    }, []);

    // Reset delta when there's no scrollable widget attached.
    // for example: on new search or while switching server.
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (scrollController.hasClients) return;
      if (delta.value.reduce((a, b) => a + b) != 0) {
        delta.value = [0, 0];
      }
    });

    return RepaintBoundary(
      child: BlurBackdrop(
        sigmaX: 8,
        sigmaY: 8,
        blur: isBlurAllowed,
        child: Container(
          decoration: BoxDecoration(
            color: context.theme.scaffoldBackgroundColor.withValues(
              alpha: context.isLightThemed
                  ? isBlurAllowed
                        ? 0.7
                        : 0.92
                  : isBlurAllowed
                  ? 0.85
                  : 0.97,
            ),
            border: Border(
              top: BorderSide(color: context.colorScheme.outlineVariant),
            ),
          ),
          child: SafeArea(
            top: false,
            maintainBottomViewPadding: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (searchBar.isOpen) const _OptionBar(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: collapsed ? 0 : 0.2),
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                  margin: collapsed
                      ? const EdgeInsets.fromLTRB(32, 4, 32, 0)
                      : const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          _LeadingButton(collapsed: collapsed),
                          if (!searchBar.isOpen)
                            Positioned(right: 8, child: _RatingIndicator()),
                        ],
                      ),
                      const Expanded(child: _SearchField()),
                      if (!searchBar.isOpen)
                        _TrailingButton(
                          collapsed: collapsed,
                          scrollController: scrollController,
                        ),
                      if (searchBar.isOpen &&
                          searchBar.value != searchBar.initial)
                        _Button(
                          onTap: searchBar.reset,
                          child: const Icon(Icons.rotate_left),
                        ),
                      if (searchBar.isOpen)
                        _Button(
                          onTap: searchBar.clear,
                          child: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double innerHeight = kBottomNavigationBarHeight + 12;
}

class _SearchField extends HookConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchBar = ref.watch(searchBarControllerProvider);
    final imeIncognito = ref.watch(
      uiSettingStateProvider.select((it) => it.imeIncognito),
    );
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);

    return TextField(
      autofocus: searchBar.isOpen,
      canRequestFocus: searchBar.isOpen,
      enableIMEPersonalizedLearning: !imeIncognito,
      controller: searchBar.textEditingController,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: searchBar.value.isEmpty
            ? context.t.searchHint(serverName: server.name)
            : searchBar.value,
        isDense: true,
      ),
      textAlign: searchBar.isOpen ? TextAlign.start : TextAlign.center,
      readOnly: !searchBar.isOpen,
      onSubmitted: (str) {
        searchBar.submit(context, str);
      },
      onTap: searchBar.isOpen ? null : searchBar.open,
      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
    );
  }
}

class _OptionBar extends ConsumerWidget {
  const _OptionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    // nhentai has no ratings (all explicit) but its own sort orders.
    final isNhentai = NhentaiJsonParser.isNhentai(server);
    final canSort = server.sortOptions.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (!isNhentai) ...[
              const _RatingButton(),
              const SizedBox(width: 8),
            ],
            if (canSort) ...[
              _SortButton(server: server),
              const SizedBox(width: 8),
            ],
            if (isNhentai) ...[
              _LanguageButton(server: server),
              const SizedBox(width: 8),
            ],
            const _RandomButton(),
          ],
        ),
      ),
    );
  }
}

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

class _Button extends StatelessWidget {
  const _Button({this.collapsed = false, required this.onTap, this.child});

  final bool collapsed;
  final void Function() onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          scale: collapsed ? 0.75 : 1,
          child: child,
        ),
      ),
    );
  }
}

class _LeadingButton extends ConsumerWidget {
  const _LeadingButton({this.collapsed = false});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final searchBar = ref.watch(searchBarControllerProvider);

    return _Button(
      collapsed: collapsed,
      onTap: () {
        if (searchBar.isOpen) {
          searchBar.close();
        } else {
          ref.read(homeDrawerControllerProvider).toggle();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animator) {
          final animation = Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(parent: animator, curve: Curves.easeInOutCubic),
          );
          return RotationTransition(
            turns: animation,
            child: ScaleTransition(scale: animation, child: child),
          );
        },
        child: searchBar.isOpen
            ? const Icon(Icons.arrow_back_rounded)
            : Favicon(
                key: ValueKey(server.homepage),
                url: server.homepage,
                iconSize: 18,
              ),
      ),
    );
  }
}

class _RatingIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRating),
    );

    String letter = 's';
    switch (rating) {
      case BooruRating.questionable:
        letter = 'q';
        break;
      case BooruRating.sensitive:
        letter = 'v';
        break;
      case BooruRating.explicit:
        letter = 'e';
        break;
      default:
        break;
    }
    Color color = Colors.green.shade800;
    switch (rating) {
      case BooruRating.questionable:
        color = Colors.grey.shade800;
        break;
      case BooruRating.sensitive:
        color = Colors.yellow.shade900;
        break;
      case BooruRating.explicit:
        color = Colors.red.shade800;
        break;
      default:
        break;
    }
    return Visibility(
      visible: rating != BooruRating.all,
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        padding: const EdgeInsets.all(4),
        child: Text(
          letter,
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
      ),
    );
  }
}

class _TrailingButton extends ConsumerWidget {
  const _TrailingButton({this.collapsed = false, this.scrollController});

  final bool collapsed;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = context.iconTheme.size ?? 24;
    final grid = ref.watch(uiSettingStateProvider.select((ui) => ui.grid));

    backToTop() {
      scrollController?.animateTo(
        0,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    }

    return _Button(
      onTap: collapsed
          ? backToTop
          : ref.read(uiSettingStateProvider.notifier).cycleGrid,
      collapsed: collapsed,
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animator) {
            final animation = Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: animator, curve: Curves.easeInOutCubic),
            );
            return RotationTransition(
              turns: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: collapsed
              ? const Icon(Icons.arrow_upward_rounded)
              : Icon(key: ValueKey(grid), Icons.grid_view, size: 20),
        ),
      ),
    );
  }
}
