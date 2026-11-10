import 'package:flutter/material.dart';

import '../app/overlays.dart';

/// 디자인 토큰 (우리WON뱅킹 화면 기준 앱 UI 기본색)
abstract final class AppColors {
  static const blue = Color(0xFF2488F3);
  static const blueDark = Color(0xFF1A72D6);
  static const blueDeep = Color(0xFF0067AC);
  static const blueLight = Color(0xFFE6EEFF);
  static const sky = Color(0xFF20C4F4);

  static const bg = Color(0xFFF2F3F5);
  static const homeBand = Color(0xFFE6F4FF);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE6EAF0);
  static const lineStrong = Color(0xFFD3DAE3);

  static const text = Color(0xFF191F28);
  static const text2 = Color(0xFF4E5968);
  static const text3 = Color(0xFF76808C);

  static const success = Color(0xFF1E9E6A);
  static const successBg = Color(0xFFE7F6EF);
  static const successText = Color(0xFF0F6B46);
  static const warning = Color(0xFFE08F00);
  static const warningBg = Color(0xFFFFF4DC);
  static const warningText = Color(0xFF7A4D00);
  static const warningBadge = Color(0xFFB26F00);
  static const danger = Color(0xFFE5484D);
  static const dangerBg = Color(0xFFFDECEC);
  static const dangerText = Color(0xFF9B2226);
  static const neutralBg = Color(0xFFEEF1F5);
  static const infoText = Color(0xFF154A78);

  static const avatarBg = Color(0xFFC1E5FD);
  static const tagBg = Color(0xFFF2F2F2);
  static const tagText = Color(0xFF696D70);
  static const promoBg = Color(0xFFFAF3E3);
  static const promoTitle = Color(0xFF2B2D30);
  static const promoBody = Color(0xFF8B8F94);
  static const promoCounter = Color(0xB3383D40);
  static const noticeIconBg = Color(0xFFFFF3D0);
  static const noticeIcon = Color(0xFFFFBE0E);
  static const chatBg = Color(0xFFF4F6F9);
  static const chip = Color(0xFFEAF2FE);
  static const chatTool = Color(0xFF4E5358);
  static const chatAvatarBg = Color(0xFFE2EDFD);
  static const connectedBg = Color(0xFFECEEF1);
  static const aiBadgeFrom = Color(0xFFB14BFF);
  static const aiBadgeTo = Color(0xFF8E52FF);
  static const inputBg = Color(0xFFF2F3F5);
  static const modeToggleBg = Color(0xFF767F86);
  static const toggleOff = Color(0xFF4E5358);
  static const outline = Color(0xFFDDE1E5);
  static const bottomNavBg = Color(0xFFF3F4F7);
  static const muted = Color(0xFF9AA3AD);
  static const iconDark = Color(0xFF33383D);
  static const toastBg = Color(0xEB191F28);
  static const backdrop = Color(0x6B0A1423);
}

abstract final class AppRadius {
  static const card = 16.0;
  static const cardMd = 20.0;
  static const cardLg = 22.0;
  static const button = 14.0;
  static const buttonLg = 16.0;
  static const buttonSm = 11.0;
  static const pill = 999.0;
  static const sheet = 26.0;
}

/// 우리다움체 L(300) / R(400) / B(700).
/// 세 파일 모두 내부 굵기 값이 400(Regular)이라 한 family로 묶으면 엔진이 굵기를 구분하지 못한다.
/// 파일은 수정할 수 없으므로 굵기별 family로 등록하고 [wooridaumFamily]로 고른다.
/// 엔진에는 실제 내부 굵기인 400을 넘겨야 B 파일 위에 가짜 볼드가 덧씌워지지 않는다.
const String appFontFamily = 'WooridaumR';

String wooridaumFamily(FontWeight w) => w.value <= 300
    ? 'WooridaumL'
    : w.value >= 600
        ? 'WooridaumB'
        : 'WooridaumR';

TextStyle weightStyle(FontWeight w, {Color? color}) =>
    TextStyle(fontFamily: wooridaumFamily(w), fontWeight: FontWeight.w400, color: color);
const List<String> appFontFallback = ['Pretendard', 'Apple SD Gothic Neo', 'Noto Sans KR', 'Malgun Gothic'];
const List<String> monoFontFamily = ['Consolas', 'D2Coding', 'Menlo', 'monospace'];

const Curve appEase = Cubic(0.22, 0.8, 0.24, 1);

TextStyle ts(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.text,
  double? height,
  double letterSpacing = 0,
}) =>
    TextStyle(
      fontFamily: wooridaumFamily(weight),
      fontFamilyFallback: appFontFallback,
      fontSize: size,
      fontWeight: FontWeight.w400,
      color: color,
      height: height,
      letterSpacing: letterSpacing * size,
    );

TextStyle monoStyle(double size, {Color color = AppColors.text2}) => TextStyle(
      fontFamily: monoFontFamily.first,
      fontFamilyFallback: [...monoFontFamily.sublist(1), appFontFamily],
      fontSize: size,
      color: color,
    );

const List<BoxShadow> shadowCard = [
  BoxShadow(color: Color(0x0A102040), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0F102040), blurRadius: 16, offset: Offset(0, 4)),
];

const List<BoxShadow> shadowFloat = [
  BoxShadow(color: Color(0x2E0A1E46), blurRadius: 40, offset: Offset(0, 12)),
];

class ToneColors {
  const ToneColors(this.bg, this.fg, this.text);

  final Color bg;
  final Color fg;
  final Color text;

  static ToneColors of(UiTone tone) => switch (tone) {
        UiTone.success => const ToneColors(AppColors.successBg, AppColors.success, AppColors.successText),
        UiTone.warning => const ToneColors(AppColors.warningBg, AppColors.warningBadge, AppColors.warningText),
        UiTone.danger => const ToneColors(AppColors.dangerBg, AppColors.danger, AppColors.dangerText),
        UiTone.info => const ToneColors(AppColors.blueLight, AppColors.blue, AppColors.infoText),
        UiTone.neutral => const ToneColors(AppColors.neutralBg, AppColors.text2, AppColors.text2),
      };
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue, primary: AppColors.blue, surface: AppColors.surface),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: appFontFamily,
    fontFamilyFallback: appFontFallback,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.blue),
  );
}
