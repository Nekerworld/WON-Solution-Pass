/// 자산관리 상담 (상태머신 asset)
/// 목표 확인 → 정보 수집 → 출처 구분 → 지표 계산 → 해석 → 부족·모순 확인 → (질문) → 제안 → 검토 → 다음 행동
/// - 계산은 asset_advisor의 고정 공식, 문장은 ai_agent.
/// - 질문은 한도(3회) 안에서만 하고, 모름·답변 거부·질문 중단 요청이면 현재 정보로 제안 가능 여부를 판단한다.
/// - 방향을 고르는 것은 가입이 아니다. 상품 가입은 고객이 상품을 고른 뒤 가입 지원 트랙에서 따로 진행한다.
library;

import 'dart:math';

import '../domain/asset_advisor.dart' as aa;
import '../domain/bank_state.dart';
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

final RegExp cookieBanned = RegExp(r'종목|매수|매도|수익률|추천주|사세요');

/// 홈 프롬프트 쿠키 문장. 계좌 정보가 있으면 그 숫자로 만든 문장을 더한다
List<String> cookieLines(BankState s) {
  final lines = [
    '해외주식 투자를 처음 시작해 보고 싶어요.',
    '비상자금이 충분한지 알고 싶어요.',
    '3년 안에 목돈을 모으려면 매달 얼마를 모아야 할까요?',
    '계좌에 있는 정보만으로, 자산관리를 어디부터 보면 좋을까요?',
  ];
  final items = s.finance.items;
  final income = items['monthlyIncome']?.value, expense = items['monthlyExpense']?.value, liquid = items['liquidAssets']?.value;
  if (income != null && expense != null && expense != 0 && liquid != null) {
    final months = (liquid / expense * 10).round() / 10;
    lines.add('예금이 생활비 ${aa.numText(months)}개월치예요. 비상자금으로 충분한지 알고 싶어요.');
    lines.add('해외주식을 시작해도 부담 없을까요?');
    lines.add('지금 예금 ${formatMan((liquid / 10000).round() * 10000)}이면, 결혼 자금 3천만원을 모으는 데 얼마나 부족한가요?');
    if (s.facts['hasFxAccount'] != true) lines.add('해외주식 계좌는 아직 없어요. 매달 얼마부터 보면 좋을지 알고 싶어요.');
  }
  return lines.where((t) => !cookieBanned.hasMatch(t) && t.length <= 120).toList();
}

final Random _cookieRand = Random();

String pickCookie(BankState s) {
  final lines = cookieLines(s);
  if (lines.isEmpty) return '';
  return lines[_cookieRand.nextInt(lines.length)];
}

/// 지금 보이는 문장과 다른 문장을 고른다
String nextCookie(BankState s, String current) {
  final lines = cookieLines(s);
  if (lines.isEmpty) return '';
  final rest = lines.where((t) => t != current).toList();
  final pool = rest.isNotEmpty ? rest : lines;
  return pool[_cookieRand.nextInt(pool.length)];
}

class AssetFlow {
  AssetFlow(this.app);

  final AppController app;

  Fsm get fsm => app.assetFsm;
  AssetSession? get s => app.session.asset;

  int _pacing = 0;
  bool _running = false;
  bool _again = false;

  /// 인사 말이 나가기 전에 목표 칩이 눌리면 말이 순서가 뒤집힌다. 고객 동작은 한 줄로 잇는다.
  Future<void> _tail = Future.value();

  Future<void> _enqueue(Future<void> Function() fn) {
    final run = _tail.then((_) => fn());
    _tail = run.catchError((_) {});
    return run;
  }

  int _scaleMs(num ms) => (ms * app.bank.latencyScale).round();

  void _push(ChatMsg Function(int id, int at) make) {
    final a = s;
    if (a == null) return;
    a.chat.add(make(a.chat.length + 1, nowMs()));
    if (a.chat.length > 80) a.chat.removeAt(0);
  }

  /// 사용자 말이 들어오는 동안에는 로딩을 켜지 않는다.
  Future<bool> _waitUserSlide(int ep) async {
    final last = s?.chat.lastOrNull;
    if (last == null || last.role != 'user') return true;
    final left = _scaleMs(1000) - (nowMs() - last.at);
    if (left > 0) {
      _think(false);
      await app.sleep(left);
      if (_stale(ep)) return false;
    }
    return true;
  }

  /// 화면에 나오는 말 사이에 생각 1.5초, 읽을 시간 1초를 둔다. 기다리는 동안 데모가 초기화됐으면 false
  Future<bool> _say(ChatMsg Function(int id, int at) make) async {
    final ep = app.epoch;
    if (!await _waitUserSlide(ep)) return false;
    final thinkMs = _scaleMs(1500), easeMs = _scaleMs(1000);
    if (thinkMs > 0) {
      _pacing += 1;
      _think(true);
      await app.sleep(thinkMs);
      _pacing -= 1;
      if (_stale(ep)) return false;
    }
    if (s == null) return false;
    s!.thinking = false;
    _push(make);
    app.refresh(_screens);
    if (easeMs > 0) {
      _pacing += 1;
      await app.sleep(easeMs);
      _pacing -= 1;
      if (_stale(ep)) return false;
    }
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

  /// 상담에서 확인한 목표·참고 금액·계좌 정보를 가입 화면과 같은 객체에 둔다.
  void _syncContext({String? selectedProductId}) {
    final a = s;
    if (a == null) return;
    final known = <KnownLine>[];
    final items = a.info?.items;
    if (items != null) {
      for (final k in ['monthlyIncome', 'monthlyExpense', 'liquidAssets']) {
        final it = items[k];
        if (it == null || it.value == null || (it.source != 'BANK' && it.source != 'STATED')) continue;
        known.add(KnownLine(label: aa.itemLabel(k), text: aa.display(k, it.value), source: it.source == 'BANK' ? '계좌' : '고객 답변'));
      }
    }
    final monthly = a.proposal?.basis.monthly ?? a.handoffTerms?.monthly;
    app.publishContext(
      goal: a.goalText,
      knownFromAccount: known,
      financialSummary: monthly == null ? null : FinancialSummary(monthly: monthly, source: '계좌 정보 기준', adjustable: true),
      selectedProductId: selectedProductId,
    );
  }

  /* ---------------- 시작 ---------------- */
  bool start() {
    if (fsm.state == 'CLOSED' || fsm.state == 'TO_JOIN') fsm.transition('NEW_CASE');
    if (fsm.state != 'IDLE') return false;
    app.session.asset = AssetSession(caseId: newId('ASSET'));
    fsm.transition('START');
    return true;
  }

  Future<void> agree() {
    if (fsm.state != 'CONSENT') return Future.value();
    fsm.transition('AGREE');
    s?.thinking = true;
    return _enqueue(() async {
      await app.navigate(ScreenId.asset, replace: true);
      await _sayBot('어떤 목표로 상담받고 싶으세요? 편하게 말씀해 주세요. 예: "2년 뒤 결혼 자금 모으고 싶어요"');
    });
  }

  bool get freshConsult => const ['IDLE', 'CLOSED', 'TO_JOIN'].contains(fsm.state);

  /// 쿠키 문장으로 상담을 연다. 목표를 다시 묻는 인사는 하지 않는다.
  Future<void> askCookie(String text) async {
    final t = text.trim();
    if (t.isEmpty || cookieBanned.hasMatch(t)) return;
    if (!freshConsult) return open();
    if (!start() || !fsm.can('AGREE')) return;
    fsm.transition('AGREE');
    s?.thinking = true;
    return _enqueue(() async {
      _sayUser(t);
      await app.navigate(ScreenId.asset, replace: true);
      await _applyGoal(t);
    });
  }

  Future<void> setGoal(String text) => _enqueue(() => _setGoalNow(text));

  Future<void> _setGoalNow(String text) async {
    final t = text.trim();
    if (s == null || t.isEmpty || fsm.state != 'GOAL') return;
    _sayUser(t);
    await _applyGoal(t);
  }

  Future<void> _applyGoal(String t) async {
    final a = s;
    if (a == null || fsm.state != 'GOAL') return;
    final ep = app.epoch;
    final ai = await app.ai.assetGoal(t);
    if (_stale(ep)) return;
    a.goalText = t;
    _syncContext();
    a.purpose = ai.valid && ai.output.purpose != null ? ai.output.purpose! : 'GOAL_SAVING';
    for (final x in ai.output.actions) {
      if (x.type == 'SET_INFO') a.stated[x['key'] as String] = (x['value'] as num).round();
    }
    if (ai.output.message.isNotEmpty && !await _sayAI(ai)) return;
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
      if (!await _waitUserSlide(ep)) return;
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
      _syncContext();
      f.transition('COLLECTED', {'stateVersion': r.data!.stateVersion});
    } else if (st == 'TAGGING') {
      app.events.add('ASSET', '출처 구분: ${a.info!.items.entries.map((e) => '${e.key}:${e.value.source}').join(', ')}');
      f.transition('TAGGED');
    } else if (st == 'CALCULATING' || st == 'RECALC_ANSWER' || st == 'RECALC_CHANGE') {
      a.metrics = aa.computeMetrics(a.info!);
      app.events.add('ASSET', '지표 계산: ${a.metrics!.list.map((m) => '${m.key}=${m.value ?? '-'}').join(', ')}');
      f.transition(st == 'CALCULATING' ? 'CALCULATED' : 'RECALCULATED');
    } else if (st == 'INTERPRETING') {
      if (a.chat.any((m) => m.kind == 'interpret')) {
        f.transition('INTERPRETED');
        return;
      }
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
        final q = _posedQuestion(aa.questionFor(gap)!, a.goalText);
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
      final ai = await app.ai.assetPropose(basis, level, a.metrics!);
      if (_stale(ep)) return;
      if (!await _sayAI(ai, kind: 'proposal', figures: aa.proposalFigures(basis, a.metrics!))) return;
      a.proposal = Proposal(level: level, basis: basis, text: ai.output.message);
      _syncContext();
      f.transition('SHOWN', {'level': level});
    }
  }

  /// 목표로 이미 말한 경조사·결혼·이사를, 아직 모르는 지출처럼 다시 묻지 않는다.
  aa.AssetQuestion _posedQuestion(aa.AssetQuestion q, String goalText) {
    if (q.key != 'plannedLumpSum' || !RegExp(r'결혼|이사|경조사').hasMatch(goalText)) return q;
    return aa.AssetQuestion(id: q.id, key: q.key, text: '그 외에 또 나갈 목돈이 있나요?', why: '', options: q.options);
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
      final reason = hold.$2['reason'] as String? ?? 'UNKNOWN';
      aa.markDeclined(a.info!, q.key, reason);
      a.pendingQuestion = null;
      if (reason == 'UNKNOWN') {
        f.transition('SKIP_ONE', {'key': q.key});
      } else {
        f.transition('UNKNOWN_OR_REFUSED', {'key': q.key, 'kind': reason});
      }
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
  Future<void> answerChip(String value, String label) => _enqueue(() => _answerChipNow(value, label));

  Future<void> _answerChipNow(String value, String label) async {
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
  Future<void> accept() => _enqueue(_acceptNow);

  Future<void> _acceptNow() async {
    final a = s;
    if (a == null || fsm.state != 'REVIEW') return;
    a.pendingAccept = true;
    _sayUser('이 방향으로 할게요');
    a.handoffTerms = HandoffTerms(
      purpose: aa.purposeOf(a.purpose).label,
      tags: a.proposal!.basis.tags,
      monthly: a.proposal!.basis.monthly,
      months: a.proposal!.basis.months,
      goalText: a.goalText,
    );
    _syncContext();
    final said = await _sayBot('좋아요. 다음에 할 일을 골라 주세요.');
    a.pendingAccept = false;
    if (!said || fsm.state != 'REVIEW') {
      app.refresh(_screens);
      return;
    }
    fsm.transition('ACCEPT');
    app.refresh(_screens);
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
      await _sayBot(alt.message ?? '비상자금부터 채우는 건 상담 연결에서 이어서 정하면 돼요.');
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
    final p = a.proposal;
    if (p != null && (key == 'monthlyIncome' || key == 'monthlyExpense' || key == 'monthlySavingPref')) {
      a.metrics = aa.computeMetrics(a.info!);
      final basis = aa.proposalBasis(a.info!, a.purpose, a.metrics!);
      a.proposal = Proposal(level: p.level, basis: basis, text: p.text, at: p.at);
      final t = a.handoffTerms;
      a.handoffTerms = HandoffTerms(
        purpose: t?.purpose ?? aa.purposeOf(a.purpose).label,
        tags: t?.tags ?? basis.tags,
        monthly: basis.monthly,
        months: t?.months ?? basis.months,
        goalText: t?.goalText ?? a.goalText,
      );
    }
    _syncContext();
    app.refresh(_screens);
  }

  void selectProduct(String productId) {
    final st = fsm.state;
    if (st != 'EXPLORE' && st != 'TO_JOIN') return;
    if (st == 'EXPLORE') fsm.transition('PRODUCT_SELECTED', {'productId': productId});
    _syncContext(selectedProductId: productId);
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
    if (a != null) _sayBot('상담을 마쳤어요.');
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

  /// 이전 룰베이스 상담 시작 (시연 패널에서 이전 상담을 켰을 때)
  Future<void> startAction() async {
    if (freshConsult) {
      if (start()) await app.navigate(ScreenId.assetConsent);
      return;
    }
    await open();
  }

  Future<void> open() async {
    final st = fsm.state;
    if (st == 'IDLE') return;
    await app.navigate(_screenFor(st), params: st == 'HANDOFF' ? const {'track': 'asset'} : const {});
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

  /// 투자 속도 시트의 칩
  void savePace(String key, int value) {
    final v = aa.pacePercent(value);
    if (v == null) return;
    app.closeSheet();
    editItem(key, v);
  }

  /// 정보 고치기 시트의 저장 버튼. 금액은 만원 단위로 입력받는다.
  void saveEdit(String key, String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (raw.trim().isEmpty || digits.isEmpty) {
      app.toast('숫자로 입력해 주세요.', UiTone.warning);
      return;
    }
    final v = int.parse(digits);
    final kind = aa.items[key]!.kind;
    app.closeSheet();
    editItem(key, kind == 'months' ? v : (kind == 'pace' ? aa.pacePercent(v)! : v * 10000));
  }
}
