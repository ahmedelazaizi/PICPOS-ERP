import 'package:ural_erp/core/i18n/tr.dart';
// بطاقةُ قالبٍ في شبكة المكتبة.
//
// المصغَّرةُ تعلو، والاسمُ تحتَها، والشاراتُ في الزاوية — كما في التصميم.
// وهي **مصغَّرةُ المحرّك** لا رسماً تخطيطيّاً: انظر
// `template_thumbnail_view.dart`.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../domain/models/picpos_template_card.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../screens/template_library_picpos_screen.dart'
    show templateStatusLabel, templateStatusTone;
import 'template_thumbnail_view.dart';

class TemplateGalleryCard extends StatelessWidget {
  const TemplateGalleryCard({
    super.key,
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final TemplateCard card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = templateStatusTone(card);
    final brand = context.picposBrandInk;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: context.picposCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? brand : context.picposHairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TemplateThumbnailView(thumbnail: card.thumbnail),
                  ),
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    child: _Badge(text: card.paperLabel, tone: brand),
                  ),
                  if (card.layoutVersion < 2)
                    PositionedDirectional(
                      bottom: 0,
                      start: 0,
                      child: Tooltip(
                        // صدقٌ لا تزيين: هذا القالبُ يُطبع بالراسم التدفّقيّ،
                        // والمصغَّرةُ تخطيطُ المحرّك. الشكلان متقاربان
                        // ومشتقّان من نفس العناصر، وليسا عينَ بعضهما.
                        message: tr('قالبٌ لم يُهاجَر بعد — المصغَّرةُ تقريبيّة'),
                        child: Icon(
                          PhosphorIconsBold.info,
                          size: 13,
                          color: context.picposMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              card.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.picposText,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              card.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: context.picposMuted),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Badge(text: templateStatusLabel(card), tone: tone),
                const Spacer(),
                if (card.isBound)
                  Text(
                    tr('{p0} مستند', {'p0': card.bindings.length}),
                    style:
                        TextStyle(fontSize: 10.5, color: context.picposMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
      );
}
