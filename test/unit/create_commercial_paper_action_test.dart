// test/unit/create_commercial_paper_action_test.dart
//
// إنشاءُ ورقةٍ تجاريّة — **كتابتان بهويّةٍ واحدة**.
//
// ═══ العطبُ الذي يحرسه هذا الملفّ ═══
//
// إنشاءُ الورقة يكتب مرّتَين على العميل: دفعةٌ للخادم عبر
// `ClientWriteInterceptor` ثمّ كتابةٌ محلّيّةٌ عبر المستودع. و`globalId`
// يُسَكّ **مرّةً واحدةً** ويُمرَّر لكليهما.
//
// 🔴 وقع فعلاً (‏Cluster 030 / Bug D): لمّا سُكَّ الـ`globalId` في كلّ طرفٍ
// على حدة، انتهى الخادمُ والمرآةُ بهويّتَين مختلفتَين لنفس الورقة — فكلُّ
// تحديثِ حالةٍ لاحقٍ من المرآة يفشل بـ«Commercial paper not found».
//
// ⇒ فحين صارت شاشةُ PicPos تُنشئ ورقةً أيضاً، كان **نسخُ** الكتلة يعني
//   نسختَين من مسارٍ ماليٍّ تنحرفان بأوّل تعديل. فاستُخرجت إلى دالّةٍ
//   واحدةٍ تستدعيها الشاشتان، وهذا الاختبارُ يثبّت عقدَها.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/repositories/commercial_papers_repository.dart';
import 'package:ural_erp/presentation/screens/commercial_papers/create_paper_action.dart';

class _RecordingRepo implements ICommercialPapersRepository {
  final List<Map<String, Object?>> created = [];

  @override
  Future<int> createPaper({
    required String paperNumber,
    required String type,
    required String direction,
    required int partyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    int? safeId,
    String? accountNumber,
    String? notes,
    String? globalId,
    int? sourceVoucherId,
  }) async {
    created.add({
      'paperNumber': paperNumber,
      'type': type,
      'direction': direction,
      'partyId': partyId,
      'amount': amount,
      'issueDate': issueDate,
      'dueDate': dueDate,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'notes': notes,
      'globalId': globalId,
    });
    return created.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _form({
  String type = 'cheque',
  String number = 'CHQ-001',
  double amount = 1500,
  int partyId = 7,
  String? bankName = 'بنك مصر',
  String? accountNumber = '123456',
  String? notes = 'ملاحظة',
}) =>
    {
      'confirmed': true,
      'type': type,
      'number': number,
      'amount': amount,
      'partyId': partyId,
      'bankName': bankName,
      'bankSafeId': null,
      'accountNumber': accountNumber,
      'issueDate': DateTime(2026, 8, 1),
      'dueDate': DateTime(2026, 9, 1),
      'notes': notes,
    };

void main() {
  late _RecordingRepo repo;

  setUp(() => repo = _RecordingRepo());

  test('يكتب محلّيّاً بهويّةٍ مسكوكةٍ لا فارغة', () async {
    await createCommercialPaper(
      repo: repo,
      direction: 'received',
      form: _form(),
    );

    expect(repo.created, hasLength(1));
    final row = repo.created.single;
    // ⚠️ الهويّةُ هي ما يربط الصفَّ المحلّيَّ بنظيره على الخادم. فراغُها
    //    يعني ورقةً لا يمكن تحديثُ حالتها من المرآة أبداً.
    expect(row['globalId'], isA<String>());
    expect((row['globalId']! as String).length, greaterThan(8));
    expect(row['paperNumber'], 'CHQ-001');
    expect(row['amount'], 1500.0);
    expect(row['partyId'], 7);
  });

  test('و«الحافظة» ليست اتّجاهاً — تُقرأ «واردة»', () async {
    // ⚠️ `portfolio` تبويبةُ عرضٍ لا اتّجاهُ ورقة. وتمريرُها كما هي كان
    //    يكتب في العمود قيمةً لا يعرفها أيُّ مرشِّحٍ لاحق، فتختفي الورقةُ
    //    من «الواردة» و«الصادرة» معاً.
    await createCommercialPaper(
      repo: repo,
      direction: 'portfolio',
      form: _form(),
    );

    expect(repo.created.single['direction'], 'received');
  });

  test('والصادرةُ تبقى صادرة', () async {
    await createCommercialPaper(
      repo: repo,
      direction: 'issued',
      form: _form(),
    );

    expect(repo.created.single['direction'], 'issued');
  });

  test('وكلُّ ورقةٍ هويّةٌ خاصّةٌ بها', () async {
    await createCommercialPaper(
      repo: repo, direction: 'received', form: _form(number: 'CHQ-001'));
    await createCommercialPaper(
      repo: repo, direction: 'received', form: _form(number: 'CHQ-002'));

    final ids = repo.created.map((r) => r['globalId']).toSet();
    expect(ids, hasLength(2),
        reason: 'هويّتان متساويتان = ورقتان تُقرآن واحدةً على الخادم');
  });

  test('ونصٌّ فارغٌ يُكتَب `null` لا سلسلةً فارغة', () async {
    // ⚠️ `''` و`null` ليسا سواءً في التقارير: حقلٌ فارغٌ يُطبَع سطراً
    //    خالياً بينما الغائبُ يُطوى. والحوارُ يُرجع `''` حين لا يكتب
    //    المستخدمُ شيئاً.
    await createCommercialPaper(
      repo: repo,
      direction: 'received',
      form: _form(notes: '', accountNumber: ''),
    );

    expect(repo.created.single['notes'], isNull);
    expect(repo.created.single['accountNumber'], isNull);
  });
}
