import 'package:flutter/material.dart';

/// App-wide messenger, for messages that arrive after the screen that
/// started an action is gone (e.g. a Monbooru job finishing later).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows [text] with the app-wide messenger. [build] gets a context below
/// the app's translations.
void showRootSnackBar(
  String Function(BuildContext context) build, {
  Duration duration = const Duration(seconds: 4),
}) {
  final state = rootMessengerKey.currentState;
  final context = rootMessengerKey.currentContext;
  if (state == null || context == null) return;
  state
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(build(context)), duration: duration));
}
