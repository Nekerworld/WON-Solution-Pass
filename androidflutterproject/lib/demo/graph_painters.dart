import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/fsm.dart';
import '../domain/pathfinder.dart';
import '../ui/theme.dart';

const _edge = Color(0xFF3A4A60);
const _edgeHl = Color(0xFF3FA2E8);
const _label = Color(0xFF6D7A8C);
const _labelHl = Color(0xFF7CC4FF);
const _bg = Color(0xFF0B1017);

enum NodeLook { normal, visited, current, goal }

class _Node {
  _Node(this.center, this.size, this.lines, this.look);

  final Offset center;
  final Size size;
  final List<String> lines;
  final NodeLook look;
}

class _Edge {
  _Edge(this.from, this.to, this.bend, {this.highlight = false, this.dashed = false, this.label});

  final _Node from;
  final _Node to;
  final double bend;
  final bool highlight;
  final bool dashed;
  final String? label;
}

double _rectExit(double dx, double dy, double w, double h) {
  final ax = dx.abs() < 1e-9 ? 1e-9 : dx.abs();
  final ay = dy.abs() < 1e-9 ? 1e-9 : dy.abs();
  return math.min(w / 2 / ax, h / 2 / ay);
}

void _drawText(Canvas canvas, String text, Offset center, double size, Color color, {bool bold = false, bool halo = false}) {
  final style = monoStyle(size, color: color).copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, height: 1);
  if (halo) {
    final stroke = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = _bg,
          color: null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stroke.paint(canvas, center - Offset(stroke.width / 2, stroke.height / 2));
  }
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

void _paintGraph(Canvas canvas, List<_Node> nodes, List<_Edge> edges) {
  void drawEdge(_Edge e) {
    final a = e.from.center, b = e.to.center;
    final d = b - a;
    final len = d.distance == 0 ? 1.0 : d.distance;
    final ux = d.dx / len, uy = d.dy / len;
    final w = e.from.size.width, h = e.from.size.height;
    final s = _rectExit(ux, uy, w, h) + 2;
    final en = _rectExit(ux, uy, e.to.size.width, e.to.size.height) + 4;
    final p1 = Offset(a.dx + ux * s, a.dy + uy * s);
    final p2 = Offset(b.dx - ux * en, b.dy - uy * en);
    final c = Offset((p1.dx + p2.dx) / 2 - uy * e.bend, (p1.dy + p2.dy) / 2 + ux * e.bend);
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..quadraticBezierTo(c.dx, c.dy, p2.dx, p2.dy);
    final color = e.highlight ? _edgeHl : _edge;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.highlight ? 2.4 : 1.2
      ..color = e.dashed ? color.withValues(alpha: 0.6) : color;
    if (e.dashed) {
      for (final m in path.computeMetrics()) {
        var t = 0.0;
        while (t < m.length) {
          canvas.drawPath(m.extractPath(t, t + 3), paint);
          t += 6;
        }
      }
    } else {
      canvas.drawPath(path, paint);
    }
    // 화살촉
    final dir = (p2 - c);
    final dl = dir.distance == 0 ? 1.0 : dir.distance;
    final dx = dir.dx / dl, dy = dir.dy / dl;
    const head = 6.0;
    final tip = p2 + Offset(dx, dy) * 3;
    final left = tip - Offset(dx, dy) * head + Offset(-dy, dx) * head * 0.5;
    final right = tip - Offset(dx, dy) * head - Offset(-dy, dx) * head * 0.5;
    canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(left.dx, left.dy)..lineTo(right.dx, right.dy)..close(), Paint()..color = color);
    if (e.label != null) {
      final lx = (p1.dx + 2 * c.dx + p2.dx) / 4;
      final ly = (p1.dy + 2 * c.dy + p2.dy) / 4;
      _drawText(canvas, e.label!, Offset(lx, ly - 7), 9.5, e.highlight ? _labelHl : _label, bold: e.highlight, halo: true);
    }
  }

  for (final e in edges.where((e) => !e.highlight)) {
    drawEdge(e);
  }
  for (final e in edges.where((e) => e.highlight)) {
    drawEdge(e);
  }
  for (final n in nodes) {
    final (fill, stroke, text, sw) = switch (n.look) {
      NodeLook.current => (const Color(0xFF0067AC), _edgeHl, Colors.white, 1.5),
      NodeLook.goal => (const Color(0xFF0F2A20), AppColors.success, const Color(0xFF86EFAC), 1.5),
      NodeLook.visited => (const Color(0xFF141C27), const Color(0xFF2F6FA3), const Color(0xFFB5D6F2), 1.0),
      NodeLook.normal => (const Color(0xFF141C27), const Color(0xFF2B3646), const Color(0xFF7F8B9B), 1.0),
    };
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: n.center, width: n.size.width, height: n.size.height), const Radius.circular(7));
    canvas.drawRRect(rect, Paint()..color = fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = stroke,
    );
    if (n.lines.length == 1) {
      _drawText(canvas, n.lines.first, n.center, 10.5, text, bold: n.look == NodeLook.current);
    } else {
      _drawText(canvas, n.lines[0], n.center - const Offset(0, 7), 10.5, text, bold: n.look == NodeLook.current);
      _drawText(canvas, n.lines[1], n.center + const Offset(0, 8), 9.5, n.look == NodeLook.current ? Colors.white : const Color(0xFF5B6879));
    }
  }
}

const Map<FsmState, Offset> _fsmPos = {
  FsmState.idle: Offset(70, 28),
  FsmState.diagnosing: Offset(215, 28),
  FsmState.planReady: Offset(375, 28),
  FsmState.waitingUser: Offset(530, 28),
  FsmState.readyToRetry: Offset(215, 108),
  FsmState.rechecking: Offset(450, 108),
  FsmState.completed: Offset(70, 188),
  FsmState.verifying: Offset(215, 188),
  FsmState.escalated: Offset(450, 188),
  FsmState.resultUncertain: Offset(215, 268),
};

/// 전이 테이블을 그대로 그래프로 그린다. 현재 상태와 마지막 전이를 강조한다.
class FsmGraphPainter extends CustomPainter {
  FsmGraphPainter(this.current, this.history);

  static const Size canvasSize = Size(600, 296);

  final FsmState current;
  final List<TransitionRecord> history;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / canvasSize.width);
    const nodeSize = Size(118, 28);
    final last = history.isEmpty ? null : history.last;
    final visited = <FsmState>{for (final h in history) ...[h.from, h.to]};
    final nodes = <FsmState, _Node>{
      for (final st in FsmState.values)
        st: _Node(
          _fsmPos[st]!,
          nodeSize,
          [st.code],
          st == current ? NodeLook.current : (visited.contains(st) ? NodeLook.visited : NodeLook.normal),
        ),
    };
    final pairs = <(FsmState, FsmState), List<FsmEvent>>{};
    fsmTransitions.forEach((from, t) {
      t.forEach((ev, to) => pairs.putIfAbsent((from, to), () => []).add(ev));
    });
    final edges = <_Edge>[];
    pairs.forEach((k, evs) {
      final (from, to) = k;
      final isLast = last != null && last.from == from && last.to == to;
      final isEsc = evs.length == 1 && evs.first == FsmEvent.escalate;
      final bend = from == FsmState.escalated && to == FsmState.idle ? 60.0 : 14.0;
      edges.add(_Edge(
        nodes[from]!,
        nodes[to]!,
        bend,
        highlight: isLast,
        dashed: !isLast && isEsc,
        label: isLast ? last.event.code : (evs.contains(FsmEvent.newCase) ? 'NEW_CASE' : null),
      ));
    });
    _paintGraph(canvas, nodes.values.toList(), edges);
  }

  @override
  bool shouldRepaint(FsmGraphPainter old) => true;
}

const _actionShort = {
  'COMPLETE_KYC': '고객확인',
  'REGISTER_OTP': 'OTP 등록',
  'CHANGE_TRANSFER_LIMIT': '한도 변경',
  'RETURN_TO_TRANSFER': '이체 복귀',
};

String actionShort(String id) => _actionShort[id] ?? id;

const _factShort = [
  ('kycCompleted', 'KYC'),
  ('otpRegistered', 'OTP'),
  ('limitSufficient', '한도'),
  ('returnedToTransfer', '복귀'),
];

/// 경로 탐색이 만든 상태 그래프와 다익스트라 최소 비용 경로
class StateGraphPainter extends CustomPainter {
  StateGraphPainter(this.graph) {
    final shown = _factShort.where((f) => graph.nodes.map((n) => n.facts[f.$1]).toSet().length > 1 || f.$1 == 'returnedToTransfer').toList();
    _shown = shown;
    final byDepth = <int, List<SerializedNode>>{};
    for (final n in graph.nodes) {
      byDepth.putIfAbsent(n.depth, () => []).add(n);
    }
    final cols = byDepth.isEmpty ? 1 : byDepth.keys.reduce(math.max) + 1;
    final rows = byDepth.values.map((c) => c.length).fold(1, math.max);
    _nw = math.max(100, shown.length * 31 + 12).toDouble();
    final colGap = _nw + 80;
    size = Size(math.max(600, _nw + colGap * (cols - 1) + 24), rows * 66.0 + 34);
    byDepth.forEach((d, col) {
      for (var i = 0; i < col.length; i++) {
        _pos[col[i].key] = Offset(12 + _nw / 2 + d * colGap, 22 + ((i + 0.5) * (size.height - 34)) / col.length);
      }
    });
  }

  final SerializedGraph graph;
  late final List<(String, String)> _shown;
  late final double _nw;
  late final Size size;
  final Map<String, Offset> _pos = {};

  @override
  void paint(Canvas canvas, Size s) {
    canvas.scale(s.width / size.width);
    final onPath = <String>{graph.startKey, for (final e in graph.edges) if (e.onPath) e.to};
    final nodes = <String, _Node>{};
    for (final n in graph.nodes) {
      final facts = _shown.map((f) => '${f.$2}${n.facts[f.$1] == true ? '✓' : '✗'}').join(' ');
      final isStart = n.key == graph.startKey;
      final sub = isStart ? '현재 · d=0' : '${n.goal ? '목표 · ' : ''}${n.dist == null ? '미탐색' : 'd=${n.dist}'}';
      nodes[n.key] = _Node(
        _pos[n.key]!,
        Size(_nw, 44),
        [facts, sub],
        isStart ? NodeLook.current : (n.goal ? NodeLook.goal : (onPath.contains(n.key) ? NodeLook.visited : NodeLook.normal)),
      );
    }
    final edges = [
      for (final e in graph.edges)
        _Edge(nodes[e.from]!, nodes[e.to]!, e.onPath ? 0 : 10, highlight: e.onPath, label: '${actionShort(e.actionId)} · ${e.weight}'),
    ];
    _paintGraph(canvas, nodes.values.toList(), edges);
  }

  @override
  bool shouldRepaint(StateGraphPainter old) => old.graph != graph;
}
