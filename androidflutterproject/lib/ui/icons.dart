import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'svg_path.dart';

/// 아이콘의 채움/선 색. null이면 사용하지 않고, [current]면 위젯의 color를 쓴다.
class Pigment {
  const Pigment._(this.color);
  const Pigment.color(Color this.color);

  static const current = Pigment._(null);

  final Color? color;

  Color resolve(Color current) => color ?? current;
}

abstract class _Prim {
  const _Prim();
  Path build();
}

class _PathPrim extends _Prim {
  const _PathPrim(this.d);
  final String d;
  @override
  Path build() => parseSvgPath(d);
}

class _CirclePrim extends _Prim {
  const _CirclePrim(this.cx, this.cy, this.r);
  final double cx, cy, r;
  @override
  Path build() => Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
}

class _RectPrim extends _Prim {
  const _RectPrim(this.x, this.y, this.w, this.h, this.rx);
  final double x, y, w, h, rx;
  @override
  Path build() => Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rx)));
}

class _EllipsePrim extends _Prim {
  const _EllipsePrim(this.cx, this.cy, this.rx, this.ry, this.rotate);
  final double cx, cy, rx, ry, rotate;
  @override
  Path build() {
    final p = Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));
    if (rotate == 0) return p;
    final m = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..rotateZ(rotate * math.pi / 180)
      ..translateByDouble(-cx, -cy, 0, 1);
    return p.transform(m.storage);
  }
}

/// SVG 요소 하나 (path / circle / rect / ellipse)
class SvgEl {
  SvgEl._(this._prim, {this.fill, this.stroke, this.strokeWidth});

  final _Prim _prim;
  final Pigment? fill;
  final Pigment? stroke;
  final double? strokeWidth;
  late final Path path = _prim.build();
}

/// 선 아이콘 기본값: fill 없음, stroke = currentColor
SvgEl _p(String d, {Pigment? fill, Pigment? stroke = Pigment.current, double? sw}) =>
    SvgEl._(_PathPrim(d), fill: fill, stroke: stroke, strokeWidth: sw);
SvgEl _c(double cx, double cy, double r, {Pigment? fill, Pigment? stroke = Pigment.current, double? sw}) =>
    SvgEl._(_CirclePrim(cx, cy, r), fill: fill, stroke: stroke, strokeWidth: sw);
SvgEl _r(double x, double y, double w, double h, double rx, {Pigment? fill, Pigment? stroke = Pigment.current, double? sw}) =>
    SvgEl._(_RectPrim(x, y, w, h, rx), fill: fill, stroke: stroke, strokeWidth: sw);
SvgEl _e(double cx, double cy, double rx, double ry, {double rotate = 0, Pigment? fill, Pigment? stroke}) =>
    SvgEl._(_EllipsePrim(cx, cy, rx, ry, rotate), fill: fill, stroke: stroke);

Pigment _hex(int argb) => Pigment.color(Color(argb));

class SvgArt {
  SvgArt(this.elements, {this.width = 24, this.height = 24, this.strokeWidth = 1.9, this.label});

  final List<SvgEl> elements;
  final double width;
  final double height;
  final double strokeWidth;

  /// 원본의 &lt;text&gt; 요소 (AI 아이콘)
  final ({String text, double x, double y, double size})? label;
}

/// 프로토타입(ui.js)의 직접 그린 아이콘을 그대로 옮긴 것
abstract final class AppIcons {
  static final back = SvgArt([_p('M15 5l-7 7 7 7')]);
  static final bell = SvgArt([_p('M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16z'), _p('M10 20a2 2 0 0 0 4 0')]);
  static final menu = SvgArt([_p('M4 7h16M4 12h16M4 17h16')]);
  static final refresh = SvgArt([_p('M20 11a8 8 0 1 0-2.3 5.7'), _p('M20 5v6h-6')]);
  static final send = SvgArt([_p('M4 12l16-8-6 16-2.5-6.5L4 12z')]);
  static final transfer = SvgArt([_p('M4 8h13l-3-3'), _p('M20 16H7l3 3')]);
  static final key = SvgArt([_c(8, 15, 4), _p('M11 12l8-8M16 7l2 2M14 9l2 2')]);
  static final gauge = SvgArt([_p('M4 17a8 8 0 1 1 16 0'), _p('M12 17l4-6')]);
  static final user = SvgArt([_c(12, 8, 4), _p('M4 21c1-4 4-6 8-6s7 2 8 6')]);
  static final idcard = SvgArt([
    _r(3, 5, 18, 14, 2),
    _c(9, 12, 2.2),
    _p('M14 10h4M14 14h4M6 16c.6-1.2 1.7-1.8 3-1.8s2.4.6 3 1.8'),
  ]);
  static final list = SvgArt([_p('M8 6h12M8 12h12M8 18h12'), _c(4, 6, 1), _c(4, 12, 1), _c(4, 18, 1)]);
  static final card = SvgArt([_r(3, 5, 18, 14, 2), _p('M3 10h18M7 15h3')]);
  static final coin = SvgArt([_c(12, 12, 8), _p('M9.5 9.5h4a1.5 1.5 0 0 1 0 3h-3a1.5 1.5 0 0 0 0 3h4M12 8v1.5M12 15v1.5')]);
  static final chart = SvgArt([_p('M4 20V10M10 20V4M16 20v-7M22 20H2')]);
  static final home = SvgArt([_p('M4 11l8-7 8 7v9h-5v-6H9v6H4z')]);
  static final gift = SvgArt([
    _r(4, 9, 16, 11, 1),
    _p('M3 9h18v-3H3zM12 6v14M12 6c-2-3-5-3-5-1s3 1 5 1zm0 0c2-3 5-3 5-1s-3 1-5 1z'),
  ]);
  static final product = SvgArt([_p('M4 8l8-4 8 4-8 4-8-4z'), _p('M4 12l8 4 8-4M4 16l8 4 8-4')]);
  static final spark = SvgArt([
    _p('M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z'),
    _p('M19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z'),
  ]);
  static final check = SvgArt([_p('M5 12.5l4.5 4.5L19 7.5')], strokeWidth: 2.6);
  static final clock = SvgArt([_c(12, 12, 9), _p('M12 7v5l3 2')]);
  static final alert = SvgArt([_p('M12 3l10 18H2z'), _p('M12 10v5M12 18v.5')]);
  static final question = SvgArt([_c(12, 12, 9), _p('M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7M12 17v.5')]);
  static final x = SvgArt([_p('M6 6l12 12M18 6L6 18')], strokeWidth: 2.4);
  static final lock = SvgArt([_r(5, 11, 14, 10, 2), _p('M8 11V8a4 4 0 0 1 8 0v3')]);
  static final shield = SvgArt([_p('M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z'), _p('M9 12l2 2 4-4')]);
  static final info = SvgArt([_c(12, 12, 9), _p('M12 11v6M12 7.5v.5')]);
  static final chat = SvgArt([_p('M4 5h16v11H9l-5 4z'), _p('M8 10h8M8 13h5')]);
  static final headset = SvgArt([
    _p('M4 14v-2a8 8 0 1 1 16 0v2'),
    _r(3, 14, 4, 6, 1.5),
    _r(17, 14, 4, 6, 1.5),
    _p('M19 20c0 1-1.5 2-4 2h-2'),
  ]);
  static final phone = SvgArt([_r(7, 2.5, 10, 19, 2.5), _p('M11 18.5h2')]);
  static final chevron = SvgArt([_p('M9 6l6 6-6 6')]);
  static final eyeOff = SvgArt([
    _p('M3 3l18 18'),
    _p('M10.6 5.1A10.6 10.6 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3 3.9M6.6 6.6C3.8 8.4 2 12 2 12s3.5 7 10 7c1.8 0 3.3-.5 4.6-1.2'),
  ]);
  static final wallet = SvgArt([
    _p('M4 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z'),
    _p('M4 7l11-3v3'),
    _p('M15 13.5h2'),
  ]);
  static final copy = SvgArt([_r(8, 8, 12, 12, 2), _p('M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3')]);
  static final more = SvgArt([
    _c(12, 5, 1.4, fill: Pigment.current, stroke: null),
    _c(12, 12, 1.4, fill: Pigment.current, stroke: null),
    _c(12, 19, 1.4, fill: Pigment.current, stroke: null),
  ]);
  static final gear = SvgArt([
    _c(12, 12, 3),
    _p('M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1'),
  ]);
  static final pie = SvgArt([_p('M12 3a9 9 0 1 0 9 9h-9z'), _p('M15 3.5A9 9 0 0 1 20.5 9H15z')]);
  static final stock = SvgArt([_p('M3 17l5-5 4 3 8-8'), _p('M15 7h5v5')]);
  static final plus = SvgArt([_p('M12 5v14M5 12h14')]);
  static final homeFill = SvgArt([
    _p('M12 2.8l8.4 6.1a1.6 1.6 0 0 1 .6 1.3V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-8.8a1.6 1.6 0 0 1 .6-1.3z', fill: Pigment.current, stroke: null),
    _c(12, 13.6, 1.5, fill: _hex(0xFFFFFFFF), stroke: null),
  ]);

  static final play = SvgArt([_p('M7 4.5v15l12.5-7.5z', fill: Pigment.current, stroke: null)]);

  /// 하단 탭 '상품' (가방)
  static final bag = SvgArt([_r(4, 4, 16, 17, 3.5), _p('M9 4v2.5a3 3 0 0 0 6 0V4')]);

  /// 하단 탭 '주식' (네모 안 차트)
  static final stockBox = SvgArt([_r(3.5, 3.5, 17, 17, 3.5), _p('M7 15l3.2-3.6 2.6 2.2L17 8.8')]);

  /// 공지 카드 종 (채움)
  static final bellFill = SvgArt([
    _p('M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16z', fill: Pigment.current, stroke: null),
    _p('M10 20a2 2 0 0 0 4 0', fill: Pigment.current, stroke: null),
  ]);

  /// 챗봇 '톡상담' (말풍선)
  static final talk = SvgArt([
    _p('M12 4.5c4.4 0 8 2.8 8 6.3s-3.6 6.3-8 6.3c-.9 0-1.8-.1-2.6-.3L5.3 19l1-3.3C4.9 14.5 4 12.7 4 10.8c0-3.5 3.6-6.3 8-6.3z'),
    _c(9, 10.8, .9, fill: Pigment.current, stroke: null),
    _c(12, 10.8, .9, fill: Pigment.current, stroke: null),
    _c(15, 10.8, .9, fill: Pigment.current, stroke: null),
  ]);

  /// 챗봇 첫 인사 아바타 (자체 제작 선 그림)
  static final robotFace = SvgArt(
    [
      _p('M20 11V7.5', stroke: _hex(0xFF2F3E7A), sw: 1.8),
      _c(20, 6.5, 1.6, fill: _hex(0xFF2F3E7A), stroke: null),
      _r(7.5, 16, 3, 7, 1.5, fill: _hex(0xFF5B8DEF), stroke: null),
      _r(29.5, 16, 3, 7, 1.5, fill: _hex(0xFF5B8DEF), stroke: null),
      _r(10, 11, 20, 17, 7, fill: _hex(0xFFFFFFFF), stroke: _hex(0xFF2F3E7A), sw: 1.8),
      _c(16, 18.5, 1.6, fill: _hex(0xFF2F3E7A), stroke: null),
      _c(24, 18.5, 1.6, fill: _hex(0xFF2F3E7A), stroke: null),
      _p('M16.5 22.5c2 1.6 5 1.6 7 0', stroke: _hex(0xFF2F3E7A), sw: 1.6),
    ],
    width: 40,
    height: 40,
  );
  static final ai = SvgArt(
    [
      _c(13, 15, 10),
      _p('M23 0.5l1.1 3 3 1.1-3 1.1-1.1 3-1.1-3-3-1.1 3-1.1z', fill: _hex(0xFF6E5BFF), stroke: null),
    ],
    width: 28,
    height: 28,
    label: (text: 'AI', x: 13, y: 18.8, size: 10.5),
  );
  static final robot = SvgArt(
    [
      _r(9, 13, 22, 17, 7, fill: _hex(0xFFFFFFFF), stroke: null),
      _c(16, 21.5, 2, fill: _hex(0xFF2488F3), stroke: null),
      _c(24, 21.5, 2, fill: _hex(0xFF2488F3), stroke: null),
      _p('M20 13V9', stroke: _hex(0xFFFFFFFF), sw: 2),
      _c(20, 8, 2, fill: _hex(0xFFFFFFFF), stroke: null),
    ],
    width: 40,
    height: 40,
  );

  /// 홈 상단 일러스트(자체 제작 장식)
  static final homeArt = SvgArt(
    [
      _r(34, 14, 78, 70, 10, fill: _hex(0xFFFFFFFF), stroke: _hex(0xFFCFE3F7), sw: 2),
      _r(42, 22, 28, 54, 4, fill: _hex(0xFFD6ECFF), stroke: null),
      _r(76, 22, 28, 54, 4, fill: _hex(0xFFD6ECFF), stroke: null),
      _c(94, 36, 6, fill: _hex(0xFFFFF4C7), stroke: null),
      _r(150, 26, 52, 38, 6, fill: _hex(0xFFFFFFFF), stroke: _hex(0xFFCFE3F7), sw: 2),
      _p('M156 58l12-14 9 9 7-6 12 11z', fill: _hex(0xFFBFE3C9), stroke: null),
      _p('M262 0v26', stroke: _hex(0xFFB9C7D6), sw: 2),
      _p('M246 40a16 14 0 0 1 32 0z', fill: _hex(0xFFFFD66B), stroke: null),
      _r(292, 78, 26, 24, 5, fill: _hex(0xFFF2C9A5), stroke: null),
      _e(298, 66, 8, 15, rotate: -18, fill: _hex(0xFF86D1A6)),
      _e(312, 64, 8, 16, rotate: 16, fill: _hex(0xFF6CC497)),
      _e(226, 98, 14, 4, fill: _hex(0xFFFFD66B)),
      _e(226, 93, 14, 4, fill: _hex(0xFFFFE08A)),
      _e(226, 88, 14, 4, fill: _hex(0xFFFFE9A8)),
    ],
    width: 360,
    height: 120,
  );
}

class SvgIcon extends StatelessWidget {
  const SvgIcon(this.art, {super.key, this.size = 24, this.color, this.width, this.height});

  final SvgArt art;
  final double size;
  final double? width;
  final double? height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size * art.width / math.max(art.width, art.height);
    final h = height ?? size * art.height / math.max(art.width, art.height);
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(painter: _SvgPainter(art, color ?? IconTheme.of(context).color ?? Colors.black)),
    );
  }
}

class _SvgPainter extends CustomPainter {
  _SvgPainter(this.art, this.color);

  final SvgArt art;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = math.min(size.width / art.width, size.height / art.height);
    canvas.translate((size.width - art.width * scale) / 2, (size.height - art.height * scale) / 2);
    canvas.scale(scale);
    for (final el in art.elements) {
      if (el.fill != null) {
        canvas.drawPath(el.path, Paint()..color = el.fill!.resolve(color));
      }
      if (el.stroke != null) {
        canvas.drawPath(
          el.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = el.stroke!.resolve(color)
            ..strokeWidth = el.strokeWidth ?? art.strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    final label = art.label;
    if (label != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: label.text,
          style: TextStyle(
            fontFamily: 'WooridaumB',
            fontSize: label.size,
            fontWeight: FontWeight.w400,
            color: color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // y는 기준선 위치
      final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(label.x - tp.width / 2, label.y - baseline));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgPainter old) => old.art != art || old.color != color;
}
