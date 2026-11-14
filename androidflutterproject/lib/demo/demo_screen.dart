import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/asset_advisor.dart' as aa;
import '../domain/bank_state.dart';
import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/pathfinder.dart';
import '../domain/scenario.dart';
import '../ui/app_scope.dart';
import '../ui/theme.dart';
import 'graph_painters.dart';
import 'self_test.dart';

const _panelBg = Color(0xFF10161F);
const _panelText = Color(0xFFD7DEE8);
const _muted = Color(0xFF7F8B9B);
const _dim = Color(0xFF5B6879);
const _accent = Color(0xFF7CC4FF);
const _boxBg = Color(0xFF0B1017);
const _boxBorder = Color(0xFF1E2734);
const _btnBg = Color(0xFF18212D);
const _btnBorder = Color(0xFF2B3646);
const _ok = Color(0xFF4ADE80);
const _bad = Color(0xFFF87171);
const _warn = Color(0xFFFBBF24);
const _proposal = Color(0xFFD69A2D);

const Map<String, Color> _statusColor = {'MET': _ok, 'UNMET': _bad, 'UNKNOWN': _warn, 'IN_PROGRESS': _accent};

const List<String> _phases = ['자산관리 상담', '상품 선택', '가입 지원', '가입 완료'];

const List<(FsmKind, String)> _tracks = [
  (FsmKind.join, '가입 지원(AI)'),
  (FsmKind.direct, '직접 가입'),
  (FsmKind.asset, '자산관리'),
];

/// 시연 제어 화면. 시연용 도구이며 실제 앱 기능이 아니다.
/// 은행 상태를 바꾸지 않고 관찰만 한다 (데모 초기화·자가 테스트 제외).
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  FsmKind _track = FsmKind.join;

  /// 탭을 직접 고르기 전까지는 방금 상태가 바뀐 트랙을 따라간다
  bool _pinned = false;
  bool _showExit = false;
  bool _testing = false;
  SelfTestReport? _report;
  final List<SelfTestResult> _partial = [];
  AppServices? _services;
  final Map<FsmKind, int> _histLen = {};
  final Map<FsmKind, VoidCallback> _fsmListeners = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (identical(s, _services)) return;
    _detach();
    _services = s;
    for (final e in s.controller.fsms.entries) {
      _histLen[e.key] = e.value.history().length;
      void listener() {
        final n = e.value.history().length;
        final grew = n > (_histLen[e.key] ?? 0);
        _histLen[e.key] = n;
        if (grew && !_pinned && mounted) setState(() => _track = e.key);
      }

      _fsmListeners[e.key] = listener;
      e.value.addListener(listener);
    }
  }

  void _detach() {
    final s = _services;
    if (s == null) return;
    _fsmListeners.forEach((k, l) => s.controller.fsms[k]?.removeListener(l));
    _fsmListeners.clear();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  Future<void> _runTests() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _report = null;
      _partial.clear();
    });
    final events = _services!.events;
    events.add('TEST', '자가 테스트 시작 ($selfTestCount개)');
    try {
      final r = await runSelfTests(onProgress: (x) {
        if (mounted) setState(() => _partial.add(x));
      });
      events.add('TEST', '자가 테스트 완료: ${r.passed}/${r.total} 통과');
      if (mounted) setState(() => _report = r);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final app = s.controller;
    return Scaffold(
      backgroundColor: _panelBg,
      body: SafeArea(
        child: DefaultTextStyle(
          style: ts(12.5, color: _panelText),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF222C3A)))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DEMO CONTROL', style: ts(14, weight: FontWeight.w700, color: Colors.white, letterSpacing: 0.04)),
                          const SizedBox(height: 2),
                          Text('시연용 도구 · 실제 앱 기능 아님', style: ts(11, color: _muted)),
                        ],
                      ),
                    ),
                    _DpButton('데모 초기화', danger: true, onTap: () {
                      app.resetDemo();
                      Navigator.of(context).pop();
                    }),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: _panelText),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([s.store, s.events, app, s.ai, s.pathfinder, ...app.fsms.values]),
                  builder: (context, _) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    children: _sections(s),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(AppServices s) {
    final st = s.store.state;
    final last = s.pathfinder.lastResult;
    return [
      _scenarioSection(),
      _progressSection(s, st, last),
      _testSection(),
      _fsmSection(s),
      _condSection(s, st),
      _pathSection(last),
      _aiSection(s),
      _infoSection(s),
      _jsonSection(st),
      _logSection(s),
    ];
  }

  /* ---------------- 시나리오 ---------------- */
  Widget _scenarioSection() {
    final c = BankState.initial().customer;
    return _Section(
      title: '시나리오',
      tag: Policy.version,
      children: [
        _Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DemoScenario.title, style: ts(13, weight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 4),
              Text('${c.name}(${c.age}) · ${DemoScenario.givens.join(' · ')}', style: ts(11.5, color: _muted, height: 1.5)),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: '고객 답변: '),
                  for (var i = 0; i < DemoScenario.customerAnswers.length; i++) ...[
                    if (i > 0) const TextSpan(text: ' · '),
                    TextSpan(text: '${DemoScenario.customerAnswers[i].$1} '),
                    TextSpan(text: DemoScenario.customerAnswers[i].$2, style: weightStyle(FontWeight.w700, color: Colors.white)),
                  ],
                ]),
                style: ts(11.5, color: _panelText),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /* ---------------- 진행 과정 ---------------- */
  Widget _progressSection(AppServices s, BankState st, RouteResult? last) {
    final app = s.controller;
    final sess = app.session;
    final apps = st.applications.values.where((a) => a.productId == DemoScenario.productId).toList();
    final opened = apps.any((a) => a.status == 'SUCCESS');
    final joining = (app.joinFsm.state != 'IDLE' && sess.join?.productId == DemoScenario.productId) ||
        (app.directFsm.state != 'IDLE' && sess.direct?.productId == DemoScenario.productId);
    final assetState = app.assetFsm.state;
    final phase = opened
        ? _phases.length
        : joining
            ? 2
            : const ['EXPLORE', 'TO_JOIN', 'CLOSED'].contains(assetState)
                ? 1
                : assetState != 'IDLE'
                    ? 0
                    : -1;

    var curFound = false;
    var done = 0, total = 0;
    final stages = <(String label, List<(String, bool, bool)> items, String cls)>[];
    for (final stg in DemoScenario.stages) {
      final items = <(String, bool, bool)>[
        for (final k in stg.facts) (factLabel(k), st.facts[k] == true, st.pending[k] != null),
        if (stg.application != null)
          ('${getProduct(stg.application)?.name ?? stg.application} 개설', opened, apps.any((a) => a.status == 'PENDING' || a.status == 'UNKNOWN')),
      ];
      total += items.length;
      done += items.where((i) => i.$2).length;
      final all = items.every((i) => i.$2);
      var cls = all ? 'done' : '';
      if (!all && !curFound) {
        curFound = true;
        cls = 'cur';
      }
      stages.add((stg.label, items, cls));
    }

    String next = '';
    if (opened) {
      next = '해외주식 계좌 개설 완료 (은행 처리 결과로 확인)';
    } else if (app.joinFsm.state == 'READY_TO_APPLY') {
      next = '고객 승인 대기: 가입 정보 확인 화면';
    } else if (app.joinFsm.state == 'CLARIFYING') {
      next = '고객 답변 대기';
    } else if (joining && last != null && last.status == 'PLAN' && last.steps.isNotEmpty) {
      next = '남은 업무 ${last.steps.length}개 · 다음: ${last.steps.first.label}';
    } else if (phase == 1) {
      next = '고객이 상품을 고르면 가입 지원이 시작돼요';
    } else if (phase == 0) {
      next = '자산관리 상담 진행 중';
    } else if (phase == -1) {
      next = '홈에서 AI 자산관리 상담으로 시작';
    }

    Color phaseColor(int i) => i < phase ? _ok : (i == phase ? _accent : _dim);

    return _Section(
      title: '진행 과정',
      tag: '$done / $total',
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _phases.length; i++) ...[
              if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: ts(12, color: _dim))),
              Text(_phases[i], style: ts(11.5, weight: i == phase ? FontWeight.w700 : FontWeight.w400, color: phaseColor(i))),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < stages.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stages[i].$3 == 'cur' ? const Color(0xFF0B2A44) : _btnBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: stages[i].$3 == 'done' ? const Color(0xFF1F6B3F) : (stages[i].$3 == 'cur' ? const Color(0xFF2F6FA3) : _btnBorder)),
                ),
                child: Text(
                  '${stages[i].$3 == 'done' ? '✓' : i + 1} ${stages[i].$1}',
                  style: ts(11, weight: stages[i].$3 == 'cur' ? FontWeight.w700 : FontWeight.w400, color: stages[i].$3 == 'done' ? _ok : (stages[i].$3 == 'cur' ? Colors.white : _muted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final stg in stages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(stg.$1, style: ts(11.5, weight: FontWeight.w700, color: stg.$3 == 'cur' ? Colors.white : _muted)),
                for (final it in stg.$2)
                  Text(
                    '${it.$2 ? '✓' : (it.$3 ? '…' : '○')} ${it.$1}',
                    style: ts(11.5, color: it.$2 ? _ok : (it.$3 ? _warn : _dim)),
                  ),
              ],
            ),
          ),
        if (next.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFF0B2A44), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1D4F7A))),
            child: Text(next, style: ts(12, weight: FontWeight.w700, color: _accent)),
          ),
      ],
    );
  }

  /* ---------------- 자가 테스트 ---------------- */
  Widget _testSection() {
    final r = _report;
    final shown = r?.results ?? _partial;
    final passed = shown.where((x) => x.ok).length;
    final failed = shown.length - passed;
    return _Section(
      title: '자가 테스트',
      action: _DpButton(_testing ? '실행 중...' : '실행', primary: true, onTap: _testing ? null : _runTests),
      children: [
        if (shown.isEmpty && !_testing)
          const _Note('검증 항목을 앱 안에서 실행합니다. 테스트마다 별도의 가상 은행을 만들어 돌리므로 시연 중인 상태는 바뀌지 않아요.')
        else ...[
          Text(
            r != null ? '${r.passed} / ${r.total} 통과${r.failed > 0 ? ' · ${r.failed} 실패' : ''}' : '실행 중... $passed / $selfTestCount${failed > 0 ? ' · $failed 실패' : ''}',
            style: ts(12.5, weight: FontWeight.w700, color: failed > 0 ? _bad : (r != null ? _ok : _accent)),
          ),
          const SizedBox(height: 4),
          for (final x in shown)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${x.ok ? '✔' : '✘'} ${x.name}${x.ok ? '' : ' — ${x.detail ?? ''}'}',
                style: ts(11.5, color: x.ok ? _ok : _bad, height: 1.45),
              ),
            ),
        ],
      ],
    );
  }

  /* ---------------- 상태머신 ---------------- */
  Widget _fsmSection(AppServices s) {
    final f = s.controller.fsms[_track]!;
    final hist = f.history();
    final painter = FsmGraphPainter(kind: _track, current: f.state, history: hist, showExit: _showExit);
    return _Section(
      title: '상태머신',
      tag: f.state,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (k, label) in _tracks)
              _DpButton(label, active: _track == k, onTap: () => setState(() {
                    _track = k;
                    _pinned = true;
                  })),
            _DpButton('종료 간선', active: _showExit, tooltip: '공통 종료(P8) 간선 표시', onTap: () => setState(() => _showExit = !_showExit)),
          ],
        ),
        const SizedBox(height: 8),
        _GraphBox(width: painter.canvasSize.width, height: painter.canvasSize.height, painter: painter),
        if (painter.hiddenExits > 0) _Note('공통 종료(P8) 간선 ${painter.hiddenExits}개 생략'),
        const SizedBox(height: 6),
        const Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _Legend(color: Color(0xFF3A4A60), label: '워크플로우'),
            _Legend(color: _proposal, label: '제안 전이(P1~P8)', dashed: true),
            _Legend(color: Color(0xFF7F8B9B), label: '안전 전이', dashed: true),
          ],
        ),
        const SizedBox(height: 8),
        _LogBox(
          maxHeight: 110,
          lines: hist.isEmpty
              ? [const TextSpan(text: '전이 기록 없음', style: TextStyle(color: _dim))]
              : [
                  for (final h in hist.reversed.take(8))
                    TextSpan(children: [
                      TextSpan(text: '${formatClock(h.at)} ', style: const TextStyle(color: _dim)),
                      TextSpan(text: '${h.from} '),
                      TextSpan(text: '--${h.event}--> ', style: const TextStyle(color: _accent)),
                      TextSpan(text: h.to),
                      if (h.src != 'D') TextSpan(text: ' ${h.src}', style: const TextStyle(color: _proposal)),
                    ]),
                ],
        ),
      ],
    );
  }

  /* ---------------- 가입 조건 판정 · 고객 제약 ---------------- */
  Widget _condSection(AppServices s, BankState st) {
    final j = s.controller.session.join;
    final ev = j?.evaluation;
    final product = getProduct(j?.productId) ?? products.first;
    return _Section(
      title: '가입 조건 판정 · 고객 제약',
      children: [
        _Table(
          header: ['조건 · ${product.name}', 'fact', '은행 값', '판정'],
          flex: const [3, 3, 2, 2],
          rows: [
            for (final id in product.conditions)
              () {
                final c = conditions[id]!;
                final status = ev?.conditions.where((x) => x.id == id).firstOrNull?.status;
                return [
                  Text(c.label),
                  Text(c.fact, style: monoStyle(10.5, color: _panelText)),
                  Text('${st.facts[c.fact] == true}${st.pending[c.fact] != null ? ' (처리 중)' : ''}', style: monoStyle(10.5, color: _panelText)),
                  status == null
                      ? Text('-', style: ts(11, color: _dim))
                      : Text(status, style: monoStyle(10.5, color: _statusColor[status] ?? _panelText).copyWith(fontWeight: FontWeight.w700)),
                ];
              }(),
          ],
        ),
        if (j != null) ...[
          const SizedBox(height: 8),
          _Table(
            header: const ['고객 제약', '값', '출처'],
            flex: const [3, 2, 5],
            rows: [
              for (final e in constraintLabels.entries)
                [
                  Text(e.value),
                  Text('${j.constraints[e.key]}', style: monoStyle(10.5, color: _panelText)),
                  Text(
                    j.constraintSource[e.key] == null ? '미확인' : '${j.constraintSource[e.key]!.$1} · ${j.constraintSource[e.key]!.$2}',
                    style: ts(11, color: _dim),
                  ),
                ],
            ],
          ),
          _Note(
            '질문 ${j.questionsAsked}/${Policy.joinQuestionLimit} · 반복 '
            '${j.repeat.isEmpty ? '없음' : j.repeat.entries.map((e) => '${facts[e.key]?.short ?? e.key} ${e.value}').join(', ')}'
            ' (한도 ${Policy.repeatLimit})',
          ),
        ] else
          const _Note('판정은 AI 가입 지원이 은행 기록을 조회할 때 계산돼요.'),
      ],
    );
  }

  /* ---------------- 해결 경로 ---------------- */
  Widget _pathSection(RouteResult? last) {
    final children = <Widget>[];
    if (last == null) {
      children.add(const _Note('아직 계산된 경로가 없어요. AI 가입 지원을 시작하세요.'));
    } else {
      if (last.graph == null) {
        children.add(_Note('${last.status}: 상태 그래프를 만들지 않았어요.'));
      } else {
        final painter = StateGraphPainter(last.graph!);
        children.add(_GraphBox(width: painter.size.width, height: painter.size.height, painter: painter));
      }
      final cause = last.cause;
      final opts = last.options;
      children.addAll([
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          const TextSpan(text: '상태: '),
          TextSpan(text: last.status, style: weightStyle(FontWeight.w700, color: Colors.white)),
          if (last.cost != null) ...[
            const TextSpan(text: ' · 최소 비용 '),
            TextSpan(text: '${last.cost}', style: weightStyle(FontWeight.w700, color: Colors.white)),
          ],
        ])),
        const SizedBox(height: 2),
        Text(last.steps.isEmpty ? '-' : last.steps.map((x) => actionShort[x.actionId] ?? x.actionId).join(' → '), style: monoStyle(11, color: _accent)),
        if (cause != null && cause.type == 'CYCLE')
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('순환 감지: ${cause.chain.map((f) => facts[f]?.short ?? f).join(' → ')}', style: ts(12, color: _warn)),
          )
        else if (cause != null)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('원인: ${cause.type} ${cause.fact ?? ''}', style: ts(12, color: _warn))),
        if (opts.isNotEmpty)
          _Note('다음 단계 대체 수단: ${opts.map((o) => '${o.recommended ? '★' : ''}${actionShort[o.actionId] ?? o.actionId}(${o.availability}${o.cost != null ? ',${o.cost}' : ''})').join(' · ')}'),
        if (last.questions.isNotEmpty) _Note('필요한 질문(P4): ${last.questions.join(', ')}'),
        if ((last.visited ?? 0) > 0) _Note('상태 ${last.visited}개 · 다익스트라 확정 ${last.explored ?? 0}개'),
      ]);
    }
    return _Section(title: '해결 경로 · 상태 그래프 (다익스트라)', children: children);
  }

  /* ---------------- AI 구조화 출력 ---------------- */
  Widget _aiSection(AppServices s) {
    final tr = s.ai.trace;
    final children = <Widget>[];
    if (tr.isEmpty) {
      children.add(const _Note('아직 AI 호출이 없어요.'));
    } else {
      for (final t in tr.reversed.take(6)) {
        children.add(Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: t.valid ? _boxBg : const Color(0xFF2A1215),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.valid ? _boxBorder : const Color(0xFF6B2A2D)),
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${t.id} ', style: monoStyle(10.5, color: _dim)),
              TextSpan(text: '${t.task} → '),
              TextSpan(text: t.output.intent, style: weightStyle(FontWeight.w700, color: Colors.white)),
              const TextSpan(text: ' '),
              TextSpan(text: t.valid ? '검증 통과' : '검증 실패 → 기본 선택지', style: TextStyle(color: t.valid ? _ok : _bad)),
            ]),
            style: ts(11.5, color: _panelText),
          ),
        ));
      }
      final l = tr.last;
      children.add(_Pre(
        const JsonEncoder.withIndent('  ').convert({'task': l.task, 'input': l.input, 'output': l.output.toJson(), 'valid': l.valid, 'errors': l.errors}),
        maxHeight: 200,
      ));
    }
    return _Section(title: 'AI 구조화 출력 · 검증', tag: '${tr.length}건', children: children);
  }

  /* ---------------- 자산 정보 저장소 ---------------- */
  Widget _infoSection(AppServices s) {
    final a = s.controller.session.asset;
    final info = a?.info;
    if (a == null || info == null) {
      return const _Section(title: '자산 정보 저장소 · 지표', children: [_Note('자산관리 상담에서 정보를 수집하면 표시돼요.')]);
    }
    final hist = info.history.reversed.take(6).toList();
    final metrics = a.metrics?.list ?? const <aa.Metric>[];
    return _Section(
      title: '자산 정보 저장소 · 지표',
      children: [
        _Table(
          header: const ['항목', '값', '출처'],
          flex: const [4, 3, 2],
          rows: [
            for (final e in info.items.entries)
              [
                Text(aa.itemLabel(e.key)),
                Text(e.value.value == null ? 'null' : '${e.value.value}', style: monoStyle(10.5, color: _panelText)),
                Text(sourceLabel[e.value.source] ?? e.value.source, style: ts(11, color: _muted)),
              ],
          ],
        ),
        _Note(
          '목적 ${a.purpose} · 질문 ${a.questionsAsked}/${Policy.assetQuestionLimit}'
          '${a.stopRequested ? ' · 질문 중단 요청' : ''}'
          '${info.declined.isNotEmpty ? ' · 답변 안 함: ${info.declined.join(', ')}' : ''}',
        ),
        if (hist.isNotEmpty) ...[
          const SizedBox(height: 8),
          _LogBox(maxHeight: 110, lines: [
            for (final h in hist)
              TextSpan(children: [
                TextSpan(text: '${h.key} ', style: const TextStyle(color: _accent)),
                TextSpan(text: '${h.from} → ${h.to} '),
                TextSpan(text: '${h.reason}${h.correction ? ' · 정정' : ''}', style: const TextStyle(color: _dim)),
              ]),
          ]),
        ],
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: 8),
          _LogBox(maxHeight: 140, lines: [
            for (final m in metrics)
              TextSpan(children: [
                TextSpan(text: m.key, style: const TextStyle(color: _accent)),
                TextSpan(text: ' = ${m.text} '),
                TextSpan(text: m.formula, style: const TextStyle(color: _dim)),
              ]),
          ]),
        ],
      ],
    );
  }

  /* ---------------- 은행 상태 JSON ---------------- */
  Widget _jsonSection(BankState st) {
    final j = st.toJson();
    final view = {for (final k in const ['facts', 'pending', 'simulation', 'system', 'applications', 'consultations']) k: j[k]};
    return _Section(
      title: '은행 상태 JSON',
      tag: 'v${st.system.stateVersion}',
      children: [_Pre(const JsonEncoder.withIndent('  ').convert(view), maxHeight: 220)],
    );
  }

  /* ---------------- 이벤트 로그 ---------------- */
  Widget _logSection(AppServices s) {
    final logs = s.events.list().reversed.take(60).toList();
    return _Section(
      title: '이벤트 로그',
      children: [
        _LogBox(
          maxHeight: 220,
          lines: logs.isEmpty
              ? [const TextSpan(text: '기록 없음', style: TextStyle(color: _dim))]
              : [
                  for (final l in logs)
                    TextSpan(children: [
                      TextSpan(text: '${formatClock(l.at)} ', style: const TextStyle(color: _dim)),
                      TextSpan(text: '${l.source} ', style: const TextStyle(color: _accent)),
                      TextSpan(text: l.message),
                    ]),
                ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.tag, this.action, required this.children});

  final String title;
  final String? tag;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: ts(11, weight: FontWeight.w700, color: _muted, letterSpacing: 0.06))),
              if (tag != null) Text(tag!, style: monoStyle(11, color: _accent)),
              if (action != null) ...[const SizedBox(width: 8), action!],
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: ts(11, color: _dim, height: 1.5)),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _boxBg, border: Border.all(color: _boxBorder), borderRadius: BorderRadius.circular(10)),
      child: child,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 2,
          child: dashed
              ? Row(children: [for (var i = 0; i < 4; i++) Expanded(child: Container(margin: const EdgeInsets.only(right: 2), color: color))])
              : ColoredBox(color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: ts(10.5, color: _muted)),
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.header, required this.rows, required this.flex});

  final List<String> header;
  final List<List<Widget>> rows;
  final List<int> flex;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> cells) => Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _boxBorder))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: flex[i],
                  child: Padding(padding: const EdgeInsets.only(right: 6), child: cells[i]),
                ),
            ],
          ),
        );
    return Container(
      decoration: BoxDecoration(color: _boxBg, border: Border.all(color: _boxBorder), borderRadius: BorderRadius.circular(8)),
      child: DefaultTextStyle.merge(
        style: ts(11.5, color: _panelText),
        child: Column(
          children: [
            row([for (final h in header) Text(h, style: ts(10.5, weight: FontWeight.w700, color: _muted))]),
            for (final r in rows) row(r),
          ],
        ),
      ),
    );
  }
}

class _DpButton extends StatelessWidget {
  const _DpButton(this.label, {required this.onTap, this.danger = false, this.active = false, this.primary = false, this.tooltip});

  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool active;
  final bool primary;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final hot = active || primary;
    final btn = Material(
      color: hot ? const Color(0xFF0067AC) : _btnBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hot ? const Color(0xFF0A7FD0) : (danger ? const Color(0xFF6B2A2D) : _btnBorder)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ts(12, weight: FontWeight.w700, color: hot ? Colors.white : (danger ? const Color(0xFFFFB4B6) : _panelText), height: 1.2),
          ),
        ),
      ),
    );
    final view = Opacity(opacity: onTap == null ? 0.6 : 1, child: btn);
    return tooltip == null ? view : Tooltip(message: tooltip!, child: view);
  }
}

class _GraphBox extends StatelessWidget {
  const _GraphBox({required this.width, required this.height, required this.painter});

  final double width;
  final double height;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: _boxBg, border: Border.all(color: _boxBorder), borderRadius: BorderRadius.circular(10)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: CustomPaint(size: Size(width, height), painter: painter),
      ),
    );
  }
}

class _Pre extends StatelessWidget {
  const _Pre(this.text, {required this.maxHeight});

  final String text;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: _boxBg, border: Border.all(color: _boxBorder), borderRadius: BorderRadius.circular(8)),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(text, style: monoStyle(10.5, color: const Color(0xFFA8D1FF)).copyWith(height: 1.5)),
        ),
      ),
    );
  }
}

class _LogBox extends StatelessWidget {
  const _LogBox({required this.lines, required this.maxHeight});

  final List<InlineSpan> lines;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: _boxBg, border: Border.all(color: _boxBorder), borderRadius: BorderRadius.circular(8)),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final l in lines)
            Text.rich(
              TextSpan(children: [l]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(10.5, color: _panelText).copyWith(height: 1.55),
            ),
        ],
      ),
    );
  }
}
