import 'dart:ui';

final RegExp _token = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

/// SVG path 데이터(d 속성)를 Path로 변환한다. M L H V C S Q T A Z와 상대 좌표를 지원한다.
Path parseSvgPath(String d) {
  final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0;
  var startX = 0.0, startY = 0.0;
  // 직전 곡선의 제어점 (S/T 반사용)
  double? lastCx, lastCy;
  var lastCmd = '';

  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCmd(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd.isEmpty) {
      break;
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0;
    final oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + next();
        y = oy + next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // 이후 좌표 쌍은 L로 해석
        cmd = rel ? 'l' : 'L';
        lastCx = null;
      case 'L':
        x = ox + next();
        y = oy + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'H':
        x = ox + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'V':
        y = oy + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'C':
        final x1 = ox + next(), y1 = oy + next();
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
      case 'S':
        final reflect = 'CS'.contains(lastCmd.toUpperCase()) && lastCx != null;
        final x1 = reflect ? 2 * x - lastCx : x;
        final y1 = reflect ? 2 * y - lastCy! : y;
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
      case 'Q':
        final x1 = ox + next(), y1 = oy + next();
        x = ox + next();
        y = oy + next();
        path.quadraticBezierTo(x1, y1, x, y);
        lastCx = x1;
        lastCy = y1;
      case 'T':
        final reflect = 'QT'.contains(lastCmd.toUpperCase()) && lastCx != null;
        final x1 = reflect ? 2 * x - lastCx : x;
        final y1 = reflect ? 2 * y - lastCy! : y;
        x = ox + next();
        y = oy + next();
        path.quadraticBezierTo(x1, y1, x, y);
        lastCx = x1;
        lastCy = y1;
      case 'A':
        final rx = next(), ry = next(), rot = next();
        final large = next() != 0, sweep = next() != 0;
        x = ox + next();
        y = oy + next();
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rot,
          largeArc: large,
          clockwise: sweep,
        );
        lastCx = null;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        lastCx = null;
      default:
        i++;
    }
    lastCmd = cmd;
  }
  return path;
}
