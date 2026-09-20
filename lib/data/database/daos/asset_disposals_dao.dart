part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// طلبُ استبعاد أصل — أوّلُ كاتبٍ لـ`AssetDisposals` (v174 شحنت الجدولَ بلا كاتب)
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ 🔴 مستندٌ له دورةُ حياة، والأثرُ عند الاعتماد وحدَه ═══
//
// `disposeAsset` القائمةُ **تنفّذ فوراً**: تستدعيها فتُقفَل الأصولُ ويُقيَّد
// القيد. ولا مسوّدةَ فيها ولا مراجعة. والتصميمُ `(6)` زرّان — «حفظ مسودة»
// و«مراجعة واعتماد» — و`AssetDisposals.status` يحمل `draft`/`approved`/
// `cancelled`. فالمسوّدةُ هنا **بلا أيّ أثرٍ محاسبيّ**، والاعتمادُ وحدَه
// يكتب في الدفاتر.
//
// ═══ 🔴 وثلاثةُ أعطابٍ في `disposeAsset` لا تُورَّث ═══
//
// ‏١) **تقيّد مدينَ نقديّةٍ على `1111` ولا تحرّك خزنةً إطلاقاً** — فيزيد
//    النقدُ في الأستاذ ولا يزيد في أيّ درج، ويفترق رصيدُ الخزينة عن دفترها
//    من أوّل أصلٍ يُباع. وهنا: الخزنةُ شرطٌ في النقديّ، والقيدُ على
//    **حسابها المرتبط** لا على `1111` عمياءَ، وحركةُ الخزنة تقع معه.
//
// ‏٢) **لا فرعَ للآجل**: بيعٌ على ذمّة عميلٍ كان يُقيَّد نقداً. وهنا فرعٌ
//    ثانٍ: مدينُ حساب العميل الفرعيّ، ورصيدُه يرتفع بالقيمة.
//
// ‏٣) 🔴 **وإن غاب حسابٌ سقط القيدُ كلُّه صامتاً**: `if (assetAcc != null &&
//    accumAcc != null && cashAcc != null)` — والأصلُ يُختَم «مستبعَداً»
//    خارجَها. فتكلفتُه ومجمَّعُه يبقيان في الأستاذ **إلى الأبد** ولا شيءَ
//    يبلّغ. وهنا: يُرمى قبل أن يُمَسّ شيء.
//
// ⚠️ **ولا تُعدَّل `disposeAsset` نفسُها**: مناديها الوحيدُ حوارُ UralCash
//    (`fixed_assets_dialogs.dart:1105`) وهو `part of` شاشتها فلا يبلغه هذا
//    الفورك، والعملُ على UralCash موقوفٌ بقرار مالك. فتصحيحُها تغييرُ سلوكٍ
//    في منتَجٍ آخرَ لم يطلبه أحد — والعطبُ موصوفٌ هنا بموضعه.

/// صفُّ طلبٍ مع ما يلزم لعرضه — **بلا نداءٍ ثانٍ لكلّ صفّ**.
typedef AssetDisposalListRow = ({
  AssetDisposalData request,
  String assetName,
  String assetCode,
  double originalCost,
  double accumulatedDepreciation,
  String assetStatus,
});

extension AssetDisposalsDao on AppDatabase {
  Stream<List<AssetDisposalData>> watchAssetDisposals() {
    return (select(assetDisposals)
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([(d) => OrderingTerm.desc(d.disposalDate)]))
        .watch();
  }

  Future<AssetDisposalData?> getAssetDisposal(int id) {
    return (select(assetDisposals)..where((d) => d.id.equals(id)))
        .getSingleOrNull();
  }

  /// الطلباتُ مع بيانات أصولها — لجدول الشاشة.
  Future<List<AssetDisposalListRow>> getAssetDisposalRows() async {
    final rows = await (select(assetDisposals)
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([(d) => OrderingTerm.desc(d.disposalDate)]))
        .join([
      leftOuterJoin(fixedAssets, fixedAssets.id.equalsExp(assetDisposals.assetId)),
    ]).get();

    return [
      for (final r in rows)
        () {
          final a = r.readTableOrNull(fixedAssets);
          return (
            request: r.readTable(assetDisposals),
            assetName: a?.name ?? '— أصل محذوف',
            assetCode: a?.code ?? '',
            originalCost: a?.purchasePrice ?? 0,
            accumulatedDepreciation: a?.accumulatedDepreciation ?? 0,
            assetStatus: a?.status ?? 'unknown',
          );
        }(),
    ];
  }

  /// هل للأصل طلبٌ مفتوحٌ بالفعل؟ — مسوّدةٌ قائمةٌ تمنع ثانيةً.
  Future<AssetDisposalData?> getOpenDisposalForAsset(int assetId) {
    return (select(assetDisposals)
          ..where((d) =>
              d.assetId.equals(assetId) &
              d.status.equals('draft') &
              d.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// يحفظ طلباً **مسودةً** — ولا أثرَ محاسبيّاً هنا إطلاقاً.
  ///
  /// يُرجع معرّفَ الصفّ. ورقمُ الطلب (`ADP-####`) يُولَّد **داخل المعاملة**
  /// (‏مواصفة ٠٦٦)، فلا رقمَ يُعرَض قبل الحفظ.
  Future<int> createAssetDisposalRequest({
    required int assetId,
    required DateTime disposalDate,
    required String method,
    required double disposalValue,
    required String collectionMethod,
    required String reason,
    int? buyerPartyId,
    int? safeId,
    int? costCenterId,
    int? createdBy,
    String? globalId,
  }) async {
    return transaction(() async {
      final asset = await _disposalAsset(assetId);
      // 🔴 **الفحصُ على الخامّ ثمّ التطبيع.** التطبيعُ يصفّر قيمةَ الإعدام،
      //    فتطبيعٌ قبل الفحص يبتلع «٥٠٠ على إعدام» صامتاً: المستخدمُ كتب
      //    رقماً ولم يُقَل له إنّه أُهمل، والصفُّ يُقرأ لاحقاً على أنّه
      //    إعدامٌ لم يُحصَّل منه شيء.
      _assertRawDisposalSane(
        asset: asset,
        method: method,
        disposalValue: disposalValue,
        collectionMethod: collectionMethod,
        buyerPartyId: buyerPartyId,
        reason: reason,
      );
      final n = normalizeDisposal(
        method: method,
        disposalValue: disposalValue,
        collectionMethod: collectionMethod,
        buyerPartyId: buyerPartyId,
        safeId: safeId,
      );

      // ⚠️ **طلبٌ واحدٌ مفتوحٌ لكلّ أصل.** اثنان يُعتمَدان فيقيّدان الأصلَ
      //    مرّتين — والثاني يسقط على «الأصل غير نشط» إن اعتُمد الأوّلُ قبله،
      //    لكنّه يبقى معروضاً كطلبٍ حيٍّ لأصلٍ ذهب.
      final open = await getOpenDisposalForAsset(assetId);
      if (open != null) {
        throw Exception('للأصل طلبُ استبعادٍ مفتوحٌ بالفعل (${open.disposalNumber})');
      }

      return into(assetDisposals).insert(
        AssetDisposalsCompanion.insert(
          assetId: assetId,
          disposalNumber: await generateInvoiceNumber('ADP'),
          disposalDate: disposalDate,
          method: n.method,
          disposalValue: Value(n.disposalValue),
          collectionMethod: Value(n.collectionMethod),
          buyerPartyId: Value(n.buyerPartyId),
          notes: Value(reason.trim()),
          costCenterId: Value(costCenterId),
          createdBy: Value(createdBy),
          globalId: Value(globalId ?? UuidV7.generate()),
        ),
      );
    });
  }

  /// يعدّل مسوّدةً — **ولا يُمَسّ طلبٌ مُعتمَد**.
  Future<void> updateAssetDisposalRequest({
    required int id,
    required DateTime disposalDate,
    required String method,
    required double disposalValue,
    required String collectionMethod,
    required String reason,
    int? buyerPartyId,
    int? safeId,
    int? costCenterId,
  }) async {
    await transaction(() async {
      final req = await getAssetDisposal(id);
      if (req == null) throw Exception('الطلب غير موجود');
      if (req.status != 'draft') {
        throw Exception('طلبٌ ${_disposalStatusWord(req.status)} لا يُعدَّل');
      }
      final asset = await _disposalAsset(req.assetId);
      _assertRawDisposalSane(
        asset: asset,
        method: method,
        disposalValue: disposalValue,
        collectionMethod: collectionMethod,
        buyerPartyId: buyerPartyId,
        reason: reason,
      );
      final n = normalizeDisposal(
        method: method,
        disposalValue: disposalValue,
        collectionMethod: collectionMethod,
        buyerPartyId: buyerPartyId,
        safeId: safeId,
      );

      await (update(assetDisposals)..where((d) => d.id.equals(id))).write(
        AssetDisposalsCompanion(
          disposalDate: Value(disposalDate),
          method: Value(n.method),
          disposalValue: Value(n.disposalValue),
          collectionMethod: Value(n.collectionMethod),
          buyerPartyId: Value(n.buyerPartyId),
          notes: Value(reason.trim()),
          costCenterId: Value(costCenterId),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// يُلغي مسوّدةً. **ولا حذف**: الطلبُ مستندٌ يُراجَع.
  Future<void> cancelAssetDisposalRequest(int id) async {
    await transaction(() async {
      final req = await getAssetDisposal(id);
      if (req == null) return;
      if (req.status == 'approved') {
        throw Exception('طلبٌ مُعتمَدٌ لا يُلغى — الأصلُ خرج من الدفاتر');
      }
      await (update(assetDisposals)..where((d) => d.id.equals(id))).write(
        AssetDisposalsCompanion(
          status: const Value('cancelled'),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// 🔴 **يعتمد الطلبَ — وهنا وحدَه يقع الأثرُ المحاسبيّ.**
  ///
  /// القيدُ:
  /// ```
  ///   مدين  مجمَّعُ الإهلاك          = المجمَّعُ المُرحَّل
  ///   مدين  الخزنة / حسابُ العميل    = قيمةُ البيع   (البيعُ وحدَه)
  ///   مدين  خسائرُ بيع أصول (642)    = الفرقُ سالباً
  ///       دائن  الأصلُ الثابت         = التكلفةُ الأصليّة
  ///       دائن  أرباحُ بيع أصول (4314) = الفرقُ موجباً
  /// ```
  ///
  /// و**يُرمى قبل أن يُمَسَّ شيءٌ** إن غاب أيُّ حسابٍ من هذه — راجع رأسَ
  /// الملفّ، البند ٣.
  /// [safeId] لازمٌ للبيع النقديِّ وحدَه.
  ///
  /// ⚠️ **ولماذا عند الاعتماد لا في الطلب**: `AssetDisposals` كما صُمّمت في
  ///    v174 بلا عمودِ خزنة، والخزنةُ قرارُ **لحظةِ الاعتماد** — مَن يعتمد
  ///    هو مَن يعرف أيُّ درجٍ استلم المال. وإضافةُ عمودٍ لتخزين نيّةٍ قد
  ///    تتغيّر تحتاج هجرةً بلا مقابل.
  Future<void> approveAssetDisposal(
    int id, {
    int? safeId,
    int? approvedBy,
    String? approvedByName,
  }) async {
    await transaction(() async {
      final req = await getAssetDisposal(id);
      if (req == null) throw Exception('الطلب غير موجود');
      if (req.status != 'draft') {
        throw Exception('طلبٌ ${_disposalStatusWord(req.status)} لا يُعتمَد');
      }

      // ⚠️ **يُعاد الفحصُ على الحيّ**: ترحيلُ إهلاكٍ بين حفظِ المسوّدة
      //    واعتمادِها يغيّر المجمَّعَ والقيمةَ الدفتريّة، وقد يكون الأصلُ
      //    استُبعد من مسارٍ آخرَ أصلاً.
      final asset = await _disposalAsset(req.assetId);
      _assertRawDisposalSane(
        asset: asset,
        method: req.method,
        disposalValue: req.disposalValue,
        collectionMethod: req.collectionMethod,
        buyerPartyId: req.buyerPartyId,
        reason: req.notes ?? '',
        safeId: safeId,
      );

      final outcome = computeDisposalOutcome(
        originalCost: asset.purchasePrice,
        accumulatedDepreciation: asset.accumulatedDepreciation,
        disposalValue: req.disposalValue,
      );

      // ── الحسابات: كلُّها أو لا شيء ──────────────────────────────────
      final cat = await _disposalCategoryAccounts(asset.categoryId);
      final assetAccount = cat.asset;
      final accumAccount = cat.accum;

      final lines = <JournalLine>[
        JournalLine(
          accountId: accumAccount.id,
          debit: asset.accumulatedDepreciation,
          credit: 0,
          description: 'إقفال مجمع الإهلاك',
        ),
        JournalLine(
          accountId: assetAccount.id,
          debit: 0,
          credit: asset.purchasePrice,
          description: 'تكلفة الأصل',
        ),
      ];

      int? safeTxnId;
      if (disposalCarriesProceeds(req.method) && req.disposalValue > 0) {
        if (req.collectionMethod == 'credit') {
          final ar = await _disposalReceivableAccount(req.buyerPartyId);
          if (ar == null) {
            throw Exception('حسابُ ذمم العملاء غير مُعرَّف — لا تُحمَّل ذمّة');
          }
          lines.add(JournalLine(
            accountId: ar.id,
            debit: req.disposalValue,
            credit: 0,
            description: 'ذمّة بيع أصل',
          ));
          // 🔴 الذمّةُ في الأستاذ وحدَها لا تُطالِب أحداً — رصيدُ الطرف
          //    هو ما تقرؤه كشوفُ الحساب وحدُّ الائتمان.
          await adjustPartyBalance(
            req.buyerPartyId!,
            req.disposalValue,
            changedBy: approvedBy ?? 0,
            changedByName: approvedByName ?? 'SYSTEM',
            changeReason: 'بيع أصل ${req.disposalNumber}',
          );
        } else {
          // الفحصُ أعلاه رفض `safeId == null` سلفاً؛ وهذا حارسُ نوعٍ لا حكم.
          if (safeId == null) throw Exception('اختر الخزينة قبل الاعتماد');
          final safe = await (select(safes)..where((s) => s.id.equals(safeId)))
              .getSingleOrNull();
          if (safe == null) throw Exception('الخزينة غير موجودة');

          // 🔴 **حسابُ الخزنة المرتبطُ لا `1111` عمياء**: خزائنُ الفروع لها
          //    حساباتٌ فرعيّةٌ، وقيدٌ على الصندوق الرئيسيِّ يُنسَب المالَ إلى
          //    درجٍ لم يدخله.
          final cashAccount = safe.linkedAccountId != null
              ? await accountingDao.getAccountById(safe.linkedAccountId!)
              : await _assetGetAccountByCode('1111');
          if (cashAccount == null) {
            throw Exception('الخزينة بلا حسابٍ مرتبطٍ ولا حسابَ نقديّةٍ بديل');
          }
          lines.add(JournalLine(
            accountId: cashAccount.id,
            debit: req.disposalValue,
            credit: 0,
            description: 'متحصلات بيع أصل',
          ));

          // 🔴 **وحركةُ الخزنة مع القيد** — راجع رأسَ الملفّ، البند ١.
          safeTxnId = await createSafeTransaction(
            SafeTransactionsCompanion.insert(
              voucherNumber: req.disposalNumber,
              safeId: safe.id,
              transactionType: 'receipt',
              category: 'asset_disposal',
              amount: req.disposalValue,
              balanceAfter: safe.balance + req.disposalValue,
              partyId: Value(req.buyerPartyId),
              description: Value('بيع أصل: ${asset.name}'),
              userId: Value(approvedBy),
              costCenterId: Value(req.costCenterId),
              globalId: Value(UuidV7.generate()),
            ),
          );
        }
      }

      if (outcome.gainLoss > 0) {
        final gain = await _assetGetAccountByCode('4314');
        if (gain == null) {
          throw Exception('حساب أرباح بيع الأصول (4314) غير موجود');
        }
        lines.add(JournalLine(
          accountId: gain.id,
          debit: 0,
          credit: outcome.gainLoss,
          description: 'أرباح بيع أصل',
        ));
      } else if (outcome.gainLoss < 0) {
        final loss = await _assetGetAccountByCode('642');
        if (loss == null) {
          throw Exception('حساب خسائر بيع الأصول (642) غير موجود');
        }
        lines.add(JournalLine(
          accountId: loss.id,
          debit: -outcome.gainLoss,
          credit: 0,
          description: '${disposalMethodLabel(req.method)} أصل — خسارة',
        ));
      }

      await accountingDao.createJournalEntry(
        date: req.disposalDate,
        description:
            '${disposalMethodLabel(req.method)} أصل: ${asset.name} '
            '(${req.disposalNumber})',
        lines: lines,
        referenceType: 'fixed_asset_disposal',
        referenceId: asset.id,
        isAutoPosted: true,
        costCenterId: req.costCenterId,
        branchId: await _resolveBranchFromCostCenter(req.costCenterId),
      );

      // 🔴 **البيعُ `sold` وما عداه `disposed`** — سبعةُ مواضعِ قراءةٍ كانت
      //    ميّتةً لأنّ `disposeAsset` تكتب `'disposed'` دائماً.
      await (update(fixedAssets)..where((a) => a.id.equals(asset.id))).write(
        FixedAssetsCompanion(
          status: Value(assetStatusAfterDisposal(req.method)),
          disposalDate: Value(req.disposalDate),
          disposalValue: Value(req.disposalValue),
        ),
      );

      await (update(assetDisposals)..where((d) => d.id.equals(id))).write(
        AssetDisposalsCompanion(
          status: const Value('approved'),
          approvedBy: Value(approvedBy),
          approvedAt: Value(DateTime.now()),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );

      debugPrint('[AssetDisposal] ${req.disposalNumber} approved — '
          'safeTxn=$safeTxnId gainLoss=${outcome.gainLoss}');
    });
  }

  // ───────────────────────────────────────────────────────────────────────
  // أدواتٌ داخليّة
  // ───────────────────────────────────────────────────────────────────────

  Future<FixedAssetData> _disposalAsset(int assetId) async {
    final asset = await (select(fixedAssets)..where((a) => a.id.equals(assetId)))
        .getSingleOrNull();
    if (asset == null) throw Exception('الأصل غير موجود');
    return asset;
  }

  /// [safeId] — الصفرُ (الافتراضيّ) يعني «لا تُفحَص هنا»: المسوّدةُ لا
  /// تختار خزنةً، والاختيارُ يقع عند الاعتماد فيُمرَّر هناك.
  void _assertRawDisposalSane({
    required FixedAssetData asset,
    required String method,
    required double disposalValue,
    required String collectionMethod,
    required int? buyerPartyId,
    required String reason,
    int? safeId = 0,
  }) {
    final error = validateAssetDisposal(
      method: method,
      disposalValue: disposalValue,
      collectionMethod: collectionMethod,
      buyerPartyId: buyerPartyId,
      safeId: safeId,
      reason: reason,
      assetStatus: asset.status,
    );
    if (error != null) throw Exception(error);
  }

  /// 🔴 حسابا الفئة **صريحان أو لا اعتماد**.
  ///
  /// `_getCategoryAssetAccount` و`_getCategoryDepreciationAccount` **تسقطان
  /// إلى `1211` (الأراضي) و`1218` (مجمّع إهلاك المباني)** حين لا تحمل الفئةُ
  /// حساباً. وذلك احتياطٌ مقبولٌ في ترحيلِ إهلاكٍ شهريٍّ يُصحَّح لاحقاً —
  /// **ولا يُقبَل في الاستبعاد**: القيدُ يُقفل الأصلَ نهائيّاً، فيُدائَن
  /// «الأراضي» بتكلفة حاسوبٍ ويُمدَن «مجمّعُ إهلاك المباني» بمجمَّعه، وتبقى
  /// الميزانيّةُ مُحرَّفةً بلا أثرٍ يدلّ على الخطأ.
  ///
  /// وفئاتُ PicPos كلُّها تحمل الحسابَين (شاشةُ «فئات الأصول» تشترطهما)،
  /// فالرفضُ هنا لا يمسّ إلّا فئةً قديمةً أو مبذورةً بلا ربط.
  Future<({Account asset, Account accum})> _disposalCategoryAccounts(
      int categoryId) async {
    final cat = await (select(assetCategories)
          ..where((c) => c.id.equals(categoryId))
          ..limit(1))
        .getSingleOrNull();
    final assetAccId = cat?.accountId;
    final accumAccId = cat?.depreciationAccountId;
    if (assetAccId == null || accumAccId == null) {
      throw Exception(
          'فئةُ الأصل بلا حسابِ أصلٍ أو حسابِ مجمَّعِ إهلاك — اربطهما من '
          'شاشة «فئات الأصول» قبل الاستبعاد');
    }
    final assetAcc = await accountingDao.getAccountById(assetAccId);
    final accumAcc = await accountingDao.getAccountById(accumAccId);
    if (assetAcc == null || accumAcc == null) {
      throw Exception('حسابُ الفئة غير موجودٍ في دليل الحسابات');
    }
    return (asset: assetAcc, accum: accumAcc);
  }

  /// حسابُ ذمم المشتري الفرعيُّ، أو حسابُ التحكّم.
  Future<Account?> _disposalReceivableAccount(int? partyId) async {
    final control = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode(
          'receivables', AccountingDao.accountPurposes['receivables']!),
    );
    if (partyId == null) return control;
    final party = await (select(parties)..where((p) => p.id.equals(partyId)))
        .getSingleOrNull();
    if (party?.accountId == null) return control;
    return await accountingDao.getAccountById(party!.accountId!) ?? control;
  }
}

String _disposalStatusWord(String status) => switch (status) {
      'approved' => 'مُعتمَد',
      'cancelled' => 'ملغى',
      _ => status,
    };
