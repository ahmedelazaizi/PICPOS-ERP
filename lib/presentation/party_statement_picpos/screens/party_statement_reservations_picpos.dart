part of 'party_statement_picpos_screen.dart';

/// تبويبُ «الحجوزات» (P3): حجوزاتُ الخدمات والطاولات المرتبطةُ بالعميل
/// (`partyId`) — للعملاء فقط. المحتوى في `widgets/party_reservations_tab.dart`.
mixin _StatementReservationsMixin on _StatementTabsMixin {
  @override
  Future<_TabData> _reservationsTab() async {
    final rows = await ref.read(partyReservationsProvider(partyId!).future);
    return _TabData(
      badge: rows.isEmpty ? null : '${rows.length}',
      blocks: [PartyReservationsTab(partyId: partyId!)],
    );
  }
}
