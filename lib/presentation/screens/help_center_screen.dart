import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// B7 — Built-in Help Center widget.
/// Displays common questions and guides for the ERP system.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  String _searchQuery = '';
  int? _expandedIndex;

  static const List<_HelpSection> _sections = [
    _HelpSection(
      title: 'البدء السريع',
      icon: PhosphorIconsBold.rocketLaunch,
      items: [
        _HelpItem(
          question: 'كيف أضيف صنف جديد؟',
          answer: 'اذهب إلى "الأصناف" ← اضغط زر "إضافة" ← املأ البيانات (الاسم، الكود، السعر، التكلفة) ← اضغط "حفظ".\n\nيمكنك أيضاً إضافة باركود وصورة للصنف.',
        ),
        _HelpItem(
          question: 'كيف أنشئ فاتورة بيع؟',
          answer: 'اذهب إلى "البيع السريع" ← اختر الأصناف من القائمة أو امسح الباركود ← حدد الكمية ← اضغط "إتمام البيع" ← اختر طريقة الدفع.',
        ),
        _HelpItem(
          question: 'كيف أضيف عميل أو مورد؟',
          answer: 'اذهب إلى "العملاء والموردين" ← اضغط "إضافة" ← اختر النوع (عميل/مورد) ← أدخل الاسم والهاتف ← اضغط "حفظ".',
        ),
      ],
    ),
    _HelpSection(
      title: 'إدارة المخزون',
      icon: PhosphorIconsBold.warehouse,
      items: [
        _HelpItem(
          question: 'كيف أتابع المخزون؟',
          answer: 'اذهب إلى "المخزون" لرؤية إجمالي المخزون لكل صنف.\n\nالنظام يحدّث المخزون تلقائياً عند كل عملية بيع أو شراء.\n\nاضبط "الحد الأدنى" لكل صنف لتلقي تنبيهات عند قرب نفاده.',
        ),
        _HelpItem(
          question: 'كيف أعمل جرد؟',
          answer: 'اذهب إلى "المخزون" ← "جرد المخزون" ← اختر المخزن ← أدخل الكميات الفعلية ← النظام يحسب الفروقات تلقائياً ← اعتمد الجرد.',
        ),
      ],
    ),
    _HelpSection(
      title: 'التقارير والمالية',
      icon: PhosphorIconsBold.chartBar,
      items: [
        _HelpItem(
          question: 'أين أجد تقرير الأرباح والخسائر؟',
          answer: 'اذهب إلى "التقارير" ← "القوائم المالية" ← تبويب "قائمة الدخل".\n\nيمكنك تحديد الفترة الزمنية ومركز التكلفة وتصدير التقرير إلى Excel أو PDF.',
        ),
        _HelpItem(
          question: 'كيف أصدّر تقرير Excel؟',
          answer: 'في أي شاشة تقارير، اضغط على أيقونة Excel في شريط الأدوات.\n\nسيتم حفظ الملف تلقائياً ويمكنك فتحه مباشرة.',
        ),
        _HelpItem(
          question: 'كيف أشوف مبيعات اليوم؟',
          answer: 'لوحة التحكم تعرض ملخص مبيعات اليوم تلقائياً.\n\nللتفاصيل: اذهب إلى "التقارير" ← "تقرير المبيعات" واختر الفترة "اليوم".',
        ),
      ],
    ),
    _HelpSection(
      title: 'الإعدادات والنظام',
      icon: PhosphorIconsBold.gear,
      items: [
        _HelpItem(
          question: 'كيف أوصّل الطابعة؟',
          answer: 'اذهب إلى "الإعدادات" ← "إعدادات الأجهزة" ← "الطابعة" ← اختر نوع الاتصال (USB أو شبكة) ← اختر الطابعة ← اضغط "حفظ".',
        ),
        _HelpItem(
          question: 'كيف أعمل نسخة احتياطية؟',
          answer: 'اذهب إلى "الإعدادات" ← "النسخ الاحتياطي" ← اضغط "إنشاء نسخة" ← اختر مكان الحفظ.\n\n⚠️ ننصح بعمل نسخة احتياطية يومياً وحفظها على USB أو سحابة.',
        ),
        _HelpItem(
          question: 'كيف أضيف موظف جديد؟',
          answer: 'اذهب إلى "الإعدادات" ← "إدارة المستخدمين" ← "إضافة مستخدم" ← أدخل البيانات واختر الصلاحيات ← اضغط "حفظ".',
        ),
      ],
    ),
  ];

  List<_HelpSection> get _filteredSections {
    if (_searchQuery.isEmpty) return _sections;
    return _sections
        .map((section) {
          final filtered = section.items
              .where((item) =>
                  item.question.contains(_searchQuery) ||
                  item.answer.contains(_searchQuery))
              .toList();
          if (filtered.isEmpty) return null;
          return _HelpSection(
            title: section.title,
            icon: section.icon,
            items: filtered,
          );
        })
        .whereType<_HelpSection>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('مركز المساعدة'),
        ),
        body: Column(
          children: [
            // Search bar
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث عن سؤال...',
                  prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            // Help sections
            Expanded(
              child: sections.isEmpty
                  ? const Center(child: Text('لا توجد نتائج'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: sections.length,
                      itemBuilder: (context, sectionIndex) {
                        final section = sections[sectionIndex];
                        return _buildSection(section, sectionIndex);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(_HelpSection section, int sectionIndex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(section.icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...section.items.asMap().entries.map((entry) {
            final globalIndex = sectionIndex * 100 + entry.key;
            final item = entry.value;
            final isExpanded = _expandedIndex == globalIndex;

            return Column(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _expandedIndex = isExpanded ? null : globalIndex;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded
                              ? PhosphorIconsBold.caretDown
                              : PhosphorIconsBold.caretLeft,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.question,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isExpanded
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(40, 0, 16, 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.answer,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          color: AppColors.textSecondary),
                    ),
                  ),
                if (entry.key < section.items.length - 1)
                  const Divider(height: 1, indent: 40),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _HelpSection {
  final String title;
  final IconData icon;
  final List<_HelpItem> items;

  const _HelpSection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class _HelpItem {
  final String question;
  final String answer;

  const _HelpItem({required this.question, required this.answer});
}
