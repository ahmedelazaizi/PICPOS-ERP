// S-01 / S-13: مفاتيح إعدادات يملكها الخادم/النظام (ترخيص، تجربة، انتقال
// الـbearer القديم). لا تُكتب عبر `POST /api/settings` ولا بمزامنة من عميل.
// المسارات الداخلية الشرعية تكتبها مباشرة بـ`db.setSetting` فلا تتأثر.

/// المفاتيح المحجوبة (مطابقة تامة).
const List<String> kHostOwnedSettingKeys = <String>[
  'lan_legacy_token_enabled',
  'lan_legacy_transition_started_at',
  'lan_legacy_transition_days',
  'lan_legacy_transition_ended',
  'trial_policy',
  'install_date',
  'license_key',
  'admin_password_customized',
  'table_bill_legacy_accepted',
];

/// هل [key] يملكه الخادم فلا يُكتب من API/مزامنة؟
bool isHostOwnedSettingKey(String key) => kHostOwnedSettingKeys.contains(key);
