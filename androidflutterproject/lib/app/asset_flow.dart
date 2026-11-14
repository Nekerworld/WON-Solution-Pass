/// 자산관리 상담 (상태머신 asset)
/// 목표 확인 → 정보 수집 → 출처 구분 → 지표 계산 → 해석 → 부족·모순 확인 → (질문) → 제안 → 검토 → 다음 행동
/// - 계산은 asset_advisor의 고정 공식, 문장은 ai_agent.
/// - 질문은 한도(3회) 안에서만 하고, 모름·답변 거부·질문 중단 요청이면 현재 정보로 제안 가능 여부를 판단한다.
/// - 방향을 고르는 것은 가입이 아니다. 상품 가입은 고객이 상품을 고른 뒤 가입 지원 트랙에서 따로 진행한다.
library;

import '../domain/asset_advisor.dart' as aa;
import '../domain/bank_types.dart';
import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/scenario.dart';
import 'ai_agent.dart';
import 'app_controller.dart';
import 'overlays.dart';
import 'router.dart';
import 'sessions.dart';

const List<ScreenId> _screens = [ScreenId.asset, ScreenId.explore, ScreenId.support, ScreenId.home];
const List<String> _auto = [
  'COLLECTING',
  'TAGGING',
  'CALCULATING',
  'INTERPRETING',
  'GAP_CHECK',
  'RECALC_ANSWER',
  'RECALC_CHANGE',
  'PROPOSABLE_CHECK',
  'PROPOSED_FULL',
  'PROPOSED_LIMITED',
];

/// 메시지가 한꺼번에 쌓이면 고객이 스크롤을 올려 다시 읽어야 하므로, 이어지는 안내 사이에 최소 간격을 둔다
const int gapMs = 3000;

class AssetFlow {
  AssetFlow(this.app);

  final AppController app;

  Fsm get fsm => app.assetFsm;
  AssetSession? get s => app.session.asset;

  int _lastSaidAt = 0;
  int _pacing = 0;
  bool _running = false;
  bool _again = false;

  void _push(ChatMsg Function(int id, int at) make) {
    final a = s;
    if (a == null) return;
    a.chat.add(make(a.chat.length + 1, nowMs()));
    if (a.chat.length > 80) a.chat.removeAt(0);
  }

  /// 기다리는 동안 데모가 초기화됐으면 false
  Future<bool> _say(ChatMsg Function(int id, int at) make) async {
    final ep = app.epoch;
    final wait = _lastSaidAt + gapMs * app.bank.latencyScale - nowMs();
    if (wait > 0) {
      _pacing += 1;
      _think(true);
      await app.sleep(wait);
      _pacing -= 1;
      if (_stale(ep)) return false;
    }
    s!.thinking = false;
    _push(make);
    _lastSaidAt = nowMs();
    app.refresh(_screens);
    return true;
  }

  Future<bool> _sayAI(AiResult res, {String? kind, List<aa.Figure>? figures, String? key, String? why, String? level}) =>
      _say((id, at) => ChatMsg(id: id, at: at, role: 'ai', text: res.output.message, fallback: res.fallback, kind: kind, figures: figures, key: key, why: why, level: level));

  Future<bool> _sayBot(String text) => _say((id, at) => ChatMsg(id: id, at: at, role: 'ai', text: text));

  Future<bool> _saySystem(String text, [String? tone]) => _say((id, at) => ChatMsg(id: id, at: at, role: 'system', text: text, tone: tone));

  void _sayUser(String text) => _push((id, at) => ChatMsg(id: id, at: at, role: 'user', text: text));

  void _think(bool on) {
    s?.thinking = on;
    app.refresh(_screens);
  }

  bool _stale(int ep) => ep != app.epoch || s == null;

  /* ---------------- 시작 ---------------- */
  bool start() {
    if (fsm.state == 'CLOSED' || fsm.state == 'TO_JOIN') fsm.transition('NEW_CASE');
    if (fsm.state != 'IDLE') return false;
    app.session.asset = AssetSession(caseId: newId('ASSET'));
    fsm.transition('START');
    return true;
  }

  void agree() {
    if (fsm.state != 'CONSENT') return;
    fsm.transition('AGREE');
    _push((id, at) => ChatMsg(id: id, at: at, role: 'ai', text: '어떤 목표로 상담받고 싶으세요? 편하게 말씀해 주세요. 예: "2년 뒤 결혼 자금 모으고 싶어요"'));
    _lastSaidAt = nowMs();
    app.navigate(ScreenId.asset, replace: true);
  }

  Future<void> setGoal(String text) async {
    final a = s;
    final t = text.trim();
    if (a == null || t.isEmpty || fsm.state != 'GOAL') return;
    _sayUser(t);
    final ep = app.epoch;
    _think(true);
    final ai = await app.ai.assetGoal(t);
    if (_stale(ep)) return;
    a.goalText = t;
    a.purpose = ai.valid && ai.output.purpose != null ? ai.output.purpose! : 'GOAL_SAVING';
    for (final x in ai.output.actions) {
      if (x.type == 'SET_INFO') a.stated[x['key'] as String] = (x['value'] as num).round();
    }
    if (!await _sayAI(ai)) return;
    fsm.transition('GOAL_SET', {'purpose': a.purpose});
    await advance();
  }

  /* ---------------- 자동 진행 ---------------- */
  Future<void> advance() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _loop();
      } while (_again);
    } finally {
      _running = false;
      app.refresh(_screens);
    }
  }

  Future<void> _loop() async {
    final ep = app.epoch;
    for (var i = 0; i < 30; i++) {
      if (_stale(ep)) return;
      final st = fsm.state;
      if (!_auto.contains(st)) return;
      await _step(st, ep);
    }
  }

  Future<void> _step(String st, int ep) async {
    final a = s!;
    final f = fsm;
    if (st == 'COLLECTING') {
      _think(true);
      final r = await app.bank.getFinancialSnapshot();
      if (_stale(ep)) return;
      _think(false);
      if (!r.ok) {
        a.hold = const AssetHold(reason: 'QUERY_FAILED', text: '연결된 기관의 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
        app.events.add('ASSET', '재무 정보 조회 실패: ${r.error!.code}', {'level': 'warn'});
        if (!await _saySystem(a.hold!.text, 'warning')) return;
        f.transition('QUERY_FAILED', {'code': r.error!.code});
        return;
      }
      _collect(r.data!);
      f.transition('COLLECTED', {'stateVersion': r.data!.stateVersion});
    } else if (st == 'TAGGING') {
      app.events.add('ASSET', '출처 구분: ${a.info!.items.entries.map((e) => '${e.key}:${e.value.source}').join(', ')}');
      f.transition('TAGGED');
    } else if (st == 'CALCULATING' || st == 'RECALC_ANSWER' || st == 'RECALC_CHANGE') {
      a.metrics = aa.computeMetrics(a.info!);
      app.events.add('ASSET', '지표 계산: ${a.metrics!.list.map((m) => '${m.key}=${m.value ?? '-'}').join(', ')}');
      f.transition(st == 'CALCULATING' ? 'CALCULATED' : 'RECALCULATED');
    } else if (st == 'INTERPRETING') {
      _think(true);
      final ai = await app.ai.assetInterpret(a.metrics!);
      if (_stale(ep)) return;
      if (!await _sayAI(ai, kind: 'interpret', figures: aa.interpretFigures(a.metrics!, a.purpose))) return;
      f.transition('INTERPRETED');
    } else if (st == 'GAP_CHECK') {
      a.gaps = aa.findGaps(a.info!, a.purpose, a.metrics);
      if (a.gaps.isEmpty) {
        f.transition('NO_GAP');
        return;
      }
      if (aa.canAsk(questionsAsked: a.questionsAsked, stopRequested: a.stopRequested, gaps: a.gaps)) {
        final gap = a.gaps.firstWhere((g) => aa.questionFor(g) != null);
        final q = aa.questionFor(gap)!;
        _think(true);
        final ai = await app.ai.assetAsk(q, gap);
        if (_stale(ep)) return;
        if (!await _sayAI(ai, kind: 'question', key: q.key, why: q.why, level: gap.level)) return;
        a.pendingQuestion = q.key;
        a.questionsAsked += 1;
        f.transition('ASK', {'question': q.id, 'level': gap.level});
        return;
      }
      app.events.add('ASSET', a.stopRequested ? '질문 중단 요청 → 현재 정보로 판단' : '질문 한도 도달 → 현재 정보로 판단');
      f.transition('LIMIT_OR_STOP');
    } else if (st == 'PROPOSABLE_CHECK') {
      final p = aa.proposable(a.info!, a.purpose);
      if (p.ok) {
        f.transition('PROPOSABLE');
        return;
      }
      a.hold = AssetHold(
        reason: 'INSUFFICIENT',
        missing: p.missing,
        text: '지금 정보로는 제안하기 어려워요. ${josa(p.missing.map(aa.itemLabel).join('·'), '이')} 확인되지 않았어요.',
      );
      if (!await _saySystem(a.hold!.text, 'warning')) return;
      f.transition('NOT_PROPOSABLE', {'missing': p.missing});
    } else if (st == 'PROPOSED_FULL' || st == 'PROPOSED_LIMITED') {
      final level = st == 'PROPOSED_FULL' ? 'FULL' : 'LIMITED';
      final basis = aa.proposalBasis(a.info!, a.purpose, a.metrics!);
      _think(true);
      final ai = await app.ai.assetPropose(basis, level, a.metrics!);
      if (_stale(ep)) return;
      if (!await _sayAI(ai, kind: 'proposal', figures: aa.proposalFigures(basis, a.metrics!))) return;
      a.proposal = Proposal(level: level, basis: basis, text: ai.output.message);
      f.transition('SHOWN', {'level': level});
    }
  }

  void _collect(FinancialSnapshot data) {
    final a = s!;
    final prev = a.info;
    a.coverage = (data.linked, data.notLinked);
    final info = aa.createInfo(data.items);
    if (prev != null) {
      // 고객이 답하거나 고친 값은 다시 조회해도 유지하고, 이력도 이어 간다
      info.history.addAll(prev.history);
      info.declined.addAll(prev.declined);
      for (final e in prev.items.entries) {
        if (e.value.source == 'STATED') info.items[e.key] = e.value;
      }
    }
    for (final e in a.stated.entries) {
      if (info.items[e.key]?.source != 'STATED') aa.setItem(info, e.key, e.value, 'STATED', '상담 목표에서 확인');
    }
    a.info = info;
  }

  /* ---------------- 질문 응답 ---------------- */
  Future<void> answerText(String text) async {
    final a = s;
    final t = text.trim();
    if (a == null || t.isEmpty) return;
    final st = fsm.state;
    if (st == 'GOAL') return setGoal(t);
    if (st == 'REVIEW') return modifyText(t);
    if (st != 'ASKING') {
      _sayUser(t);
      await _sayBot('지금 단계에서는 아래 버튼으로 선택해 주세요.');
      return;
    }
    _sayUser(t);
    final ep = app.epoch;
    final q = aa.questions[a.pendingQuestion];
    _think(true);
    final ai = await app.ai.assetAnswer(t, q);
    if (_stale(ep) || fsm.state != 'ASKING') return;
    if (ai.output.intent == 'SET_INFO') {
      a.thinking = false;
    } else if (!await _sayAI(ai)) {
      return;
    }
    await _applyAnswer(ai.output.actions.map((x) => (x.type, x.fields)).toList(), q);
  }

  Future<void> _applyAnswer(List<(String, Map<String, Object?>)> actions, aa.AssetQuestion? q) async {
    final a = s!;
    final f = fsm;
    final types = actions.map((x) => x.$1).toList();
    if (types.contains('END')) return _exit();
    if (types.contains('STOP_QUESTIONS') || types.contains('ESCALATE')) {
      a.stopRequested = true;
      a.pendingQuestion = null;
      if (types.contains('ESCALATE') && !await _sayBot('지금까지 확인한 내용으로 정리한 뒤 상담 연결을 도와드릴게요.')) return;
      f.transition('STOP_REQUEST');
      return advance();
    }
    final hold = actions.where((x) => x.$1 == 'HOLD').firstOrNull;
    if (hold != null && q != null) {
      aa.markDeclined(a.info!, q.key, hold.$2['reason'] as String? ?? 'UNKNOWN');
      a.pendingQuestion = null;
      f.transition('UNKNOWN_OR_REFUSED', {'key': q.key, 'kind': hold.$2['reason']});
      return advance();
    }
    final sets = actions.where((x) => x.$1 == 'SET_INFO').toList();
    if (sets.isEmpty) {
      app.refresh(_screens);
      return;
    }
    for (final x in sets) {
      aa.setItem(a.info!, x.$2['key'] as String, (x.$2['value'] as num).round(), 'STATED', '질문 응답');
    }
    a.pendingQuestion = null;
    f.transition('ANSWERED', {'keys': sets.map((x) => x.$2['key']).toList()});
    await advance();
  }

  /// 답변 칩: 범위 답변
  Future<void> answerChip(String value, String label) async {
    final a = s;
    if (a == null || fsm.state != 'ASKING') return;
    final q = aa.questions[a.pendingQuestion];
    _sayUser(label);
    if (value == 'UNKNOWN' || value == 'REFUSED') {
      if (!await _sayBot(value == 'UNKNOWN' ? replyUnknown : replyRefused)) return;
      return _applyAnswer([('HOLD', {'reason': value})], q);
    }
    if (value == 'STOP') {
      if (!await _sayBot(replyStop)) return;
      return _applyAnswer([('STOP_QUESTIONS', const {})], q);
    }
    return _applyAnswer([('SET_INFO', {'key': q?.key, 'value': int.tryParse(value) ?? 0})], q);
  }

  /* ---------------- 검토 ---------------- */
  Future<void> accept() async {
    final a = s;
    if (a == null || fsm.state != 'REVIEW') return;
    _sayUser('이 방향으로 할게요');
    a.handoffTerms = HandoffTerms(
      purpose: aa.purposeOf(a.purpose).label,
      tags: a.proposal!.basis.tags,
      monthly: a.proposal!.basis.monthly,
      months: a.proposal!.basis.months,
      goalText: a.goalText,
    );
    fsm.transition('ACCEPT');
    await _sayBot('좋아요. 다음에 할 일을 골라 주세요.');
  }

  Future<void> modifyText(String text) async {
    final a = s;
    if (a == null || fsm.state != 'REVIEW') return;
    _sayUser(text);
    final ep = app.epoch;
    _think(true);
    final ai = await app.ai.assetModify(text);
    if (_stale(ep) || fsm.state != 'REVIEW') return;
    if (!await _sayAI(ai)) return;
    final sets = ai.output.actions.where((x) => x.type == 'SET_INFO').toList();
    if (sets.isEmpty) {
      app.refresh(_screens);
      return;
    }
    for (final x in sets) {
      aa.setItem(a.info!, x['key'] as String, (x['value'] as num).round(), 'STATED', '조건 수정: $text');
    }
    fsm.transition('MODIFY', {'keys': sets.map((x) => x['key']).toList()});
    await advance();
  }

  Future<void> applyAlternative(String id) async {
    final a = s;
    if (a == null || fsm.state != 'REVIEW' || a.proposal == null) return;
    final alt = a.proposal!.basis.alternatives.where((x) => x.id == id).firstOrNull;
    if (alt == null) return;
    _sayUser(alt.label);
    if (alt.apply.isEmpty) {
      await _sayBot('비상자금을 먼저 채우는 방향은 상담사와 함께 구체적으로 정하는 걸 권해요. 이 방향으로 정한 뒤 상담 연결을 고를 수 있어요.');
      return;
    }
    for (final e in alt.apply.entries) {
      aa.setItem(a.info!, e.key, e.value, 'STATED', '조정안 선택: ${alt.label}');
    }
    fsm.transition('MODIFY', {'alternative': id});
    await advance();
  }

  /* ---------------- 다음 행동 ---------------- */
  void nextAction(String kind) {
    final a = s;
    final f = fsm;
    if (a == null) return;
    if (kind == 'explore' && f.state == 'NEXT_ACTION') {
      f.transition('EXPLORE');
      app.navigate(ScreenId.explore);
    } else if (kind == 'consult' && (f.state == 'NEXT_ACTION' || f.state == 'HOLD')) {
      final hold = f.state == 'HOLD';
      a.escalation = Escalation(reason: hold ? 'HOLD' : 'CUSTOMER_REQUEST', text: hold ? (a.hold?.text ?? '') : '고객이 전문 상담을 원했어요.');
      a.consult = null;
      a.handoff = null;
      a.handoffConsent = false;
      f.transition('CONSULT');
      app.navigate(ScreenId.support, params: {'track': 'asset'});
    } else if (kind == 'keep' && f.state == 'NEXT_ACTION') {
      a.closedReason = 'KEEP';
      f.transition('KEEP');
      _sayBot('지금은 유지하기로 했어요. 상담 내용은 언제든 다시 볼 수 있어요.');
    } else if (kind == 'recheck' && (f.state == 'NEXT_ACTION' || f.state == 'HOLD')) {
      f.transition('RECHECK_INFO');
      _sayBot('틀린 정보가 있으면 아래에서 고쳐 주세요. 다 고치셨으면 "다시 분석"을 눌러 주세요.');
    }
    app.refresh(_screens);
  }

  /// RECONSULT: 정보 정정 후 다시 분석
  Future<void> resumeAnalysis() async {
    final a = s;
    if (a == null || fsm.state != 'RECONSULT') return;
    if (a.info == null) {
      final ep = app.epoch;
      _think(true);
      final r = await app.bank.getFinancialSnapshot();
      if (_stale(ep)) return;
      _think(false);
      if (!r.ok) {
        app.toast('아직 정보를 불러올 수 없어요. 잠시 후 다시 시도해 주세요.', UiTone.danger);
        return;
      }
      _collect(r.data!);
    }
    a.metrics = aa.computeMetrics(a.info!);
    a.hold = null;
    _sayUser('다시 분석해 주세요');
    fsm.transition('RESUME');
    await advance();
  }

  void editItem(String key, int value) {
    final a = s;
    if (a == null || a.info == null || !aa.items.containsKey(key)) return;
    aa.setItem(a.info!, key, value, 'STATED', '고객 정정');
    app.events.add('ASSET', '정보 정정 $key → $value');
    app.refresh(_screens);
  }

  void selectProduct(String productId) {
    final st = fsm.state;
    if (st != 'EXPLORE' && st != 'TO_JOIN') return;
    if (st == 'EXPLORE') fsm.transition('PRODUCT_SELECTED', {'productId': productId});
    app.navigate(ScreenId.product, params: {'productId': productId, 'from': 'asset'});
  }

  Future<void> backFromExplore() async {
    if (fsm.state == 'EXPLORE') {
      fsm.transition('BACK');
    } else if (fsm.state == 'TO_JOIN') {
      return app.goBack();
    }
    await app.navigate(ScreenId.asset, backTo: true);
  }

  void end() {
    final f = fsm;
    final a = s;
    if (f.can('END')) {
      a?.closedReason = 'END';
      f.transition('END');
    } else if (f.can('EXIT')) {
      a?.closedReason = 'EXIT';
      f.transition('EXIT');
    } else {
      return;
    }
    app.refresh(_screens);
    if (a != null) _sayBot('상담을 마쳤어요. 상품 가입이나 이체 같은 변경은 하지 않았어요.');
  }

  Future<void> _exit() async => end();

  void newCase() {
    if (!fsm.can('NEW_CASE')) return;
    fsm.transition('NEW_CASE');
    app.session.asset = null;
    app.navigate(ScreenId.home, resetHistory: true);
  }

  void resume() {
    final a = s;
    if (a == null || _running) return;
    if (_auto.contains(fsm.state)) {
      advance();
    } else if (a.thinking && _pacing == 0) {
      a.thinking = false;
      app.refresh(_screens);
    }
  }

  HandoffCtx? handoffContext() {
    final a = s;
    if (a == null) return null;
    final lines = ['상담 목적: ${aa.purposeOf(a.purpose).label}${a.goalText.isNotEmpty ? ' ("${a.goalText}")' : ''}'];
    final info = a.info;
    if (info != null) {
      final knownList = <String>[];
      final unknown = <String>[];
      for (final e in info.items.entries) {
        final it = e.value;
        if (e.key == 'monthlySavingPref' && it.value == null) continue;
        if (it.value == null) {
          unknown.add(aa.itemLabel(e.key));
        } else {
          knownList.add('${aa.itemLabel(e.key)} ${aa.display(e.key, it.value)}(${sourceLabel[it.source] ?? it.source})');
        }
      }
      lines.add('확인된 정보: ${knownList.join(', ')}');
      if (unknown.isNotEmpty) lines.add('미확인: ${unknown.join(', ')}');
    }
    if (a.proposal != null) lines.add('제안: ${a.proposal!.text}');
    if (a.escalation != null && a.escalation!.text.isNotEmpty) lines.add('연결 사유: ${a.escalation!.text}');
    return HandoffCtx(reason: a.escalation?.reason ?? 'HANDOFF', lines: lines);
  }

  /* ---------------- 화면 동작 ---------------- */

  ScreenId _screenFor(String st) => switch (st) {
        'CONSENT' => ScreenId.assetConsent,
        'EXPLORE' => ScreenId.explore,
        'HANDOFF' => ScreenId.support,
        _ => ScreenId.asset,
      };

  /// 홈·상품몰의 AI 자산관리 버튼
  Future<void> startAction() async {
    final st = fsm.state;
    if (st == 'IDLE' || st == 'CLOSED' || st == 'TO_JOIN') {
      if (start()) await app.navigate(ScreenId.assetConsent);
      return;
    }
    await app.navigate(_screenFor(st), params: st == 'HANDOFF' ? const {'track': 'asset'} : const {});
  }

  void open() {
    final st = fsm.state;
    if (st == 'IDLE') return;
    app.navigate(_screenFor(st), params: st == 'HANDOFF' ? const {'track': 'asset'} : const {});
  }

  void decline() {
    if (fsm.can('EXIT')) fsm.transition('EXIT');
    if (fsm.can('NEW_CASE')) fsm.transition('NEW_CASE');
    app.session.asset = null;
    app.navigate(ScreenId.home, resetHistory: true);
  }

  void openEdit(String key) {
    final a = s;
    if (a == null || a.info == null) return;
    app.openSheet(AssetEditSheet(itemKey: key));
  }

  /// 정보 고치기 시트의 저장 버튼. 금액은 만원 단위로 입력받는다.
  void saveEdit(String key, String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (raw.trim().isEmpty || digits.isEmpty) {
      app.toast('숫자로 입력해 주세요.', UiTone.warning);
      return;
    }
    final v = int.parse(digits);
    app.closeSheet();
    editItem(key, aa.items[key]!.kind == 'months' ? v : v * 10000);
  }
}
