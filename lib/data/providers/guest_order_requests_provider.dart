import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/guest_order_requests.dart';
import '../../services/network_service.dart';
import '../../services/server_proxy.dart';

/// طلباتُ الضيوف المعلَّقةُ كما تراها **هذه** الشاشة.
///
/// ⚠️ **مصدران لا واحد، والفرقُ بنيويٌّ لا تفصيليّ.** الطابورُ يعيش في ذاكرة
/// الخادم ولا مرآةَ له في القاعدة، فلا يصل بالمزامنة كما يصل كلُّ ما تعرضه
/// شاشةُ الطاولات:
///
///   • على الخادم: يُقرأ من الذاكرة مباشرةً ويُوقظ بمُبلِّغه.
///   • على العميل: يُسأل الخادمُ دوريّاً — لا إشعارَ يصله.
///
/// وقراءةُ الذاكرة على عميلٍ تُرجع **فارغاً دائماً**: نفيٌ يبدو يقيناً، وهو
/// أسوأُ من غياب الميزة.
final guestOrderRequestsProvider =
    StreamProvider.autoDispose<List<GuestOrderRequest>>((ref) {
  if (NetworkService.instance.isServer) {
    return _serverSideStream(ref);
  }
  return _clientSideStream(ref);
});

/// على الخادم: بثٌّ عند كلّ تغيّرٍ في الطابور — بلا استطلاع.
Stream<List<GuestOrderRequest>> _serverSideStream(Ref ref) {
  final queue = GuestOrderRequests.instance;
  final controller = StreamController<List<GuestOrderRequest>>();
  void emit() {
    if (!controller.isClosed) controller.add(queue.pending);
  }

  queue.addListener(emit);
  ref.onDispose(() {
    queue.removeListener(emit);
    controller.close();
  });
  emit();
  return controller.stream;
}

/// على العميل: استطلاعٌ دوريّ.
///
/// ⚠️ **وأوّلُ سؤالٍ فوريٌّ لا بعد الفترة**: فتحُ الشاشة يجب أن يُظهر ما هو
/// معلَّقٌ الآن، لا أن يترك النادلَ أمام «لا طلبات» عشرَ ثوانٍ وهي كاذبة.
Stream<List<GuestOrderRequest>> _clientSideStream(Ref ref) async* {
  const interval = Duration(seconds: 10);
  while (true) {
    final raw = await ServerProxy.instance.fetchGuestOrderRequests();
    // `null` = تعذّر السؤال. ولا تُبَثّ قائمةٌ فارغةٌ حينَها: الفراغُ يقول
    // «لا طلبات» والصوابُ «لا أعرف»، والأوّلُ يُخفي طلباً حقيقيّاً.
    if (raw != null) yield [for (final m in raw) _parse(m)];
    await Future<void>.delayed(interval);
  }
}

GuestOrderRequest _parse(Map<String, dynamic> m) => GuestOrderRequest(
      id: (m['id'] as num).toInt(),
      tableId: (m['tableId'] as num).toInt(),
      orderId: (m['orderId'] as num).toInt(),
      tableName: (m['tableName'] as String?) ?? '—',
      at: DateTime.tryParse((m['at'] as String?) ?? '') ?? DateTime.now(),
      lines: [
        for (final l in (m['lines'] as List? ?? const []))
          GuestOrderLine(
            productId: ((l as Map)['productId'] as num).toInt(),
            quantity: (l['qty'] as num).toDouble(),
            note: l['note'] as String?,
          ),
      ],
    );
