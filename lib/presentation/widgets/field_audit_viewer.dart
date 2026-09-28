import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database/database.dart'; // Only for FieldAuditLog type

/// PIR-10: Data source callback to decouple from AppDatabase
typedef FieldAuditDataSource = Future<List<FieldAuditLog>> Function({
  required String entityType,
  required int entityId,
  String? fieldKey,
  int limit,
});

/// A reusable widget that displays field-level audit history for any entity.
/// Shows a timeline of individual field changes with old → new values.
class FieldAuditViewer extends StatefulWidget {
  /// PIR-10: Accepts a data source callback instead of direct AppDatabase access
  final FieldAuditDataSource getFieldHistory;
  final String entityType;
  final int entityId;
  final String title;

  const FieldAuditViewer({
    super.key,
    required this.getFieldHistory,
    required this.entityType,
    required this.entityId,
    this.title = 'سجل التغييرات',
  });

  @override
  State<FieldAuditViewer> createState() => _FieldAuditViewerState();
}

class _FieldAuditViewerState extends State<FieldAuditViewer> {
  List<FieldAuditLog> _logs = [];
  bool _loading = true;
  String? _filterField;
  List<String> _availableFields = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant FieldAuditViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId ||
        oldWidget.entityType != widget.entityType) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final logs = await widget.getFieldHistory(
        entityType: widget.entityType,
        entityId: widget.entityId,
        fieldKey: _filterField,
        limit: 200,
      );

      // Extract distinct field names for filter dropdown
      final fields = <String>{};
      for (final log in logs) {
        fields.add(log.fieldKey);
      }

      setState(() {
        _logs = logs;
        _availableFields = fields.toList()..sort();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with filter
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.history, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_availableFields.isNotEmpty) ...[
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _filterField,
                    decoration: InputDecoration(
                      hintText: 'كل الحقول',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل الحقول'),
                      ),
                      ..._availableFields.map(
                        (f) => DropdownMenuItem(value: f, child: Text(f)),
                      ),
                    ],
                    onChanged: (val) {
                      _filterField = val;
                      _loadData();
                    },
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                '${_logs.length} تغيير',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Timeline
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'لا توجد تغييرات مسجلة',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return _buildChangeCard(context, log, isDark);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildChangeCard(
    BuildContext context,
    FieldAuditLog log,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('yyyy/MM/dd  HH:mm', 'ar').format(log.createdAt);

    // Determine change type colors
    final isAddition = log.oldValue == null && log.newValue != null;
    final isDeletion = log.oldValue != null && log.newValue == null;

    final changeColor = isAddition
        ? Colors.green
        : isDeletion
            ? AppColors.error
            : Colors.amber.shade700;

    final changeIcon = isAddition
        ? Icons.add_circle_outline
        : isDeletion
            ? Icons.remove_circle_outline
            : Icons.edit_outlined;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: changeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Change type icon
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: changeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(changeIcon, size: 18, color: changeColor),
            ),
            const SizedBox(width: 12),

            // Change details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Field name + date
                  Row(
                    children: [
                      Text(
                        log.fieldName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        dateStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Old → New values
                  if (!isAddition && !isDeletion) ...[
                    Row(
                      children: [
                        // Old value
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.oldValue ?? '—',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                decoration: TextDecoration.lineThrough,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.arrow_forward,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // New value
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.newValue ?? '—',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: changeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isAddition
                            ? log.newValue ?? '—'
                            : log.oldValue ?? '—',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: changeColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],

                  const SizedBox(height: 4),

                  // User name + reason
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        log.changedByName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      if (log.changeReason != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.info_outline,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            log.changeReason!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact inline button that opens the field audit viewer in a dialog.
class FieldAuditButton extends StatelessWidget {
  /// PIR-10: Accepts a data source callback instead of direct AppDatabase access
  final FieldAuditDataSource getFieldHistory;
  final String entityType;
  final int entityId;
  final String? label;

  const FieldAuditButton({
    super.key,
    required this.getFieldHistory,
    required this.entityType,
    required this.entityId,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showAuditDialog(context),
      icon: const Icon(Icons.history, size: 18),
      label: Text(label ?? 'سجل التغييرات'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }

  void _showAuditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 700,
          height: 500,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FieldAuditViewer(
              getFieldHistory: getFieldHistory,
              entityType: entityType,
              entityId: entityId,
            ),
          ),
        ),
      ),
    );
  }
}
