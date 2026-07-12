import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BackupRestoreWidget extends ConsumerWidget {
  const BackupRestoreWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Backup/Restore not supported on web in this version
    return const SizedBox.shrink();
  }
}
