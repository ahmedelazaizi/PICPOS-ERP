// Fixed texts the warehouse documents write into stored data (journal
// descriptions, invoice notes, movement notes). They live here, not inline in
// the services, so they are one reviewable list (WH-022). They are DATA written
// once, so they do not go through the UI `tr()` (the reader's language is not
// the writer's); the Arabic wording is the books' language.
abstract final class WhConstants {
  static const receiptJournalNote = 'استلام من تطبيق المخازن';

  static String transferOutJournal(String gid) => 'تحويل مرحلي — إرسال ($gid)';
  static String transferInJournal(String gid) => 'تحويل مرحلي — استلام ($gid)';
  static String transferReturnJournal(String gid) => 'تحويل مرحلي — إعادة النقص للمصدر ($gid)';
  static String transferLossJournal(String gid) => 'تحويل مرحلي — فقد في الطريق ($gid)';
  static String transferDamageReason(String gid) => 'تالف عند استلام تحويل $gid';

  static String transferOutNote(int? toWarehouse, String gid) => 'Transfer out to warehouse #$toWarehouse ($gid)';
  static String transferInNote(int fromWarehouse, String gid) => 'Transfer in from warehouse #$fromWarehouse ($gid)';
  static String transferReturnNote(String gid) => 'Short quantity returned to source ($gid)';
}
