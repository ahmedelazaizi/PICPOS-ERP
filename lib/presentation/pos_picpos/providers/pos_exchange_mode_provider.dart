import 'package:flutter_riverpod/legacy.dart';

import '../state/pos_exchange_mode.dart';

/// وضعُ الاستبدال الجاري، أو `null` خارجَه.
///
/// **منفصلٌ عن `posReturnModeProvider` عمداً وحصريٌّ معه:** الوضعان يقرآن نفسَ
/// الفاتورة لكنّهما يفعلان بالسلّة عكسَ بعضهما — المرتجعُ يمنع تعديلَها،
/// والاستبدالُ يبني عليها البديل. وحالةٌ واحدةٌ بعلَمٍ كانت ستُخفي هذا
/// التناقضَ خلف شرطٍ في كلِّ موضع.
final posExchangeModeProvider = StateProvider<PosExchangeMode?>((ref) => null);
