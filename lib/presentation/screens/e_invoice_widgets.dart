part of 'e_invoice_dashboard_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS — عناصر واجهة المستخدم
// ═══════════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  final EInvoiceSubmissionData submission;
  final VoidCallback onRetry;
  final VoidCallback onCheckStatus;
  final VoidCallback onCancel;

  const _SubmissionTile({
    required this.submission,
    required this.onRetry,
    required this.onCheckStatus,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(submission.status);
    final statusLabel = _statusLabel(submission.status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(
            _statusIcon(submission.status),
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text('فاتورة #${submission.id}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المنصة: ${submission.platform.toUpperCase()}'),
            if (submission.submittedAt != null)
              Text('تاريخ: ${_formatDate(submission.submittedAt!)}'),
            if (submission.errorMessage != null)
              Text(
                submission.errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 11),
              ),
              backgroundColor: statusColor.withValues(alpha: 0.1),
              side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'retry':
                    onRetry();
                  case 'status':
                    onCheckStatus();
                  case 'cancel':
                    onCancel();
                }
              },
              itemBuilder: (_) => [
                if (submission.status == 'pending' ||
                    submission.status == 'invalid')
                  const PopupMenuItem(
                    value: 'retry',
                    child: Text('إعادة إرسال'),
                  ),
                if (submission.status == 'submitted')
                  const PopupMenuItem(
                    value: 'status',
                    child: Text('فحص الحالة'),
                  ),
                if (submission.status == 'valid')
                  const PopupMenuItem(value: 'cancel', child: Text('إلغاء')),
              ],
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'valid':
        return Colors.green;
      case 'submitted':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'invalid':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'valid':
        return 'مقبولة';
      case 'submitted':
        return 'مرسلة';
      case 'pending':
        return 'معلقة';
      case 'invalid':
        return 'مرفوضة';
      case 'cancelled':
        return 'ملغاة';
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'valid':
        return Icons.check_circle;
      case 'submitted':
        return Icons.send;
      case 'pending':
        return Icons.hourglass_empty;
      case 'invalid':
        return Icons.error;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
