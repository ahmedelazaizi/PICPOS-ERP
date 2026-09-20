part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FLOOR PLAN DAO — مخطَّطُ القاعة (v174، قسمُ ٧)
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ 🔴 المخطَّطُ يُحفَظ **مستنداً واحداً** لا سحبةً سحبة ═══
//
// المصمّمُ القديم (`floor_plan_designer.dart`) كان يكتب في القاعدة عند نهاية
// **كلِّ** سحبة (`repo.updateTablePosition` داخل `onPanEnd`). ويترتّب على
// ذلك ثلاثةُ أشياءَ كلُّها سيّئة:
//
//   • **لا تراجعَ ممكن** — ما كُتب كُتب، فكلُّ سحبةٍ خاطئةٍ خسارةٌ دائمة.
//     وهو أوّلُ ما طلبته الخطّة من أدوات.
//   • **ولا ذرّيّة** — نصفُ القاعة يُنقَل ثمّ يُغلَق التطبيقُ فتبقى نصفَ
//     منقولة، ولا شيءَ يقول إنّ شيئاً بقي.
//   • **ولا عبورَ للسلك** — الكتابةُ في هذا المستودع **مستندٌ صريح**، فسحبةٌ
//     واحدةٌ ليست مستنداً يُقدَّم.
//
// فصار الحفظُ [saveFloorPlanLayout]: معاملةٌ واحدةٌ تحمل هندسةَ القسم
// وهندسةَ طاولاته ومعالمَه.
//
// ═══ ⚠️ والمعالمُ الغائبةُ عن الحمولة تُحذَف حذفاً ناعماً ═══
//
// لأنّ الحمولةَ **صورةُ المخطَّط كلِّه** لا فرقَه: جدارٌ مسحوهُ المستخدمُ
// يغيب من القائمة، ولو لم يُحذَف لعاد في أوّل فتحٍ للشاشة. وثمنُه المعروف:
// حفظان متوازيان من جهازَين يفوز آخرُهما بالمخطَّط كلِّه — وهو عينُ عقد
// المستندات في هذا المستودع، لا استثناءٌ منه.

extension FloorPlanDao on AppDatabase {
  // ───────────────────────────────────────────────────────────────────────
  // قراءة
  // ───────────────────────────────────────────────────────────────────────

  /// معالمُ قسمٍ — الحيّةُ وحدَها.
  Stream<List<FloorPlanItemData>> watchFloorPlanItems(int sectionId) {
    return (select(floorPlanItems)
          ..where((i) =>
              i.sectionId.equals(sectionId) &
              i.isActive.equals(true) &
              i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .watch();
  }

  Future<List<FloorPlanItemData>> getFloorPlanItems(int sectionId) {
    return (select(floorPlanItems)
          ..where((i) =>
              i.sectionId.equals(sectionId) &
              i.isActive.equals(true) &
              i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .get();
  }

  /// صناديقُ الأقسام على أرضيّة المحلّ — لنظرةِ المحلّ كلِّه.
  ///
  /// والمواضعُ الغائبةُ تُرصَف في [resolveSectionOrigins]، لا هنا: الرصفُ
  /// حسابٌ خالصٌ يُختبَر بلا قاعدة.
  Future<List<FloorPlanSectionBox>> getFloorPlanSectionBoxes() async {
    final sections = await (select(tableSections)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([
            (s) => OrderingTerm.asc(s.sortOrder),
            (s) => OrderingTerm.asc(s.id),
          ]))
        .get();
    return resolveSectionOrigins([
      for (final s in sections)
        (
          sectionId: s.id,
          originX: s.originX,
          originY: s.originY,
          width: s.canvasWidth ?? kDefaultCanvasWidth,
          height: s.canvasHeight ?? kDefaultCanvasHeight,
        ),
    ]);
  }

  /// مخطَّطُ قسمٍ كاملاً كما يفتحه المصمّم.
  Future<FloorPlanSectionLayout?> getFloorPlanSectionLayout(
    int sectionId,
  ) async {
    final section = await (select(tableSections)
          ..where((s) => s.id.equals(sectionId))
          ..limit(1))
        .getSingleOrNull();
    if (section == null) return null;

    final tables = await (select(restaurantTables)
          ..where((t) =>
              t.sectionId.equals(sectionId) & t.isActive.equals(true)))
        .get();
    final items = await getFloorPlanItems(sectionId);

    return (
      sectionId: sectionId,
      sectionGlobalId: section.globalId,
      canvasWidth: section.canvasWidth ?? kDefaultCanvasWidth,
      canvasHeight: section.canvasHeight ?? kDefaultCanvasHeight,
      originX: section.originX ?? 0,
      originY: section.originY ?? 0,
      tables: <FloorPlanTableGeometry>[
        for (final t in tables)
          (
            id: t.id,
            globalId: t.globalId,
            x: t.x,
            y: t.y,
            width: t.width,
            height: t.height,
            rotation: t.rotation,
            shape: t.shape,
          ),
      ],
      items: <FloorPlanItemInput>[
        for (final i in items)
          (
            id: i.id,
            globalId: i.globalId,
            kind: i.kind,
            x: i.x,
            y: i.y,
            width: i.width,
            height: i.height,
            rotation: i.rotation,
            label: i.label,
          ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // كتابة
  // ───────────────────────────────────────────────────────────────────────

  /// حفظُ مخطَّط قسمٍ كاملاً — **معاملةٌ واحدة**.
  Future<void> saveFloorPlanLayout(FloorPlanSectionLayout layout) async {
    final bad = validateFloorPlanLayout(layout);
    if (bad != null) throw ArgumentError(bad);

    final now = DateTime.now();

    await transaction(() async {
      // ── هندسةُ القسم ────────────────────────────────────────────────
      await (update(tableSections)
            ..where((s) => s.id.equals(layout.sectionId)))
          .write(
        TableSectionsCompanion(
          canvasWidth: Value(layout.canvasWidth),
          canvasHeight: Value(layout.canvasHeight),
          originX: Value(layout.originX),
          originY: Value(layout.originY),
          lastModifiedAt: Value(now),
        ),
      );

      // ── هندسةُ الطاولات ─────────────────────────────────────────────
      //
      // ⚠️ **والشرطُ على القسم ليس تزيُّداً.** الحمولةُ تأتي من شاشةٍ أو من
      //    السلك، وطاولةٌ من قسمٍ آخرَ ذُكرت فيها كانت ستُنقَل إلى إحداثيّاتِ
      //    لوحةٍ لا تخصّها — فتختفي من قسمها بلا أن يلمسها أحد. والقيدُ هنا
      //    يجعل ذكرَها بلا أثر.
      for (final t in layout.tables) {
        await (update(restaurantTables)
              ..where((r) =>
                  r.id.equals(t.id) & r.sectionId.equals(layout.sectionId)))
            .write(
          RestaurantTablesCompanion(
            x: Value(t.x),
            y: Value(t.y),
            width: Value(t.width),
            height: Value(t.height),
            rotation: Value(t.rotation),
            shape: Value(t.shape),
            lastModifiedAt: Value(now),
          ),
        );
      }

      // ── المعالم ─────────────────────────────────────────────────────
      final existing = await (select(floorPlanItems)
            ..where((i) =>
                i.sectionId.equals(layout.sectionId) &
                i.isActive.equals(true) &
                i.deletedAt.isNull()))
          .get();
      final byGlobalId = <String, FloorPlanItemData>{
        for (final e in existing)
          if (e.globalId != null) e.globalId!: e,
      };
      final byId = <int, FloorPlanItemData>{
        for (final e in existing) e.id: e,
      };

      final kept = <int>{};
      for (final it in layout.items) {
        final match = (it.globalId != null ? byGlobalId[it.globalId] : null) ??
            (it.id != null ? byId[it.id] : null);

        if (match == null) {
          await into(floorPlanItems).insert(
            FloorPlanItemsCompanion.insert(
              sectionId: layout.sectionId,
              kind: it.kind,
              x: Value(it.x),
              y: Value(it.y),
              width: Value(it.width),
              height: Value(it.height),
              rotation: Value(it.rotation),
              label: Value(it.label),
              // هويّةٌ تسبق أوّلَ مزامنة — المعلَمُ قد يُرسَم دون اتّصالٍ
              // ويُدفَع لاحقاً، فلا بدّ أن يحمل حينها نفسَ المعرِّف.
              globalId: Value(it.globalId ?? UuidV7.generate()),
              lastModifiedAt: Value(now),
            ),
          );
          continue;
        }

        kept.add(match.id);
        await (update(floorPlanItems)..where((i) => i.id.equals(match.id)))
            .write(
          FloorPlanItemsCompanion(
            kind: Value(it.kind),
            x: Value(it.x),
            y: Value(it.y),
            width: Value(it.width),
            height: Value(it.height),
            rotation: Value(it.rotation),
            label: Value(it.label),
            lastModifiedAt: Value(now),
          ),
        );
      }

      // ── ما غاب عن الحمولة حُذف ──────────────────────────────────────
      for (final e in existing) {
        if (kept.contains(e.id)) continue;
        await (update(floorPlanItems)..where((i) => i.id.equals(e.id))).write(
          FloorPlanItemsCompanion(
            isActive: const Value(false),
            deletedAt: Value(now),
            lastModifiedAt: Value(now),
          ),
        );
      }
    });
  }
}
