import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// C6 — Guided Tour Service
///
/// Manages interactive walkthroughs for key screens using tutorial overlays.
/// Tracks completion via SharedPreferences and supports first-visit auto-trigger.
class GuidedTourService {
  static const _prefix = 'tour_completed_';

  /// Check if a user has completed a specific tour
  static Future<bool> hasCompletedTour(String tourName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$tourName') ?? false;
  }

  /// Mark a tour as completed
  static Future<void> markTourComplete(String tourName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$tourName', true);
  }

  /// Reset a tour (allow replaying)
  static Future<void> resetTour(String tourName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$tourName');
  }

  /// Reset all tours
  static Future<void> resetAllTours() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Show a guided tour if not completed yet.
  /// Returns true if tour was shown, false if already completed.
  static Future<bool> showTourIfNeeded({
    required BuildContext context,
    required String tourName,
    required List<TourStep> steps,
  }) async {
    if (await hasCompletedTour(tourName)) return false;
    if (!context.mounted) return false;

    await _showTourOverlay(context, tourName, steps);
    return true;
  }

  /// Force-show a tour (for "Replay Tour" button)
  static Future<void> showTour({
    required BuildContext context,
    required String tourName,
    required List<TourStep> steps,
  }) async {
    await resetTour(tourName);
    if (!context.mounted) return;
    await _showTourOverlay(context, tourName, steps);
  }

  static Future<void> _showTourOverlay(
    BuildContext context,
    String tourName,
    List<TourStep> steps,
  ) async {
    int currentStep = 0;

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final step = steps[currentStep];
            final isLast = currentStep >= steps.length - 1;

            return Stack(
              children: [
                // Tap to dismiss background
                GestureDetector(
                  onTap: () {},
                  child: Container(color: Colors.transparent),
                ),

                // Tour card
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 450),
                    margin: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header with step indicator
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.primaryContainer,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                step.icon ?? Icons.lightbulb_outline,
                                color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.title,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${currentStep + 1} / ${steps.length}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(ctx).colorScheme.onPrimaryContainer
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  markTourComplete(tourName);
                                  Navigator.of(dialogCtx).pop();
                                },
                                icon: Icon(
                                  Icons.close,
                                  color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Body
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            step.description,
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                            ),
                          ),
                        ),

                        // Step progress indicator
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              steps.length,
                              (index) => Container(
                                width: index == currentStep ? 24 : 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: index == currentStep
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Theme.of(ctx).colorScheme.outlineVariant,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Actions
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (currentStep > 0)
                                TextButton.icon(
                                  onPressed: () {
                                    setDialogState(() => currentStep--);
                                  },
                                  icon: const Icon(Icons.arrow_back, size: 18),
                                  label: const Text('السابق'),
                                )
                              else
                                TextButton(
                                  onPressed: () {
                                    markTourComplete(tourName);
                                    Navigator.of(dialogCtx).pop();
                                  },
                                  child: const Text('تخطي'),
                                ),
                              FilledButton.icon(
                                onPressed: () {
                                  if (isLast) {
                                    markTourComplete(tourName);
                                    Navigator.of(dialogCtx).pop();
                                  } else {
                                    setDialogState(() => currentStep++);
                                  }
                                },
                                icon: Icon(
                                  isLast ? Icons.check : Icons.arrow_forward,
                                  size: 18,
                                ),
                                label: Text(isLast ? 'إنهاء' : 'التالي'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PREDEFINED TOURS
  // ═══════════════════════════════════════════════════════════════════════

  /// Dashboard tour steps
  static List<TourStep> get dashboardTour => [
    const TourStep(
      title: 'مرحباً بك في لوحة التحكم',
      description: 'هذه هي لوحة التحكم الرئيسية. هنا ستجد ملخصاً سريعاً لأداء عملك اليومي والشهري.',
      icon: Icons.dashboard,
    ),
    const TourStep(
      title: 'مؤشرات الأداء',
      description: 'في الأعلى تجد مؤشرات الأداء الرئيسية: المبيعات، المصروفات، صافي الربح، وعدد الفواتير.',
      icon: Icons.analytics,
    ),
    const TourStep(
      title: 'الرسوم البيانية',
      description: 'الرسوم البيانية تعرض اتجاهات المبيعات والمصروفات على مدار الفترة. يمكنك تبديل الفترة بين يومي، أسبوعي، وشهري.',
      icon: Icons.bar_chart,
    ),
    const TourStep(
      title: 'التنقل السريع',
      description: 'استخدم القائمة الجانبية للتنقل بين شاشات التطبيق: المبيعات، المشتريات، المخزون، والإعدادات.',
      icon: Icons.menu,
    ),
  ];

  /// POS tour steps
  static List<TourStep> get posTour => [
    const TourStep(
      title: 'نقطة البيع',
      description: 'شاشة نقطة البيع مصممة للبيع السريع. ابحث عن الأصناف بالاسم أو بقراءة الباركود.',
      icon: Icons.point_of_sale,
    ),
    const TourStep(
      title: 'سلة المشتريات',
      description: 'الأصناف المختارة تظهر في السلة على اليمين. يمكنك تعديل الكمية أو إضافة خصم لكل صنف.',
      icon: Icons.shopping_cart,
    ),
    const TourStep(
      title: 'إتمام الدفع',
      description: 'اضغط على زر "إتمام الدفع" لتحديد طريقة الدفع (نقدي، بطاقة، آجل) وإصدار الفاتورة.',
      icon: Icons.payment,
    ),
  ];

  /// Products tour steps
  static List<TourStep> get productsTour => [
    const TourStep(
      title: 'إدارة الأصناف',
      description: 'هنا يمكنك إضافة وتعديل وحذف الأصناف. استخدم البحث للوصول السريع لأي صنف.',
      icon: Icons.inventory_2,
    ),
    const TourStep(
      title: 'إضافة صنف جديد',
      description: 'اضغط على "+" لإضافة صنف جديد. أدخل الاسم، الكود، السعر، والتصنيف.',
      icon: Icons.add_circle_outline,
    ),
    const TourStep(
      title: 'استيراد وتصدير',
      description: 'يمكنك استيراد الأصناف من ملف Excel أو تصديرها للنسخ الاحتياطي.',
      icon: Icons.import_export,
    ),
  ];

  /// Inventory tour steps
  static List<TourStep> get inventoryTour => [
    const TourStep(
      title: 'إدارة المخزون',
      description: 'تابع أرصدة المخزون لكل صنف في كل مستودع. شاهد الكميات المتاحة والحركات.',
      icon: Icons.warehouse,
    ),
    const TourStep(
      title: 'حركات المخزون',
      description: 'كل عملية شراء أو بيع أو تحويل تُسجل تلقائياً كحركة مخزون.',
      icon: Icons.swap_horiz,
    ),
    const TourStep(
      title: 'سندات المخزون',
      description: 'استخدم سندات الإضافة والصرف لتعديل المخزون يدوياً أو لتحويل الأصناف بين المستودعات.',
      icon: Icons.receipt_long,
    ),
  ];

  /// Reports tour steps
  static List<TourStep> get reportsTour => [
    const TourStep(
      title: 'التقارير',
      description: 'استعرض تقارير شاملة عن المبيعات، المشتريات، المخزون، والحسابات.',
      icon: Icons.assessment,
    ),
    const TourStep(
      title: 'تصدير التقارير',
      description: 'يمكنك تصدير أي تقرير كملف PDF أو Excel للحفظ أو المشاركة.',
      icon: Icons.file_download,
    ),
  ];
}

/// Represents a single step in a guided tour
class TourStep {
  final String title;
  final String description;
  final IconData? icon;
  final GlobalKey? targetKey;

  const TourStep({
    required this.title,
    required this.description,
    this.icon,
    this.targetKey,
  });
}
