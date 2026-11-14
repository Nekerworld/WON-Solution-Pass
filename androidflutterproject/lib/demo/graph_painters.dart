import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/fsm.dart';
import '../domain/pathfinder.dart';
import '../ui/theme.dart';

const _edge = Color(0xFF3A4A60);
const _edgeP = Color(0xFFD69A2D);
const _edgeS = Color(0xFF6D7A8C);
const _edgeHl = Color(0xFF3FA2E8);
const _labelHl = Color(0xFF7CC4FF);
const _bg = Color(0xFF0B1017);

enum NodeLook { normal, visited, current, goal }

enum EdgeKind { workflow, proposal, safety }

class _Node {
  _Node(this.center, this.size, this.lines, this.look);

  final Offset center;
  final Size size;
  final List<String> lines;
  final NodeLook look;
}

class _Edge {
  _Edge(this.from, this.to, this.bend, {this.kind = EdgeKind.workflow, this.highlight = false, this.dashed = false, this.label});

  final _Node from;
  final _Node to;
  final double bend;
  final EdgeKind kind;
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

void _dashPath(Canvas canvas, Path path, Paint paint, double on, double off) {
  for (final m in path.computeMetrics()) {
    var t = 0.0;
    while (t < m.length) {
      canvas.drawPath(m.extractPath(t, t + on), paint);
      t += on + off;
    }
  }
}

void _paintGraph(Canvas canvas, List<_Node> nodes, List<_Edge> edges) {
  void drawEdge(_Edge e) {
    final a = e.from.center, b = e.to.center;
    final d = b - a;
    final len = d.distance == 0 ? 1.0 : d.distance;
    final ux = d.dx / len, uy = d.dy / len;
    final s = _rectExit(ux, uy, e.from.size.width, e.from.size.height) + 2;
    final en = _rectExit(ux, uy, e.to.size.width, e.to.size.height) + 4;
    final p1 = Offset(a.dx + ux * s, a.dy + uy * s);
    final p2 = Offset(b.dx - ux * en, b.dy - uy * en);
    final c = Offset((p1.dx + p2.dx) / 2 - uy * e.bend, (p1.dy + p2.dy) / 2 + ux * e.bend);
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..quadraticBezierTo(c.dx, c.dy, p2.dx, p2.dy);
    final color = e.highlight
        ? _edgeHl
        : switch (e.kind) {
            EdgeKind.workflow => _edge,
            EdgeKind.proposal => _edgeP,
            EdgeKind.safety => _edgeS,
          };
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.highlight ? 2.4 : 1.2
      ..color = color;
    if (!e.highlight && e.kind == EdgeKind.proposal) {
      _dashPath(canvas, path, paint..color = color.withValues(alpha: 0.85), 5, 3);
    } else if (!e.highlight && (e.kind == EdgeKind.safety || e.dashed)) {
      _dashPath(canvas, path, paint, 2, 3);
    } else {
      canvas.drawPath(path, paint);
    }
    final dir = p2 - c;
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
      _drawText(canvas, e.label!, Offset(lx, ly - 7), 9.5, _labelHl, bold: true, halo: true);
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
      _drawText(canvas, n.lines.first, n.center, 9.5, text, bold: n.look == NodeLook.current);
    } else {
      _drawText(canvas, n.lines[0], n.center - const Offset(0, 7), 10.5, text, bold: n.look == NodeLook.current);
      _drawText(canvas, n.lines[1], n.center + const Offset(0, 8), 9.5, n.look == NodeLook.current ? Colors.white : const Color(0xFF5B6879));
    }
  }
}

/* ==================================================================
 * 상태머신 그래프: 전이 테이블에서 BFS 깊이로 층을 나눠 위→아래로 배치한다
 * ================================================================== */

class FsmLayout {
  FsmLayout._(this.pos, this.size);

  static const double nodeW = 112;
  static const double nodeH = 24;

  final Map<String, Offset> pos;
  final Size size;

  static final Map<FsmKind, FsmLayout> _cache = {};

  static FsmLayout of(FsmKind kind) => _cache.putIfAbsent(kind, () {
        final def = fsmDefs[kind]!;
        final tbl = fsmTables[kind]!;
        final depth = <String, int>{def.initial: 0};
        final q = [def.initial];
        while (q.isNotEmpty) {
          final s = q.removeAt(0);
          for (final e in (tbl.table[s] ?? const <String, String>{}).entries) {
            if (e.key == 'EXIT' || e.key == 'NEW_CASE') continue;
            if (!depth.containsKey(e.value)) {
              depth[e.value] = depth[s]! + 1;
              q.add(e.value);
            }
          }
        }
        final layers = <int, List<String>>{};
        for (final s in tbl.states) {
          layers.putIfAbsent(depth[s] ?? 0, () => []).add(s);
        }
        final maxCols = layers.values.map((l) => l.length).fold(1, math.max);
        final vw = math.max(560.0, maxCols * (nodeW + 16) + 16);
        const rowGap = 46.0;
        final pos = <String, Offset>{};
        final maxDepth = layers.keys.fold(0, math.max);
        layers.forEach((d, l) {
          for (var i = 0; i < l.length; i++) {
            pos[l[i]] = Offset((i + 0.5) * vw / l.length, 20 + d * rowGap);
          }
        });
        return FsmLayout._(pos, Size(vw, 20 + maxDepth * rowGap + 22));
      });
}

class FsmGraphPainter extends CustomPainter {
  FsmGraphPainter({required this.kind, required this.current, required this.history, required this.showExit});

  final FsmKind kind;
  final String current;
  final List<TransitionRecord> history;
  final bool showExit;

  Size get canvasSize => FsmLayout.of(kind).size;

  /// 공통 종료(P8) 간선 중 숨긴 개수
  int get hiddenExits => showExit ? 0 : fsmDefs[kind]!.edges.where((e) => e.$2 == 'EXIT').length;

  @override
  void paint(Canvas canvas, Size size) {
    final l = FsmLayout.of(kind);
    canvas.scale(size.width / l.size.width);
    const nodeSize = Size(FsmLayout.nodeW, FsmLayout.nodeH);
    final last = history.isEmpty ? null : history.last;
    final visited = <String>{for (final h in history) ...[h.from, h.to]};
    final nodes = <String, _Node>{
      for (final st in fsmTables[kind]!.states)
        st: _Node(l.pos[st]!, nodeSize, [st], st == current ? NodeLook.current : (visited.contains(st) ? NodeLook.visited : NodeLook.normal)),
    };
    final pairs = <(String, String), (List<String>, String)>{};
    for (final e in fsmDefs[kind]!.edges) {
      if (!showExit && e.$2 == 'EXIT') continue;
      final k = (e.$1, e.$3);
      final p = pairs[k];
      if (p == null) {
        pairs[k] = ([e.$2], e.$4);
      } else {
        p.$1.add(e.$2);
        if (e.$4 != 'D') pairs[k] = (p.$1, e.$4);
      }
    }
    final edges = <_Edge>[];
    pairs.forEach((k, v) {
      final a = nodes[k.$1]!, b = nodes[k.$2]!;
      final back = b.center.dy <= a.center.dy;
      final isLast = last != null && last.from == k.$1 && last.to == k.$2;
      final src = v.$2;
      edges.add(_Edge(
        a,
        b,
        back ? 40 : 10,
        kind: src == 'D' ? EdgeKind.workflow : (src == 'S' ? EdgeKind.safety : EdgeKind.proposal),
        highlight: isLast,
        label: isLast ? '${last.event}${last.src != 'D' ? ' (${last.src})' : ''}' : null,
      ));
    });
    _paintGraph(canvas, nodes.values.toList(), edges);
  }

  @override
  bool shouldRepaint(FsmGraphPainter old) => true;
}

/* ==================================================================
 * 해결 경로 상태 그래프 (다익스트라)
 * ================================================================== */

const Map<String, String> actionShort = {
  'ID_CARD_VERIFY': '신분증',
  'MOBILE_ID_VERIFY': '모바일신분증',
  'OPEN_ACCOUNT_OTHERBANK': '계좌(타행)',
  'OPEN_ACCOUNT_CERT': '계좌(인증서)',
  'ISSUE_CERT': '인증서',
  'KYC_UPDATE': '고객정보',
  'FX_REGISTER': '외환신청',
  'OPEN_FX_ACCOUNT': '외화계좌',
  'INVESTOR_PROFILE': '투자성향',
};

class StateGraphPainter extends CustomPainter {
  StateGraphPainter(this.graph) {
    final byDepth = <int, List<GraphNode>>{};
    for (final n in graph.nodes) {
      byDepth.putIfAbsent(n.depth, () => []).add(n);
    }
    final depths = byDepth.isEmpty ? 1 : byDepth.keys.reduce(math.max) + 1;
    final rows = byDepth.values.map((c) => c.length).fold(1, math.max);
    _blockH = rows * (_nh + 14);
    final blocks = (depths / _per).ceil();
    size = Size(_per * _nw + (_per - 1) * _cg + 24, blocks * _blockH + (blocks - 1) * _rg + 12);
    byDepth.forEach((d, col) {
      for (var i = 0; i < col.length; i++) {
        final bi = d ~/ _per;
        _pos[col[i].key] = Offset(12 + _nw / 2 + (d % _per) * (_nw + _cg), 6 + bi * (_blockH + _rg) + (i + 0.5) * _blockH / col.length);
      }
    });
  }

  static const int _per = 4;
  static const double _nw = 96;
  static const double _nh = 36;
  static const double _cg = 40;
  static const double _rg = 26;

  final SerializedGraph graph;
  late final double _blockH;
  late final Size size;
  final Map<String, Offset> _pos = {};

  @override
  void paint(Canvas canvas, Size s) {
    canvas.scale(s.width / size.width);
    final onPath = <String>{graph.startKey, for (final e in graph.edges) if (e.onPath) e.to};
    final inEdge = <String, GraphEdge>{};
    for (final e in graph.edges) {
      if (inEdge[e.to] == null || e.onPath) inEdge[e.to] = e;
    }
    final nodes = <String, _Node>{};
    for (final n in graph.nodes) {
      final isStart = n.key == graph.startKey;
      final e = inEdge[n.key];
      final label = isStart ? '현재' : (e != null ? (actionShort[e.actionId] ?? e.actionId) : '?');
      final sub = isStart ? 'd=0' : '${n.goal ? '목표 · ' : ''}${n.dist == null ? '미탐색' : 'd=${n.dist}'}';
      nodes[n.key] = _Node(
        _pos[n.key]!,
        const Size(_nw, _nh),
        [label, sub],
        isStart ? NodeLook.current : (n.goal ? NodeLook.goal : (onPath.contains(n.key) ? NodeLook.visited : NodeLook.normal)),
      );
    }
    _Edge edgeOf(GraphEdge e) {
      final a = nodes[e.from]!, b = nodes[e.to]!;
      final wrap = b.center.dy - a.center.dy > _blockH / 2;
      return _Edge(a, b, e.onPath ? (wrap ? -20 : 0) : 12, highlight: e.onPath, dashed: !e.onPath && e.unknown);
    }

    _paintGraph(canvas, nodes.values.toList(), [for (final e in graph.edges) edgeOf(e)]);
  }

  @override
  bool shouldRepaint(StateGraphPainter old) => old.graph != graph;
}
