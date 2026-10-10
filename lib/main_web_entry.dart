// نقطة دخول الويب المستقلة (docs/superpowers/specs/2026-09-01-saas-web-design.md).
//
// البناء:
//   flutter build web --release --no-tree-shake-icons --no-wasm-dry-run -t lib/main_web_entry.dart
//
// عمدًا لا تستورد main.dart ولا main_desktop.dart ولا connection_io ولا أي شاشة
// POS/مطبخ/طاولات/ميزان/إقفال وردية/اختبار طباعة (يفرضه
// test/structural/web_entry_scope_test.dart).
//
// م3-6: دخول حقيقي (POST /api/web/session) ثم قناة drift للقراءة
// (/webdb) وتجاوز `databaseProvider` — انظر lib/web/.
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/write_router.dart' show MirrorOfflineException;
import 'web/web_providers.dart';
import 'web/web_session.dart';
import 'web/web_shell.dart';

/// يعرض رسائل أخطاء الكتابة عبر HTTP (م3-7) أياً كانت الشاشة.
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  // فشل الكتابة (انقطاع الخادم أو رفضه) يرمي MirrorOfflineException بنصٍّ عربي:
  // يُعرض في شريط تنبيه بدل أن يضيع كخطأ غير ملتقَط. لا شيء حُفظ (لا صندوق صادر).
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is MirrorOfflineException) {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
      return true;
    }
    return false;
  };
  runApp(ProviderScope(
    overrides: webProviderOverrides,
    child: const PicPosWebApp(),
  ));
}

class PicPosWebApp extends StatelessWidget {
  const PicPosWebApp({super.key});

  static const Color _brandBlue = Color(0xFF0250D3);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PicPos Web',
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _brandBlue),
        scaffoldBackgroundColor: const Color(0xFFF2F5FA),
      ),
      home: const _WebGate(),
    );
  }
}

/// يبدّل بين الدخول والتطبيق حسب الجلسة.
class _WebGate extends ConsumerWidget {
  const _WebGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(webSessionProvider);
    if (session == null) return const _ServerLoginPage();
    return WebShell(session: session);
  }
}

/// شاشة الدخول: عنوان السيرفر (اختياري) + اسم المستخدم + كلمة المرور.
class _ServerLoginPage extends ConsumerStatefulWidget {
  const _ServerLoginPage();

  @override
  ConsumerState<_ServerLoginPage> createState() => _ServerLoginPageState();
}

class _ServerLoginPageState extends ConsumerState<_ServerLoginPage> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await WebAuthClient().login(
        baseUrl: WebSession.normalizeBaseUrl(_server.text),
        username: _user.text.trim(),
        password: _pass.text,
      );
      if (!mounted) return;
      ref.read(webSessionProvider.notifier).signIn(session);
    } on WebAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sameOrigin = WebSession.defaultBaseUrl();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('PicPos Web',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text('الحسابات والفواتير والمخزون والتقارير',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _server,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'عنوان السيرفر (اختياري)',
                          hintText: sameOrigin.isEmpty
                              ? 'https://erp.example.com'
                              : 'الافتراضي: $sameOrigin',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _user,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pass,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('دخول'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
