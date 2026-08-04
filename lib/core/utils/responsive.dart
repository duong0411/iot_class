import 'dart:math';
import 'package:flutter/material.dart';

/// Responsive utility — dùng trong toàn bộ app
class R {
  R._();

  // ─── Screen info ──────────────────────────────────────────────────────────
  static double w(BuildContext ctx) => MediaQuery.sizeOf(ctx).width;
  static double h(BuildContext ctx) => MediaQuery.sizeOf(ctx).height;

  /// Padding an toàn phía trên (status bar + notch/tai thỏ/nốt ruồi)
  static double top(BuildContext ctx) => MediaQuery.viewPaddingOf(ctx).top;

  /// Padding an toàn phía dưới (thanh cử chỉ vuốt lên)
  static double bottom(BuildContext ctx) =>
      max(MediaQuery.viewPaddingOf(ctx).bottom, 8);

  /// Padding an toàn trái/phải (camera thụt vào 2 bên)
  static double left(BuildContext ctx) => MediaQuery.viewPaddingOf(ctx).left;
  static double right(BuildContext ctx) => MediaQuery.viewPaddingOf(ctx).right;

  // ─── Screen category ──────────────────────────────────────────────────────
  /// Màn hình nhỏ < 360dp (Samsung A-series cũ, v.v.)
  static bool isSmall(BuildContext ctx) => w(ctx) < 360;

  /// Màn hình bình thường 360–414dp
  static bool isNormal(BuildContext ctx) => w(ctx) >= 360 && w(ctx) < 415;

  /// Màn hình lớn ≥ 415dp (iPhone Plus, Samsung S-series, v.v.)
  static bool isLarge(BuildContext ctx) => w(ctx) >= 415;

  // ─── Font size ────────────────────────────────────────────────────────────
  /// Scale font theo chiều rộng màn hình
  static double fs(BuildContext ctx, double base) {
    final scale = (w(ctx) / 390).clamp(0.82, 1.18);
    return base * scale;
  }

  // ─── Spacing ──────────────────────────────────────────────────────────────
  /// Scale khoảng cách theo màn hình
  static double sp(BuildContext ctx, double base) {
    if (isSmall(ctx)) return base * 0.82;
    if (isLarge(ctx)) return base * 1.08;
    return base;
  }

  // ─── Padding cạnh ngang ───────────────────────────────────────────────────
  /// Padding ngang phù hợp mọi màn hình (min 16, max 28)
  static double hPad(BuildContext ctx) => sp(ctx, 22).clamp(16.0, 28.0);

  // ─── Icon size ────────────────────────────────────────────────────────────
  static double icon(BuildContext ctx, double base) {
    if (isSmall(ctx)) return base * 0.88;
    if (isLarge(ctx)) return base * 1.06;
    return base;
  }

  // ─── Safe bottom padding cho SingleChildScrollView ────────────────────────
  /// Dùng làm padding bottom trong list/scroll để tránh gesture bar che nội dung
  static EdgeInsets scrollPadding(BuildContext ctx, {double extra = 0}) {
    return EdgeInsets.only(
      left: hPad(ctx),
      right: hPad(ctx),
      bottom: bottom(ctx) + extra,
    );
  }
}
