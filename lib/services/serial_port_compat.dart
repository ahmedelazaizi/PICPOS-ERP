// واجهة موحّدة لـ SerialPort: على الأجهزة (dart:io) هي الحزمة الأصلية
// serial_port_win32 كما كانت، وعلى الويب نسخة وهمية بنفس التوقيعات
// (الويب خارج نطاقه الأجهزة التسلسلية — انظر docs/superpowers/specs/2026-09-01-saas-web-design.md).
export 'package:serial_port_win32/serial_port_win32.dart'
    if (dart.library.js_interop) 'serial_port_compat_web.dart';