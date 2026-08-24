import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_surface.dart';
import '../../core/constants/app_constants.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';
import 'widgets/dialogs/opex_category_edit_dialog.dart';
import 'widgets/dialogs/opex_record_edit_dialog.dart';

/// Operational Expenses Screen — إدارة المصروفات التشغيلية

part 'opex_categories_tab.dart';
part 'opex_expenses_tab.dart';
class OperationalExpensesScreen extends ConsumerStatefulWidget {
  const OperationalExpensesScreen({super.key});
  @override
  ConsumerState<OperationalExpensesScreen> createState() =>
      _OperationalExpensesScreenState();
}

class _OperationalExpensesScreenState
    extends ConsumerState<OperationalExpensesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      // لا تجاوزَ للخلفيّة: الثيمُ يعرّف `scaffoldBackgroundColor` للوضعَين.
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المصروفات التشغيلية',
              style: TextStyle(fontWeight: FontWeight.bold)),
          // الشقّان مقترنان: خلفيّةٌ بيضاءُ ونصٌّ داكنٌ صحيحان في الفاتح
          // وحدَه. ويتبعان الوضعَ معاً — تجاوزُ أحدِهما يكسر الاقتران.
          backgroundColor: context.picposCard,
          foregroundColor: context.picposText,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(
                  icon: Icon(PhosphorIconsBold.listDashes),
                  text: 'فئات المصروفات'),
              Tab(
                  icon: Icon(PhosphorIconsBold.receipt),
                  text: 'سجل المصروفات'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _CategoriesTab(),
            _ExpensesTab(
              dateRange: _dateRange,
              onDateRangeChanged: (range) =>
                  setState(() => _dateRange = range),
            ),
          ],
        ),
      ),
    );
  }
}

