part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FIXED ASSETS DAO — الأصول الثابتة والإهلاك
// ═══════════════════════════════════════════════════════════════════════════

extension FixedAssetsDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // ASSET CATEGORIES
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all asset categories
  Stream<List<AssetCategory>> watchAssetCategories() {
    return select(assetCategories).watch();
  }

  /// Create asset category
  ///
  /// Feature 050 (v132): both `accountId` (asset acquisition account) and
  /// `depreciationAccountId` (accumulated depreciation account) are
  /// **required** at creation time. A category with either field null can
  /// never be used to create an asset — `createFixedAsset` always throws
  /// `MissingCategoryAccountException` further downstream, after the user
  /// has already filled out a long asset form. Reject at the source so
  /// no broken row can be inserted in the first place.
  ///
  /// Update path ([updateAssetCategoryById]) keeps its existing
  /// "absent = leave the column alone" semantics so admins can rename a
  /// category without re-picking its accounts.
  Future<int> createAssetCategory({
    required String name,
    double defaultUsefulLife = 5,
    String defaultDepreciationMethod = 'straight_line',
    int? accountId,
    int? depreciationAccountId,
    /// v166 — يُمرَّر حين يُعيد الخادمُ بناءَ فئةٍ سكّها عميل، فتحمل
    /// الهويّةَ نفسَها على الجهازين ولا تتضاعف عند سحب الدلتا.
    String? globalId,
  }) async {
    if (accountId == null || depreciationAccountId == null) {
      throw Exception(
        'اختر حساب الأصل وحساب مجمع الإهلاك للفئة قبل الحفظ.',
      );
    }
    final id = await into(assetCategories).insert(
      AssetCategoriesCompanion.insert(
        name: name,
        defaultUsefulLife: Value(defaultUsefulLife),
        defaultDepreciationMethod: Value(defaultDepreciationMethod),
        accountId: Value(accountId),
        depreciationAccountId: Value(depreciationAccountId),
        globalId: Value(globalId ?? UuidV7.generate()),
      ),
    );
    // Feature 014 / Issue 5 — explicit notification so the
    // categories tab StreamBuilder picks up the row immediately
    // instead of waiting for a screen re-entry. Drift normally
    // propagates inserts via the table's auto-watch, but the
    // explicit call is a cheap insurance against silent stream
    // staleness reported in the field.
    markTablesUpdated({assetCategories});
    return id;
  }

  /// Get all asset categories as a list
  Future<List<AssetCategory>> getAssetCategoriesList() =>
      select(assetCategories).get();

  /// Update asset category by ID
  ///
  /// Feature 052 (v132): `defaultUsefulLife` and `defaultDepreciationMethod`
  /// are now also editable. They only affect the **defaults pre-filled into
  /// the create-asset dialog** for new assets under this category — past
  /// assets are not retro-modified. All four optional params follow the
  /// same "null = leave column alone" semantics (Drift `Value.absent()`).
  Future<void> updateAssetCategoryById(
    int id, {
    required String name,
    int? accountId,
    int? depreciationAccountId,
    double? defaultUsefulLife,
    String? defaultDepreciationMethod,
  }) async {
    await (update(assetCategories)..where((c) => c.id.equals(id)))
        .write(AssetCategoriesCompanion(
          name: Value(name),
          accountId: accountId != null ? Value(accountId) : const Value.absent(),
          depreciationAccountId: depreciationAccountId != null
              ? Value(depreciationAccountId)
              : const Value.absent(),
          defaultUsefulLife: defaultUsefulLife != null
              ? Value(defaultUsefulLife)
              : const Value.absent(),
          defaultDepreciationMethod: defaultDepreciationMethod != null
              ? Value(defaultDepreciationMethod)
              : const Value.absent(),
        ));
    // Feature 014 / Issue 5 — see createAssetCategory above.
    markTablesUpdated({assetCategories});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIXED ASSETS CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all fixed assets
  Stream<List<FixedAssetData>> watchFixedAssets({String? status}) {
    final q = select(fixedAssets)..orderBy([(a) => OrderingTerm.asc(a.name)]);
    if (status != null) q.where((a) => a.status.equals(status));
    return q.watch();
  }

  /// Get a single fixed asset by ID
  Future<FixedAssetData?> getFixedAssetById(int id) {
    return (select(fixedAssets)..where((a) => a.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get all fixed assets as a list
  Future<List<FixedAssetData>> getFixedAssetsList() =>
      select(fixedAssets).get();

  /// Create a fixed asset + acquisition journal entry
  Future<int> createFixedAsset({
    required String code,
    required String name,
    required int categoryId,
    String? location,
    required double purchasePrice,
    required DateTime purchaseDate,
    required double usefulLifeYears,
    double salvageValue = 0,
    String depreciationMethod = 'straight_line',
    String? notes,
    int? costCenterId,
    int? contraAccountId, // Optional: overrides default cash/bank credit account
    /// v166 — هويّةُ الأصل. تُسَكّ هنا حين تكون `null`، وتُمرَّر حين
    /// يُنفّذ الخادمُ نداءَ عميلٍ سكّها بالفعل.
    String? globalId,
    /// v166 — وهويّةُ حسابه الفرعيِّ في شجرة الحسابات. منفصلةٌ لأنّ
    /// الصفَّين جدولان مختلفان يُزامَنان استقلالاً.
    String? linkedAccountGlobalId,
  }) async {
    // Feature 004 (US3, FR-023b) — fail fast before opening the transaction
    // when the elevated-admin session has lost the server connection. The
    // alternative (enqueue or silently no-op) would mislead the user about
    // whether the asset was created.
    final guard = MutationGuard.current;
    if (!guard.canMutate) {
      throw MutationDeniedException(guard.reason);
    }
    // Ensure fixed-asset GL accounts exist before use (idempotent — outside transaction)
    await accountingDao.syncDefaultAccounts();

    final createdId = await transaction(() async {
      // ── Feature 004 (US1): atomic per-asset CoA sub-account linkage ──
      //
      // Resolve the category's existing asset account first — it serves as
      // the PARENT under which we mint a per-asset sub-account. If the
      // category has no `accountId` set, fail closed (FR-005): no asset row,
      // no account row, no JE.
      final categoryRow = await (select(assetCategories)
            ..where((c) => c.id.equals(categoryId))
            ..limit(1))
          .getSingleOrNull();
      if (categoryRow == null) {
        throw Exception('فئة الأصل برقم $categoryId غير موجودة.');
      }
      if (categoryRow.accountId == null) {
        throw MissingCategoryAccountException(categoryId, categoryRow.name);
      }
      final parentAccount = await (select(accounts)
            ..where((a) => a.id.equals(categoryRow.accountId!))
            ..limit(1))
          .getSingleOrNull();
      if (parentAccount == null) {
        throw MissingCategoryAccountException(categoryId, categoryRow.name);
      }

      // Compute deterministic sub-account code under the category's account.
      final suffix = await _nextAccountSuffix(parentAccount.id);
      final accountCode =
          '${parentAccount.code}-${suffix.toString().padLeft(5, '0')}';

      // Feature 014 / Issue 6 — defensive `.limit(1)` so the existence
      // check never throws "Bad state: too many elements" when the
      // accounts table has duplicate codes (legacy data, partial sync).
      // Any duplicate code is, by itself, the failure we care about
      // here — we just need to know IF a row exists, not how many.
      final dupAcc = await (select(accounts)
            ..where((a) => a.code.equals(accountCode))
            ..limit(1))
          .getSingleOrNull();
      if (dupAcc != null) {
        throw Exception(
          'كود الحساب الفرعى "$accountCode" مستخدم بالفعل — '
          'تحقق من دليل الحسابات.',
        );
      }

      // Mint the per-asset sub-account.
      final perAssetAccountId = await into(accounts).insert(
        AccountsCompanion.insert(
          code: accountCode,
          name: name,
          accountType: parentAccount.accountType,
          parentId: Value(parentAccount.id),
          isSystem: const Value(false),
          globalId: Value(linkedAccountGlobalId ?? UuidV7.generate()),
        ),
      );

      // Insert the asset row carrying the new globalId + linkedAccountId.
      final assetId = await into(fixedAssets).insert(
        FixedAssetsCompanion.insert(
          code: code,
          name: name,
          categoryId: categoryId,
          location: Value(location),
          purchasePrice: purchasePrice,
          purchaseDate: purchaseDate,
          usefulLifeYears: usefulLifeYears,
          salvageValue: Value(salvageValue),
          depreciationMethod: Value(depreciationMethod),
          notes: Value(notes),
          costCenterId: Value(costCenterId),
          linkedAccountId: Value(perAssetAccountId),
          globalId: Value(globalId ?? UuidV7.generate()),
        ),
      );

      // ── Acquisition JE — UNCHANGED (Constitution I, behavior preservation)
      //
      // The per-asset sub-account above is created and linked but does NOT
      // receive the acquisition entry in v1. The acquisition JE continues to
      // debit the CATEGORY's asset account exactly as before so existing
      // fixed-asset reports keep their numbers identical across the cohort
      // boundary. Per-asset GL flows are deferred to a future spec.
      Account? creditAccount;
      if (contraAccountId != null) {
        creditAccount = await accountingDao.getAccountById(contraAccountId);
      }
      creditAccount ??= await _assetGetAccountByCode('1111');

      // v166 — العميلُ لا يُرحّل: `referenceId` هنا رقمُ الأصل **المحلّيّ**،
      // ومفتاحُ إزالة تكرار القيد `(referenceType, referenceId)`. فلو رحّل
      // الطرفان لصار للاقتناء الواحد قيدان لا يمسكهما شيءٌ لأنّ مفتاحَيهما
      // مختلفان — وأصلٌ يظهر في الأستاذ بضعف قيمته.
      if (creditAccount != null && !SyncInterceptor.isClientMode) {
        await accountingDao.createJournalEntry(
          date: purchaseDate,
          description: 'شراء أصل ثابت: $name',
          lines: [
            JournalLine(
              accountId: parentAccount.id,
              debit: purchasePrice,
              credit: 0,
              description: 'أصول ثابتة',
            ),
            JournalLine(
              accountId: creditAccount.id,
              debit: 0,
              credit: purchasePrice,
              description: 'مقابل شراء الأصل',
            ),
          ],
          referenceType: 'fixed_asset',
          referenceId: assetId,
          isAutoPosted: true,
          costCenterId: costCenterId,
          branchId: await _resolveBranchFromCostCenter(costCenterId),
        );
      }

      return assetId;
    });

    // خارجَ المعاملة عمداً — انظر [_pushFixedAssetCreate].
    await _pushFixedAssetCreate(createdId);
    return createdId;
  }

  /// v166 — يُرسل اقتناءَ الأصل إلى الخادم ليُرحّله هو.
  ///
  /// يُنادى **بعد** التزام المعاملة لا داخلَها: نداءُ HTTP داخلَ معاملةٍ
  /// يحجز قفلَ الكتابة طوالَ زمن الشبكة (‏نفسُ علاج `SqliteException 517`
  /// في `accounting_dao_writes`).
  Future<void> _pushFixedAssetCreate(int assetId) async {
    if (!SyncInterceptor.isClientMode) return;
    final asset = await (select(fixedAssets)
          ..where((a) => a.id.equals(assetId)))
        .getSingleOrNull();
    if (asset == null) return;

    final category = await (select(assetCategories)
          ..where((c) => c.id.equals(asset.categoryId)))
        .getSingleOrNull();
    final linkedAccount = asset.linkedAccountId == null
        ? null
        : await (select(accounts)
              ..where((a) => a.id.equals(asset.linkedAccountId!)))
            .getSingleOrNull();
    final costCenter = asset.costCenterId == null
        ? null
        : await (select(costCenters)
              ..where((c) => c.id.equals(asset.costCenterId!)))
            .getSingleOrNull();

    await SyncInterceptor.instance?.submitFixedAssetCreate(<String, dynamic>{
      'globalId': asset.globalId,
      'linkedAccountGlobalId': linkedAccount?.globalId,
      'code': asset.code,
      'name': asset.name,
      // الفئةُ تُرسَل كاملةً لا بمعرّفها وحدَه: فئةٌ أنشأها هذا الجهازُ لا
      // وجودَ لها على الخادم، ولو أرسلنا المعرّفَ فقط لرُدَّ الأصلُ أبداً.
      'category': category == null
          ? null
          : <String, dynamic>{
              'globalId': category.globalId,
              'name': category.name,
              'defaultUsefulLife': category.defaultUsefulLife,
              'defaultDepreciationMethod':
                  category.defaultDepreciationMethod,
            },
      'location': asset.location,
      'purchasePrice': asset.purchasePrice,
      'purchaseDate': asset.purchaseDate.toIso8601String(),
      'usefulLifeYears': asset.usefulLifeYears,
      'salvageValue': asset.salvageValue,
      'depreciationMethod': asset.depreciationMethod,
      'notes': asset.notes,
      'costCenterGlobalId': costCenter?.globalId,
    });
  }

  /// Update fixed asset details (IAS 16).
  /// Feature 004 (US1, FR-006): rename propagates to the linked CoA sub-account
  /// atomically inside a transaction. The "manually-overridden account name"
  /// guard mentioned in FR-006 is deferred to a follow-up spec; this
  /// implementation always propagates a non-null name change.
  Future<void> updateFixedAsset(
    int assetId, {
    String? name,
    String? location,
    double? salvageValue,
    String? notes,
    int? costCenterId,
    bool clearCostCenter = false,
  }) async {
    final companion = FixedAssetsCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      location: location != null ? Value(location) : const Value.absent(),
      salvageValue: salvageValue != null ? Value(salvageValue) : const Value.absent(),
      notes: notes != null ? Value(notes) : const Value.absent(),
      costCenterId: costCenterId != null || clearCostCenter ? Value(costCenterId) : const Value.absent(),
    );
    await transaction(() async {
      // Read current name + linkedAccountId before mutation so we can detect
      // a real rename and propagate it.
      final current = await (select(fixedAssets)
            ..where((a) => a.id.equals(assetId))
            ..limit(1))
          .getSingleOrNull();

      await (update(fixedAssets)..where((a) => a.id.equals(assetId)))
          .write(companion);

      if (current != null && name != null && current.name != name && current.linkedAccountId != null) {
        await (update(accounts)..where((a) => a.id.equals(current.linkedAccountId!)))
            .write(AccountsCompanion(name: Value(name)));
      }
    });
  }

  /// Delete a fixed asset.
  ///
  /// Feature 004 (US1, FR-007): rejects deletion when the asset's linked
  /// CoA sub-account has any journal-entry lines (acquisition / depreciation).
  /// Returns the number of rows deleted (0 if the asset didn't exist; throws
  /// when the GL guard fires).
  Future<int> deleteFixedAsset(int assetId) async {
    return transaction(() async {
      final asset = await (select(fixedAssets)
            ..where((a) => a.id.equals(assetId))
            ..limit(1))
          .getSingleOrNull();
      if (asset == null) return 0;

      if (asset.linkedAccountId != null) {
        final row = await customSelect(
          'SELECT COUNT(*) AS c FROM journal_entry_lines WHERE account_id = ?',
          variables: [Variable.withInt(asset.linkedAccountId!)],
        ).getSingle();
        final count = row.read<int>('c');
        if (count > 0) {
          throw Exception(
            'لا يمكن حذف الأصل "${asset.name}" لأن الحساب المرتبط به '
            'يحتوى على قيود محاسبية ($count قيد). يرجى تصفية الحركات أولاً.',
          );
        }
      }

      return (delete(fixedAssets)..where((a) => a.id.equals(assetId))).go();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEPRECIATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Calculate and post monthly depreciation for all active assets
  Future<int> runMonthlyDepreciation(DateTime periodDate, {int? costCenterId}) async {
    // v166 — على عميلٍ: يُطلَب من الخادم ولا يُحسَب هنا.
    //
    // الترحيلُ دفعةٌ على **كلّ** أصلٍ نشط، ومفتاحُ إزالة التكرار داخلَ
    // القاعدة `(assetId, periodDate)` يحمي القاعدةَ الواحدةَ لا الاثنتين.
    // فجهازان يشغّلانه لنفس الشهر يُنتجان مجموعتَي قيودٍ كاملتَين على
    // الخادم — إهلاكٌ مضاعفٌ لشهرٍ واحد. ولذلك الطالبُ واحدٌ والمنفّذُ واحد.
    //
    // ويُرسَل التاريخُ لا قائمةُ الأصول: قائمةُ العميل قد تنقص أصولاً لم
    // تصله بعد، والخادمُ يعرف أصولَه كلَّها.
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.submitAssetDepreciationRun(
        <String, dynamic>{
          'periodDate': periodDate.toIso8601String(),
          'costCenterId': costCenterId,
        },
      );
      // صفرٌ صادق: هذا الجهازُ لم يُرحّل شيئاً. والعددُ الحقيقيُّ يظهر
      // بصفوف الإهلاك حين تصل بسحب الدلتا.
      return 0;
    }

    int count = 0;
    // Ensure all required GL accounts (6213, 1218, 1219, …) exist before looping.
    await accountingDao.syncDefaultAccounts();
    final activeAssets = await (select(
      fixedAssets,
    )..where((a) => a.status.equals('active'))).get();

    for (final asset in activeAssets) {
      // Check if already depreciated for this month
      final existing =
          await (select(assetDepreciations)
                ..where((d) => d.assetId.equals(asset.id))
                ..where((d) => d.periodDate.equals(periodDate)))
              .getSingleOrNull();
      if (existing != null) continue;

      final depreciableAmount = asset.purchasePrice - asset.salvageValue;
      double monthlyDepreciation;

      if (asset.depreciationMethod == 'declining_balance') {
        // Double declining balance
        final rate = 2 / (asset.usefulLifeYears * 12);
        final bookValue = asset.purchasePrice - asset.accumulatedDepreciation;
        monthlyDepreciation = bookValue * rate;
        if (asset.accumulatedDepreciation + monthlyDepreciation >
            depreciableAmount) {
          monthlyDepreciation =
              depreciableAmount - asset.accumulatedDepreciation;
        }
      } else {
        // Straight-line
        monthlyDepreciation = depreciableAmount / (asset.usefulLifeYears * 12);
      }

      if (monthlyDepreciation <= 0) continue;

      final newAccumulated =
          asset.accumulatedDepreciation + monthlyDepreciation;
      final newBookValue = asset.purchasePrice - newAccumulated;

      // All three writes are atomic: journal entry + depreciation record + asset update.
      // Each asset commits independently — a failure here skips only this asset.
      try {
        await transaction(() async {
          // Auto-post: Dr: 6213 مصروفات الإهلاك - إداري, Cr: مجمع إهلاك (category account)
          int? journalEntryId;
          final depExpenseAccount = await _assetGetAccountByCode('6213');
          final accumDepAccount = await _getCategoryDepreciationAccount(asset.categoryId);
          if (depExpenseAccount != null && accumDepAccount != null) {
            journalEntryId = await accountingDao.createJournalEntry(
              date: periodDate,
              description:
                  'إهلاك أصل: ${asset.name} — ${periodDate.month}/${periodDate.year}',
              lines: [
                JournalLine(
                  accountId: depExpenseAccount.id,
                  debit: monthlyDepreciation,
                  credit: 0,
                  description: 'مصروف إهلاك',
                ),
                JournalLine(
                  accountId: accumDepAccount.id,
                  debit: 0,
                  credit: monthlyDepreciation,
                  description: 'مجمع إهلاك',
                ),
              ],
              referenceType: 'asset_depreciation',
              referenceId: asset.id,
              isAutoPosted: true,
              costCenterId: costCenterId,
              branchId: await _resolveBranchFromCostCenter(costCenterId),
            );
          }

          // Record depreciation entry
          await into(assetDepreciations).insert(
            AssetDepreciationsCompanion.insert(
              assetId: asset.id,
              periodDate: periodDate,
              depreciationAmount: monthlyDepreciation,
              accumulatedDepreciation: newAccumulated,
              bookValue: newBookValue,
              journalEntryId: Value(journalEntryId),
              // v166 — الصفُّ يُزامَن، فيحتاج هويّةً. والمفتاحُ الطبيعيُّ
              // `(assetId, periodDate)` يمنع التكرارَ داخلَ القاعدة، لكنّه
              // لا يُغني عن هويّةٍ تعبر الأجهزة.
              globalId: Value(UuidV7.generate()),
            ),
          );

          // Update asset accumulated depreciation
          await (update(fixedAssets)..where((a) => a.id.equals(asset.id))).write(
            FixedAssetsCompanion(accumulatedDepreciation: Value(newAccumulated)),
          );
        });
        count++;
      } catch (e) {
        // Log and continue — already-processed assets are not rolled back
        debugPrint('runMonthlyDepreciation: failed for asset ${asset.id} (${asset.name}): $e');
      }
    }
    return count;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPOSAL, TRANSFER & REVALUATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Dispose of an asset (sell or write-off)
  Future<void> disposeAsset(
    int assetId, {
    required double disposalValue,
    required DateTime disposalDate,
    int? costCenterId,
  }) async {
    await transaction(() async {
      final asset = await (select(
        fixedAssets,
      )..where((a) => a.id.equals(assetId))).getSingleOrNull();
      if (asset == null) throw Exception('الأصل غير موجود');

      final bookValue = asset.purchasePrice - asset.accumulatedDepreciation;
      final gainLoss = disposalValue - bookValue;

      // Update asset status
      await (update(fixedAssets)..where((a) => a.id.equals(assetId))).write(
        FixedAssetsCompanion(
          status: const Value('disposed'),
          disposalDate: Value(disposalDate),
          disposalValue: Value(disposalValue),
        ),
      );

      // Auto-post disposal journal entry
      final fixedAssetAccount = await _getCategoryAssetAccount(asset.categoryId);
      final accumDepAccount = await _getCategoryDepreciationAccount(asset.categoryId);
      final cashAccount = await _assetGetAccountByCode('1111');

      if (fixedAssetAccount != null &&
          accumDepAccount != null &&
          cashAccount != null) {
        final lines = <JournalLine>[
          // Debit: Cash (disposal value)
          if (disposalValue > 0)
            JournalLine(
              accountId: cashAccount.id,
              debit: disposalValue,
              credit: 0,
              description: 'قيمة بيع الأصل',
            ),
          // Debit: Accumulated depreciation
          JournalLine(
            accountId: accumDepAccount.id,
            debit: asset.accumulatedDepreciation,
            credit: 0,
            description: 'مجمع إهلاك',
          ),
          // Credit: Fixed asset (original cost)
          JournalLine(
            accountId: fixedAssetAccount.id,
            debit: 0,
            credit: asset.purchasePrice,
            description: 'تكلفة الأصل',
          ),
        ];

        // Handle gain/loss
        if (gainLoss > 0) {
          final revenueAccount = await _assetGetAccountByCode('4314'); // أرباح بيع أصول ثابتة
          if (revenueAccount != null) {
            lines.add(
              JournalLine(
                accountId: revenueAccount.id,
                debit: 0,
                credit: gainLoss,
                description: 'أرباح بيع أصل',
              ),
            );
          }
        } else if (gainLoss < 0) {
          final expenseAccount = await _assetGetAccountByCode('642'); // خسائر بيع أصول ثابتة
          if (expenseAccount != null) {
            lines.add(
              JournalLine(
                accountId: expenseAccount.id,
                debit: -gainLoss,
                credit: 0,
                description: 'خسائر بيع أصل',
              ),
            );
          }
        }

        await accountingDao.createJournalEntry(
          date: disposalDate,
          description: 'استبعاد أصل: ${asset.name}',
          lines: lines,
          referenceType: 'fixed_asset_disposal',
          referenceId: assetId,
          isAutoPosted: true,
          costCenterId: costCenterId,
          branchId: await _resolveBranchFromCostCenter(costCenterId), 
        );
      }
    });
  }

  /// Get depreciation schedule for an asset
  Future<List<AssetDepreciationData>> getAssetDepreciationSchedule(
    int assetId,
  ) {
    return (select(assetDepreciations)
          ..where((d) => d.assetId.equals(assetId))
          ..orderBy([(d) => OrderingTerm.asc(d.periodDate)]))
        .get();
  }

  /// Get asset summary: total value, accumulated depreciation, book value
  Future<Map<String, double>> getAssetsSummary() async {
    final assets = await (select(
      fixedAssets,
    )..where((a) => a.status.equals('active'))).get();

    double totalCost = 0, totalDepreciation = 0, totalBookValue = 0;
    for (final a in assets) {
      totalCost += a.purchasePrice;
      totalDepreciation += a.accumulatedDepreciation;
      totalBookValue += a.purchasePrice - a.accumulatedDepreciation;
    }

    return {
      'totalCost': totalCost,
      'totalDepreciation': totalDepreciation,
      'totalBookValue': totalBookValue,
      'assetCount': assets.length.toDouble(),
    };
  }

  /// Transfer asset to a different cost center (IAS 16.73e)
  Future<void> transferAsset(
    int assetId, {
    required int newCostCenterId,
    required int fromCostCenterId,
    int? costCenterId,
  }) async {
    await transaction(() async {
      final asset = await (select(fixedAssets)..where((a) => a.id.equals(assetId))).getSingleOrNull();
      if (asset == null) throw Exception('الأصل غير موجود');
      if (asset.status != 'active') throw Exception('لا يمكن تحويل أصل غير نشط');

      final bookValue = asset.purchasePrice - asset.accumulatedDepreciation;

      // المصدرُ يأتي من المنادي ثقةً، والبطاقةُ تعرف مركزَها الحقيقيّ. فلو
      // تناقضا لأخرج الطرفُ الدائنُ أدناه القيمةَ من مركزٍ لم يحملها قطّ،
      // وبقي المركزُ الحقيقيُّ حاملاً أصلاً غادره — بلا أثرٍ في ميزان
      // المراجعة لأنّ الطرفَين في نفس الحساب. يُرفَض قبل أيّ كتابة.
      if (asset.costCenterId != fromCostCenterId) {
        final current = asset.costCenterId == null
            ? 'بلا مركز تكلفة'
            : '#${asset.costCenterId}';
        throw Exception(
          'مركزُ التكلفة المصدر (#$fromCostCenterId) لا يطابق مركزَ الأصل '
          'الحاليّ ($current) — حدِّث بطاقةَ الأصل أوّلاً.',
        );
      }

      // Update the asset's cost center reference
      //
      // 🔴 `costCenterId` كان غائباً عن هذه الكتابة بينما القيدُ أدناه ينقل
      // القيمةَ الدفتريّةَ بين المركزَين في الأستاذ ⇒ بطاقةٌ في مركزٍ ودفترٌ
      // في آخر، وكلُّ تقريرٍ يجمع الأصولَ بمركز التكلفة يخالف الدفتر.
      // الحارس: `test/unit/asset_transfer_moves_its_cost_center_test.dart`.
      await (update(fixedAssets)..where((a) => a.id.equals(assetId)))
          .write(FixedAssetsCompanion(
            costCenterId: Value(newCostCenterId),
            notes: Value('محوّل إلى مركز تكلفة #$newCostCenterId — القيمة الدفترية: ${bookValue.toStringAsFixed(AppConstants.decimalPlaces)}'),
          ));

      // Journal entry: Dr Fixed Assets (new CC) / Cr Fixed Assets (old CC)
      final assetAccount = await _getCategoryAssetAccount(asset.categoryId);
      if (assetAccount != null) {
        await accountingDao.createJournalEntry(
          description: 'تحويل أصل ${asset.name} بين مراكز التكلفة',
          date: DateTime.now(),
          lines: [
            JournalLine(accountId: assetAccount.id, debit: bookValue, description: 'تحويل أصل — وجهة', costCenterId: newCostCenterId),
            JournalLine(accountId: assetAccount.id, credit: bookValue, description: 'تحويل أصل — مصدر', costCenterId: fromCostCenterId),
          ],
          referenceType: 'asset_transfer',
          referenceId: assetId,
          isAutoPosted: true,
          costCenterId: costCenterId,
          branchId: await _resolveBranchFromCostCenter(costCenterId),
        );
      }
    });
  }

  /// Revalue an asset (IAS 16.31 — Revaluation Model)
  /// Creates a journal entry for the revaluation gain or loss
  Future<void> revalueAsset(
    int assetId, {
    required double newFairValue,
    int? costCenterId,
  }) async {
    await transaction(() async {
      final asset = await (select(fixedAssets)..where((a) => a.id.equals(assetId))).getSingleOrNull();
      if (asset == null) throw Exception('الأصل غير موجود');
      if (asset.status != 'active') throw Exception('لا يمكن إعادة تقييم أصل غير نشط');

      final currentBookValue = asset.purchasePrice - asset.accumulatedDepreciation;
      final difference = newFairValue - currentBookValue;

      if (difference.abs() < 0.01) return; // No material change

      // Update purchase price to reflect new valuation
      await (update(fixedAssets)..where((a) => a.id.equals(assetId)))
          .write(FixedAssetsCompanion(
            purchasePrice: Value(newFairValue + asset.accumulatedDepreciation),
            notes: Value('إعادة تقييم — القيمة العادلة: ${newFairValue.toStringAsFixed(AppConstants.decimalPlaces)} (${difference > 0 ? '+' : ''}${difference.toStringAsFixed(AppConstants.decimalPlaces)})'),
          ));

      final assetAccount = await _getCategoryAssetAccount(asset.categoryId);
      // IAS 16.39: Revaluation surplus → equity; Revaluation loss → P&L
      if (assetAccount != null) {
        if (difference > 0) {
          // Revaluation gain → Dr Asset / Cr Revaluation Surplus (equity 316)
          final equityAccount = await _assetGetAccountByCode('316'); // الاحتياطي الاختياري
          if (equityAccount != null) {
            await accountingDao.createJournalEntry(
              description: 'إعادة تقييم أصل ${asset.name} — فائض',
              date: DateTime.now(),
              lines: [
                JournalLine(accountId: assetAccount.id, debit: difference, description: 'زيادة قيمة أصل'),
                JournalLine(accountId: equityAccount.id, credit: difference, description: 'فائض إعادة التقييم'),
              ],
              referenceType: 'asset_revaluation',
              referenceId: assetId,
              isAutoPosted: true,
              costCenterId: costCenterId,
            );
          }
        } else {
          // Revaluation loss → Dr Expense / Cr Asset
          final expenseAccount = await _assetGetAccountByCode('6213'); // مصروفات الإهلاك - إداري
          if (expenseAccount != null) {
            await accountingDao.createJournalEntry(
              description: 'إعادة تقييم أصل ${asset.name} — خسارة',
              date: DateTime.now(),
              lines: [
                JournalLine(accountId: expenseAccount.id, debit: difference.abs(), description: 'خسارة إعادة تقييم'),
                JournalLine(accountId: assetAccount.id, credit: difference.abs(), description: 'تخفيض قيمة أصل'),
              ],
              referenceType: 'asset_revaluation',
              referenceId: assetId,
              isAutoPosted: true,
              costCenterId: costCenterId,
            );
          }
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEPRECIATION HISTORY
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch depreciation history for a specific asset
  Stream<List<AssetDepreciationData>> watchDepreciationHistory(int assetId) {
    return (select(assetDepreciations)
          ..where((d) => d.assetId.equals(assetId))
          ..orderBy([(d) => OrderingTerm.desc(d.periodDate)]))
        .watch();
  }

  /// Watch all depreciations
  Stream<List<AssetDepreciationData>> watchAllDepreciations() {
    return (select(assetDepreciations)
          ..orderBy([(d) => OrderingTerm.desc(d.periodDate)]))
        .watch();
  }

  /// Helper: get account by code (assets-scoped)
  Future<Account?> _assetGetAccountByCode(String code) async {
    return (select(accounts)..where((a) => a.code.equals(code))..limit(1))
        .getSingleOrNull();
  }

  /// Helper: get the fixed-asset GL account for a given category.
  /// Uses the category's accountId if set; falls back to '1211' (الأراضي).
  Future<Account?> _getCategoryAssetAccount(int categoryId) async {
    final cat = await (select(assetCategories)
          ..where((c) => c.id.equals(categoryId))
          ..limit(1))
        .getSingleOrNull();
    if (cat?.accountId != null) {
      return (select(accounts)
            ..where((a) => a.id.equals(cat!.accountId!))
            ..limit(1))
          .getSingleOrNull();
    }
    return _assetGetAccountByCode('1211'); // default: الأراضي
  }

  /// Helper: get the accumulated-depreciation GL account for a given category.
  /// Uses the category's depreciationAccountId if set; falls back to '1218' (مجمع إهلاك المباني).
  Future<Account?> _getCategoryDepreciationAccount(int categoryId) async {
    final cat = await (select(assetCategories)
          ..where((c) => c.id.equals(categoryId))
          ..limit(1))
        .getSingleOrNull();
    if (cat?.depreciationAccountId != null) {
      return (select(accounts)
            ..where((a) => a.id.equals(cat!.depreciationAccountId!))
            ..limit(1))
          .getSingleOrNull();
    }
    return _assetGetAccountByCode('1218'); // default: مجمع إهلاك المباني
  }
  // ─────────────────────────────────────────────────────────────────────────
  // HELPER: Resolve Branch from Cost Center
  // ─────────────────────────────────────────────────────────────────────────

  Future<int?> _resolveBranchFromCostCenter(int? costCenterId) async {
    if (costCenterId == null) return null;
    final branch = await (select(branches)
          ..where((b) => b.costCenterId.equals(costCenterId))
          ..limit(1))
        .getSingleOrNull();
    return branch?.id;
  }
}
