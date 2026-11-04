part of 'picpos_payment_panel.dart';

/// زرار ثانوي مضغوط — أيقونة فوق تسمية، بلا إطار ثقيل.
class _MiniAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final double height;
  final double font;

  const _MiniAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.height,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: _fieldOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.picposHairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: font + 2, color: PicPosText.brandOf(context)),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: PicPosText.v(context, 
                  font,
                  color: PicPosText.brandOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final double height;
  final double font;

  const _Action({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.height,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(color: context.picposHairline),
          foregroundColor: PicPosText.brandOf(context),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: PicPosText.v(context, font),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
