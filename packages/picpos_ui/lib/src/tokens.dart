import 'package:flutter/material.dart';

/// DESIGN.md colour tokens (front-matter names in comments).
abstract final class PicPosTokens {
  static const brandBlue = Color(0xFF0250D3); // brand-blue
  static const brandNavy = Color(0xFF012258); // brand-navy
  static const brandSky = Color(0xFF4A80E8); // brand-sky
  static const brandInkDark = Color(0xFF7DA6F5); // brand-ink-dark
  static const canvas = Color(0xFFF2F5FA); // canvas
  static const card = Color(0xFFFFFFFF); // card
  static const fieldFill = Color(0xFFF4F7FC); // field-fill
  static const hairline = Color(0xFFDCE3EE); // hairline
  static const ink = Color(0xFF000000); // ink
  static const inkSecondary = Color(0xFF374151); // ink-secondary
  static const inkMuted = Color(0xFF6B7280); // ink-muted
  static const canvasDark = Color(0xFF0A1220); // canvas-dark
  static const cardDark = Color(0xFF121C2E); // card-dark
  static const fieldFillDark = Color(0xFF18243A); // field-fill-dark
  static const hairlineDark = Color(0xFF243247); // hairline-dark
  static const inkDark = Color(0xFFFFFFFF); // ink-dark
  static const inkMutedDark = Color(0xFF94A3B8); // ink-muted-dark
  static const sidebarSlate = Color(0xFF1E293B); // sidebar-slate
  static const success = Color(0xFF22C55E); // success
  static const successDeep = Color(0xFF16A34A); // success-deep
  static const warning = Color(0xFFF59E0B); // warning
  static const warningDeep = Color(0xFFD97706); // warning-deep
  static const error = Color(0xFFEF4444); // error
  static const errorDeep = Color(0xFFDC2626); // error-deep
  static const switchTrackOff = Color(0xFFC7D2E1); // switch-track-off
  static const checkboxOutline = Color(0xFFB6C2D4); // checkbox-outline
}

/// DESIGN.md spacing rhythm (4 px base).
abstract final class PicPosSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 48.0;
  static const page = 64.0;

  /// Grid-of-cards gap.
  static const cardGap = 13.0;

  /// Page-header and dialog gutters.
  static const gutter = 20.0;
}

abstract final class PicPosRadii {
  static const field = 10.0;
  static const button = 10.0;
  static const formButton = 11.0;
  static const card = 14.0;
  static const chip = 9.0;
  static const badge = 12.0;
}

/// Window-size breakpoints (dp) used by the adaptive widgets.
abstract final class PicPosBreakpoints {
  /// < 600: phone (bottom navigation bar, card lists).
  static const medium = 600.0;

  /// ≥ 840: list/detail two-pane.
  static const expanded = 840.0;
}

/// Font families bundled by this package (use these names, they carry the
/// `packages/picpos_ui/` prefix Flutter requires for package fonts).
abstract final class PicPosFonts {
  static const ui = 'packages/picpos_ui/Cairo';
  static const print = 'packages/picpos_ui/NotoNaskhArabic';
}
