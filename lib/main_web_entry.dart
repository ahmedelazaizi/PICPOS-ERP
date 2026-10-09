// نقطة دخول الويب المستقلة (المرحلة 1 من docs/superpowers/specs/2026-09-01-saas-web-design.md).
//
// البناء:
//   flutter build web --release --no-tree-shake-icons --no-wasm-dry-run -t lib/main_web_entry.dart
//
// عمدًا لا تستورد main.dart ولا main_desktop.dart ولا connection_io ولا أي حزمة
// أجهزة (POS/ميزان/طباعة حرارية/shelf). منطق الأعمال يُوصَّل في مراحل لاحقة
// (drift/remote للقراءة + HTTP API للكتابة).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'web/web_dashboard_preview.dart';

void main() {
  runApp(const ProviderScope(child: PicPosWebApp()));
}

class PicPosWebApp extends StatelessWidget {
  const PicPosWebApp({super.key});

  static const Color _brandBlue = Color(0xFF0250D3);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PicPos Web',
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
      home: const _ServerLoginPage(),
    );
  }
}

/// شاشة مؤقتة: عنوان السيرفر + اسم المستخدم + كلمة المرور (بلا اتصال فعلي بعد).
class _ServerLoginPage extends StatefulWidget {
  const _ServerLoginPage();

  @override
  State<_ServerLoginPage> createState() => _ServerLoginPageState();
}

class _ServerLoginPageState extends State<_ServerLoginPage> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _notice;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _notice =
        'الاتصال بالسيرفر غير مفعّل بعد في هذه المرحلة (نسخة الويب قيد التجهيز).');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
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
                    decoration: const InputDecoration(
                      labelText: 'عنوان السيرفر',
                      hintText: 'https://erp.example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _submit, child: const Text('دخول')),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => openWebDashboardPreview(context),
                    child: const Text('Dashboard preview'),
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    Text(_notice!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
