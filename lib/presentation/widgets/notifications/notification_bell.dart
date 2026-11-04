import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import 'providers/notification_provider.dart';
import 'notification_panel.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCountAsync = ref.watch(unreadNotificationsCountProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(PhosphorIconsRegular.bell, color: context.picposText),
          tooltip: tr('الإشعارات'),
          onPressed: () {
            // Open the notification panel
            showGeneralDialog(
              context: context,
              barrierDismissible: true,
              barrierLabel: 'Dismiss',
              pageBuilder: (context, animation, secondaryAnimation) {
                return Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Material(
                    elevation: 16,
                    color: Colors.transparent,
                    child: Container(
                      width: 400,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: context.picposField,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                        ),
                      ),
                      child: const NotificationPanel(),
                    ),
                  ),
                );
              },
              transitionBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(-1, 0), // Slide from left for RTL
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
            );
          },
        ),
        unreadCountAsync.when(
          data: (count) {
            if (count > 0) {
              return PositionedDirectional(
                start: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
