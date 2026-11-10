part of 'settings_page.dart';

// Settings → Monbooru (monloader): address and token for "Send to Monbooru".

class _Monbooru extends StatelessWidget {
  const _Monbooru();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(context.t.monbooru.settings.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(context.t.monbooru.settings.desc),
      ),
      onTap: () =>
          showDialog(context: context, builder: (_) => const _MonbooruDialog()),
    );
  }
}

class _MonbooruDialog extends StatefulWidget {
  const _MonbooruDialog();

  @override
  State<_MonbooruDialog> createState() => _MonbooruDialogState();
}

class _MonbooruDialogState extends State<_MonbooruDialog> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  String? _status;

  @override
  void initState() {
    super.initState();
    _url.addListener(_onChanged);
    _token.addListener(_onChanged);
    MonbooruSender.load().then((c) {
      if (!mounted) return;
      _url.text = c.url;
      _token.text = c.token;
    });
  }

  void _onChanged() => setState(() {});

  /// Plain HTTP outside the local network sends the bearer token unencrypted.
  bool get _insecureToken =>
      _token.text.trim().isNotEmpty &&
      ServerAuthStore.isInsecureRemote(MonbooruSender.normalizeUrl(_url.text));

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() => _status = context.t.monbooru.settings.testing);
    final error = await MonbooruSender.testConnection(_url.text);
    if (!mounted) return;
    setState(
      () =>
          _status = error?.describe(context) ?? context.t.monbooru.settings.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t.monbooru.settings.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.t.monbooru.settings.address,
                hintText: 'http://192.168.0.10:8080',
              ),
            ),
            TextField(
              controller: _token,
              autocorrect: false,
              obscureText: true,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: context.t.monbooru.settings.token,
                helperText: _insecureToken
                    ? context.t.servers.apiToken.insecure
                    : context.t.monbooru.settings.tokenDesc,
                helperMaxLines: 4,
                helperStyle: _insecureToken
                    ? TextStyle(color: context.colorScheme.error)
                    : null,
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status!),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                context.t.monbooru.settings.duplicateCheck,
                style: context.theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _test,
          child: Text(context.t.monbooru.settings.test),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: () async {
            await MonbooruSender.save(_url.text, _token.text);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(context.t.save),
        ),
      ],
    );
  }
}
