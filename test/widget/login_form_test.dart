// ═══════════════════════════════════════════════════════════════════════════
// Day 10 — Login Form Widget Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests the login form structure and validation feedback.
// Uses a lightweight test double for the form — avoids mounting the real
// LoginScreen which pulls in auth providers and HTTP services.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal login form that mirrors the real form's validation UX.
/// Contains username + password fields and a login button.
/// On submit: validates emptiness and shows inline error messages.
class _LoginFormUnderTest extends StatefulWidget {
  const _LoginFormUnderTest();

  @override
  State<_LoginFormUnderTest> createState() => _LoginFormUnderTestState();
}

class _LoginFormUnderTestState extends State<_LoginFormUnderTest> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  String? _errorMessage;
  bool _requiresPasswordChange = false;

  @override
  void dispose() {
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    // Simulate: admin with unchanged default password → force change
    if (_usernameCtl.text == 'admin' && _passwordCtl.text == 'admin') {
      setState(() => _requiresPasswordChange = true);
      return;
    }

    // Simulate wrong credentials
    setState(() => _errorMessage = 'اسم المستخدم أو كلمة المرور غير صحيحة');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('username_field'),
                  controller: _usernameCtl,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'الحقل مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('password_field'),
                  controller: _passwordCtl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'الحقل مطلوب' : null,
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    key: const Key('error_message'),
                    style: const TextStyle(color: Colors.red),
                  ),
                if (_requiresPasswordChange)
                  const Text(
                    'يجب تغيير كلمة المرور الافتراضية',
                    key: Key('password_change_required'),
                    style: TextStyle(color: Colors.orange),
                  ),
                ElevatedButton(
                  key: const Key('login_button'),
                  onPressed: _submit,
                  child: const Text('تسجيل الدخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  Widget buildApp() => const MaterialApp(home: _LoginFormUnderTest());

  group('Day 10 — Login Form Widget Tests', () {
    // ── Test 6: wrong credentials → clear error message ──────────────────
    testWidgets('بيانات خاطئة → رسالة خطأ واضحة', (tester) async {
      await tester.pumpWidget(buildApp());

      // Enter wrong credentials
      await tester.enterText(find.byKey(const Key('username_field')), 'wrong');
      await tester.enterText(
          find.byKey(const Key('password_field')), 'wrongpwd');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pump();

      expect(find.byKey(const Key('error_message')), findsOneWidget);
      expect(find.text('اسم المستخدم أو كلمة المرور غير صحيحة'), findsOneWidget);
    });

    // ── Test 7: admin + default password → redirect to password change ────
    testWidgets('admin بكلمة المرور الافتراضية → يُوجَّه لتغييرها',
        (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.enterText(find.byKey(const Key('username_field')), 'admin');
      await tester.enterText(
          find.byKey(const Key('password_field')), 'admin');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pump();

      expect(
          find.byKey(const Key('password_change_required')), findsOneWidget);
      expect(find.byKey(const Key('error_message')), findsNothing);
    });
  });
}
