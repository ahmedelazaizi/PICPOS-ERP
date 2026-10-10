import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../admin_session.dart';
import '../l10n/strings.dart';
import 'unpair_flow.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.session,
    required this.onPreview,
    this.initialError,
  });
  final AdminSession session;
  final VoidCallback onPreview;
  final String? initialError;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _url = TextEditingController();
  final _code = TextEditingController();
  final _offer = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username.text = widget.session.username ?? '';
  }

  @override
  void dispose() {
    for (final controller in [_url, _code, _offer, _username, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// M-5: manual pairing gets its signing key from the cloud; show the key
  /// fingerprint so the user can compare it with the office computer first.
  Future<bool> _confirmKey(String fingerprint) async {
    if (!mounted) return false;
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('admin.keyConfirm'),
        title: Text(t('keyFingerprintTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('keyFingerprintBody')),
            const SizedBox(height: PicPosSpacing.md),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                fingerprint,
                key: const Key('admin.keyFingerprint'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('admin.keyReject'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            key: const Key('admin.keyAccept'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('keyFingerprintMatches')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = S.errorText(context, error.message));
    } on ApiError catch (error) {
      if (mounted) {
        setState(() => _error = S.errorText(context, error.code, retryAfter: error.retryAfter));
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PicPosPageHeader(
              title: t('pairTitle'),
              subtitle: t('pairSub'),
              icon: Icons.qr_code_2,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PicPosSpacing.lg),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PicPosBlock(
                            title: widget.session.paired
                                ? t('signIn')
                                : t('manualEntry'),
                            child: widget.session.paired
                                ? Column(
                                    children: [
                                      Text(
                                        t('boundToUser', {'user': widget.session.displayName ?? widget.session.username ?? t('unknownUser')}),
                                      ),
                                      TextField(
                                        key: const Key('admin.username'),
                                        controller: _username,
                                        textDirection: TextDirection.ltr,
                                        keyboardType: TextInputType.visiblePassword,
                                        textCapitalization: TextCapitalization.none,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        decoration: InputDecoration(
                                          labelText: t('username'),
                                        ),
                                      ),
                                      TextField(
                                        key: const Key('admin.password'),
                                        controller: _password,
                                        obscureText: true,
                                        keyboardType: TextInputType.visiblePassword,
                                        textDirection: TextDirection.ltr,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        decoration: InputDecoration(
                                          labelText: t('mobilePassword'),
                                        ),
                                      ),
                                      const SizedBox(height: PicPosSpacing.md),
                                      FilledButton(
                                        key: const Key('admin.login'),
                                        onPressed: _busy
                                            ? null
                                            : () => _run(
                                                () => widget.session.login(
                                                  _username.text.trim(),
                                                  _password.text,
                                                ),
                                              ),
                                        child: Text(t('signIn')),
                                      ),
                                      TextButton(
                                        key: const Key('admin.unpair'),
                                        onPressed: _busy ? null : () => confirmUnpair(context, widget.session),
                                        child: Text(t('unpairDevice')),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextField(
                                        key: const Key('admin.url'),
                                        controller: _url,
                                        keyboardType: TextInputType.url,
                                        textDirection: TextDirection.ltr,
                                        autocorrect: false,
                                        decoration: InputDecoration(
                                          labelText: t('serverUrl'),
                                          hintText: 'https://',
                                        ),
                                      ),
                                      TextField(
                                        key: const Key('admin.code'),
                                        controller: _code,
                                        textDirection: TextDirection.ltr,
                                        textCapitalization: TextCapitalization.characters,
                                        autocorrect: false,
                                        decoration: InputDecoration(
                                          labelText: t('pairingCode'),
                                        ),
                                      ),
                                      TextField(
                                        key: const Key('admin.offer'),
                                        controller: _offer,
                                        maxLines: 2,
                                        textDirection: TextDirection.ltr,
                                        decoration: InputDecoration(
                                          labelText: t('pasteOffer'),
                                        ),
                                      ),
                                      const SizedBox(height: PicPosSpacing.md),
                                      FilledButton(
                                        key: const Key('admin.pair'),
                                        onPressed: _busy
                                            ? null
                                            : () => _run(() {
                                                final offer =
                                                    _offer.text
                                                        .trim()
                                                        .isNotEmpty
                                                    ? PairingOffer.fromQr(
                                                        _offer.text.trim(),
                                                      )
                                                    : PairingOffer.manual(
                                                        url: _url.text,
                                                        code: _code.text,
                                                      );
                                                return widget.session.pair(
                                                  offer,
                                                  confirmKey: _confirmKey,
                                                );
                                              }),
                                        child: Text(t('pair')),
                                      ),
                                    ],
                                  ),
                          ),
                          if (_busy) const LinearProgressIndicator(),
                          if ((_error ?? widget.initialError) != null)
                            Text(
                              '${t('requestFailed')}: ${_error ?? widget.initialError}',
                              key: const Key('admin.error'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          const SizedBox(height: PicPosSpacing.md),
                          if (!widget.session.paired)
                            TextButton.icon(
                              key: const Key('onboarding.preview'),
                              onPressed: widget.onPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text(t('previewApp')),
                            ),
                          const Center(child: PicPosLanguageThemeControls()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
