/// 목돈 불리기 대본 진행. 월급·지출·부채는 채팅 시작 스냅샷만 쓰고,
/// 목표와 성향은 그 채팅에서 보낸 문장으로 정한다.
library;

import 'dart:async';

import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/lumpsum_advisor.dart' as la;
import '../domain/lumpsum_script.dart' as ls;
import 'app_controller.dart';
import 'router.dart';
import 'sessions.dart';

const Map<String, String> decisionLabel = {
  'SPEND_CHECK': '지출 점검',
  'DEBT_FIRST': '상환 우선',
  'EMERGENCY_FIRST': '비상자금',
  'SAVINGS_ENOUGH': '적금으로 달성',
  'MIX': '적금+투자',
};

class LumpsumHint {
  const LumpsumHint({required this.active, this.line = '', this.decision = ''});
  final bool active;
  final String line;
  final String decision;
}

const List<ScreenId> _screens = [ScreenId.lumpsum, ScreenId.home];

int _hash(String str) {
  var h = 0;
  for (final c in str.codeUnits) {
    h = (h * 33 + c) & 0xFFFFFFFF;
  }
  return h;
}

class LumpsumFlow {
  LumpsumFlow(this.app);

  final AppController app;

  Fsm get fsm => app.fsms[FsmKind.lumpsum]!;
  LumpsumSession? get s => app.session.lumpsum;

  Future<void> _tail = Future.value();
  int _pending = 0;
  Timer? _typeTimer;

  Future<void> _enqueue(Future<void> Function() fn) {
    _pending += 1;
    final run = _tail.then((_) => fn());
    _tail = run.catchError((_) {}).whenComplete(() => _pending -= 1);
    return run;
  }

  double get _scale => app.bank.latencyScale;

  Future<void> _sleep(num ms) {
    final wait = (ms * _scale).round();
    if (wait <= 0) return Future.value();
    return Future.delayed(Duration(milliseconds: wait));
  }

  bool _stale(int ep) => ep != app.epoch || s == null;

  void _refresh() => app.refresh(_screens);

  /// 글자 흐름처럼 자주 바뀌는 값은 저장 없이 다시 그리기만 한다
  void _paint() => app.touch();

  LumpsumSession _fresh(LumpSnap snap) {
    final caseId = newId('LUMP');
    return LumpsumSession(caseId: caseId, seed: _hash(caseId), snap: snap);
  }

  LumpSnap _readSnap() {
    final items = app.store.state.finance.items;
    final debt = items['debt']?.value ?? 0;
    return LumpSnap(
      income: items['monthlyIncome']?.value ?? 0,
      expense: items['monthlyExpense']?.value ?? 0,
      debt: debt,
      debtPayment: la.debtPayment(debt),
      deposit: items['liquidAssets']?.value ?? la.depositDefault,
    );
  }

  /// 외화 계좌를 이미 갖고 있는지 (해외주식 계좌 개설 안내 문구가 달라진다)
  bool _hasFx() => app.store.state.facts['hasFxAccount'] == true;

  LumpRow? _push({required String role, String text = '', List<ls.LBlock>? blocks, double thoughtMs = 0}) {
    final ss = s;
    if (ss == null) return null;
    final id = '${ss.caseId}-${ss.chat.length + 1}';
    LumpRow row;
    if (role == 'ai') {
      final bl = blocks ?? [ls.tb(text)];
      row = LumpRow(id: id, at: nowMs(), role: role, blocks: bl, thoughtMs: thoughtMs, text: bl.where((b) => b.t == 'text').map((b) => b.text).join('\n\n'));
    } else {
      row = LumpRow(id: id, at: nowMs(), role: role, text: text);
    }
    ss.chat.add(row);
    return row;
  }

  void _syncPrompt() {
    final ss = s;
    if (ss == null) return;
    final st = fsm.state;
    final t = ls.typed;
    var p = const LumpPrompt();
    if (st == 'INTRO') {
      p = LumpPrompt(mode: 'type', typeText: t['INTRO']!, choices: ls.introChoices());
    } else if (st == 'GOAL' && ss.intent == 'EMERGENCY') {
      final c = ls.emergencyChoices(ss.emAdvice);
      p = LumpPrompt(mode: 'choice', typeText: t['EMERGENCY']!, choices: c, demoChoice: c.first.text);
    } else if (st == 'GOAL') {
      p = LumpPrompt(mode: 'choice', typeText: t['GOAL']!, choices: ls.goalChoices(), demoChoice: '3년 안에 1억');
    } else if (st == 'DEBT_CHECK') {
      // 판단에 따라 선택지가 다르다. 투자로도 어려우면 목표 조정과 "그래도 투자"를 함께 보여 준다
      final c = ls.investChoices(ss.advice, ss.goal);
      final yes = c.where((x) => x.id == 'inv-yes').firstOrNull;
      p = LumpPrompt(mode: 'choice', typeText: ls.situationText(), choices: c, demoChoice: (yes ?? c.first).text);
    } else if (st == 'PROFILING') {
      p = LumpPrompt(mode: 'choice', typeText: t['PROFILING']!, choices: ls.experienceChoices(), demoChoice: '소액으로 ETF');
    } else if (st == 'LOSS') {
      p = LumpPrompt(mode: 'type', typeText: t['LOSS']!, choices: ls.lossChoices());
    } else if (st == 'SHORTFALL') {
      final c = ls.shortfallChoices(ss.shortfall, ss.goal ?? la.lumpGoals['goal-100']!);
      p = LumpPrompt(mode: 'choice', choices: c, demoChoice: c.last.text);
    } else if (st == 'RECOMMEND') {
      // 레버리지는 한 번 안내하고 나면 다시 보여 주지 않는다
      final showLev = (ss.advice?.leverage ?? false) && !ss.leverageDone;
      p = LumpPrompt(mode: 'choice', typeText: t['RECOMMEND']!, choices: ls.productChoices(showLev), demoChoice: '해외주식');
    } else if (st == 'NO_ACCOUNT') {
      p = LumpPrompt(mode: 'choice', typeText: t['NO_ACCOUNT']!, choices: ls.openChoices(), demoChoice: '네, 개설해 주세요');
    } else if (st == 'SPEND_PLAN') {
      p = LumpPrompt(mode: 'choice', choices: ls.spendChoices(), demoChoice: '줄이기 목표로 저장');
    }
    // 타이핑은 선택지에 원하는 상황이 없을 때 쓴다. 선택지와 같은 문장은 타이핑하지 않는다
    if (p.choices.any((c) => c.text == p.typeText)) p = p.withTypeText('');
    ss.prompt = p;
  }

  la.LumpAdvice currentAdvice() {
    final ss = s!;
    final goal = ss.goal ?? la.lumpGoals['goal-100']!;
    return la.advise(la.AdviseInput(
      income: ss.snap.income,
      expense: ss.snap.expense,
      debt: ss.snap.debt,
      deposit: ss.snap.deposit,
      goalAmount: goal.amount,
      goalMonths: goal.months,
      expText: ss.expText,
      lossText: ss.lossText,
      investFocus: ss.investFocus,
      boldShare: ss.boldShare,
    ));
  }

  la.LumpGoal _goalFrom(String text, String? choiceId) {
    if (choiceId != null && la.lumpGoals.containsKey(choiceId)) return la.lumpGoals[choiceId]!;
    if (la.goalTyped.text == text) return la.goalTyped;
    for (final g in la.lumpGoals.values) {
      if (g.text == text) return g;
    }
    return la.lumpGoals['goal-100']!;
  }

  /// 화면에 보인 선택지의 문장이 가장 정확하다. 판단에 따라 같은 id의 문장이 다르다
  String textOf(String choiceId, [String fallback = '']) {
    final own = s?.prompt.choices.where((c) => c.id == choiceId).firstOrNull;
    if (own != null) return own.text;
    final g = la.lumpGoals[choiceId];
    if (g != null) return g.text;
    final known = la.experienceTexts[choiceId] ?? la.lossTexts[choiceId];
    if (known != null) return known;
    for (final c in [...ls.investChoicesDefault, ...ls.emergencyChoicesHigh]) {
      if (c.id == choiceId) return c.text;
    }
    return fallback;
  }

  Future<bool> _think(String kind, int ep) async {
    final ss = s!;
    final steps = ls.thoughtSteps(kind);
    final started = nowMs();
    ss.thinking = true;
    ss.lock = true;
    for (var i = 0; i < steps.length; i++) {
      if (_stale(ep)) return false;
      ss.thinkLabel = steps[i];
      _refresh();
      await _sleep(700 + (i % 2) * 400);
    }
    if (_stale(ep)) return false;
    ss.thinking = false;
    ss.thoughtMs = _scale == 0 ? 0 : ((nowMs() - started) / 100).round() / 10;
    if (_scale != 0 && ss.thoughtMs < 1) ss.thoughtMs = 1;
    _refresh();
    return true;
  }

  static List<String> _tokens(String text) =>
      RegExp(r'\s+|[^\s]+').allMatches(text).map((m) => m.group(0)!).where((p) => p.isNotEmpty).toList();

  /// 문장 블록 하나를 글자 흐름으로 보여 준다
  Future<bool> _streamText(LumpRow row, int idx, int ep) async {
    final bits = _tokens(row.blocks[idx].text);
    row.cur = idx;
    row.curText = '';
    _refresh();
    for (var i = 0; i < bits.length; i++) {
      if (_stale(ep)) return false;
      if (s!.stopStream) break;
      row.curText += bits[i];
      _paint();
      final pause = RegExp(r'[.!?。]|요$|다$').hasMatch(bits[i]) ? 180 : 40 + (i % 4) * 18;
      await _sleep(pause);
    }
    row.cur = -1;
    row.curText = '';
    row.shown = idx + 1;
    _refresh();
    return !_stale(ep);
  }

  /// 블록을 순서대로 하나씩 보여 준다. 카드와 드롭다운은 앞 블록이 끝난 뒤에 나온다
  Future<bool> _revealBlocks(LumpRow row, int ep) async {
    row.streaming = true;
    if (_scale != 0) {
      for (var i = row.shown; i < row.blocks.length; i++) {
        if (_stale(ep)) return false;
        final b = row.blocks[i];
        if (s!.stopStream) break;
        if (b.t == 'text') {
          if (!await _streamText(row, i, ep)) return false;
        } else {
          if (i > 0) await _sleep(260);
          if (_stale(ep)) return false;
          row.shown = i + 1;
          _refresh();
          await _sleep(b.t == 'steps' ? 700 * b.items.length + 300 : 420);
        }
        await _sleep(140);
      }
    }
    if (_stale(ep)) return false;
    row.cur = -1;
    row.curText = '';
    row.shown = row.blocks.length;
    row.streaming = false;
    s!.stopStream = false;
    _refresh();
    return true;
  }

  Future<bool> _say(ls.LMessage msg, String? kind, int ep) async {
    if (kind != null && !await _think(kind, ep)) return false;
    if (_stale(ep)) return false;
    final row = _push(role: 'ai', text: msg.text, blocks: msg.blocks.isEmpty ? null : msg.blocks, thoughtMs: kind != null ? s!.thoughtMs : 0)!;
    final ok = await _revealBlocks(row, ep);
    s?.awaiting = '';
    return ok;
  }

  void _settle({bool closePrompt = false}) {
    final ss = s;
    if (ss == null) return;
    if (closePrompt) {
      ss.prompt = const LumpPrompt();
    } else {
      _syncPrompt();
    }
    ss.lock = false;
    _refresh();
  }

  void _tr(String event, [List<String>? from]) {
    if ((from == null || from.contains(fsm.state)) && fsm.can(event)) fsm.transition(event);
  }

  Future<void> _replyAnalysis(int ep) async {
    final ss = s!;
    ss.awaiting = 'analysis';
    ss.lock = true;
    final advice = currentAdvice();
    if (ss.intent == 'EMERGENCY') ss.emAdvice = advice;
    // 남는 돈이 없으면 목표를 묻지 않고 바로 지출부터 본다. 묻고 나서 무시하지 않는다
    final skipGoal = ss.goal == null && advice.surplus <= 0;
    final msg = ls.analysisMessage(
      advice,
      goalKnown: ss.goal != null,
      assumedMonths: ss.goal?.assumed ?? false,
      emergency: ss.intent == 'EMERGENCY',
      skipGoal: skipGoal,
      purposeLabel: ss.purposeLabel,
    );
    _tr('SENT', ['INTRO']);
    if (!await _say(msg, 'analysis', ep)) return;
    _tr('SHOWN');
    // 첫 말에서 목표를 이미 말했으면(결혼 자금 3천만원 3년 등) 목표를 묻지 않고 바로 판단으로 간다
    if (ss.goal != null || skipGoal) return _replyDecision(ep);
    _settle();
  }

  /// 첫 말에서 목표를 읽는다. 금액과 기간이 함께 있으면 그대로 쓰고,
  /// 금액만 있으면 기간을 3년으로 가정한다(화면에서 가정했다고 밝힌다). 금액이 없으면 null이라 목표를 따로 묻는다.
  Future<la.LumpGoal?> _introGoal(String text) async {
    try {
      final ai = await app.ai.assetGoal(text);
      final acts = ai.valid ? ai.output.actions : const [];
      int? pick(String key) {
        for (final x in acts) {
          if (x.type == 'SET_INFO' && x['key'] == key) return (x['value'] as num?)?.round();
        }
        return null;
      }

      final amount = pick('goalAmount'), months = pick('goalMonths');
      if (amount != null && amount != 0 && months != null && months != 0) return la.LumpGoal(amount: amount, months: months, text: text);
      if (amount != null && amount != 0) return la.LumpGoal(amount: amount, months: 36, text: text, assumed: true);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 비상자금만 보다가 목돈 마련도 보겠다고 했을 때: 목표를 묻는다
  Future<void> _replyGoalAsk(int ep) async {
    final ss = s!;
    ss.awaiting = 'goalask';
    ss.lock = true;
    if (!await _say(ls.goalAskMessage(ss.emAdvice), 'talk', ep)) return;
    _settle();
  }

  /// 비상자금만 보고 마칠 때: 안내 한 줄을 남기고 상담을 닫는다
  Future<void> _replyEmergencyStop(int ep) async {
    s!.lock = true;
    if (!await _say(ls.emergencyStop(s!.emAdvice), 'talk', ep)) return;
    _tr('EXIT');
    _settle(closePrompt: true);
  }

  /// 해외주식 첫 시작: 외화 계좌 안내와 개설 질문. 목표는 묻지 않는다
  Future<void> _replyOverseasIntro(int ep) async {
    final ss = s!;
    ss.awaiting = 'overseas';
    ss.lock = true;
    _refresh();
    _tr('OVERSEAS', ['INTRO']);
    if (!await _say(ls.overseasIntro(_hasFx()), 'talk', ep)) return;
    _settle();
  }

  Future<void> _replyDecision(int ep) async {
    final ss = s!;
    ss.awaiting = 'decision';
    ss.lock = true;
    final advice = currentAdvice();
    ss.advice = advice;
    // 비상자금 칩에서 이어졌으면 채우는 방법은 이미 말했으므로 다시 말하지 않는다
    final msg = ls.decisionMessage(advice, skipFill: ss.fromEmergency);
    _tr('SENT', ['GOAL']);
    if (!await _say(msg, 'decision', ep)) return;
    if (advice.decisionId == 'SPEND_CHECK') _tr('PLAN');
    _settle();
  }

  /// 줄이기 목표를 저장하고 상담을 마친다. 저장값은 소비 분석 화면이 읽는다
  Future<void> _replySaved(int ep) async {
    final ss = s!;
    ss.awaiting = 'saved';
    ss.lock = true;
    final advice = ss.advice ?? currentAdvice();
    final plan = la.spendPlan(advice);
    app.session.spendGoal = SpendGoal(
      total: plan.total,
      target: plan.target,
      after: plan.after,
      items: [for (final it in plan.items) SpendGoalItem(id: it.id, category: it.category, label: it.label, saved: it.saved)],
      savedAt: nowMs(),
    );
    if (!await _say(ls.savedMessage(advice), 'save', ep)) return;
    _tr('DONE');
    _settle(closePrompt: true);
  }

  /// 투자는 빼고 마칠 때: 안내 한 줄을 남기고 상담을 닫는다
  Future<void> _replyStop(int ep) async {
    s!.lock = true;
    if (!await _say(ls.stopMessage(s!.advice), 'talk', ep)) return;
    _tr('STOP');
    _settle(closePrompt: true);
  }

  Future<void> _replyAfterUser3(int ep) async {
    final ss = s!;
    ss.awaiting = 'profile';
    ss.lock = true;
    // 목표를 바꿔 다시 판단한 경우처럼 성향을 이미 답했으면 다시 묻지 않고 바로 계산으로 간다
    final known = ss.expText.isNotEmpty && ss.lossText.isNotEmpty;
    final msg = ls.afterSituation(ss.advice ?? currentAdvice(), focus: ss.investFocus, profileKnown: known);
    if (!known) _tr('SENT', ['DEBT_CHECK']);
    if (!await _say(msg, 'talk', ep)) return;
    if (known) return _replyAfterLoss(ep);
    _settle();
  }

  Future<void> _replyLoss(int ep) async {
    final ss = s!;
    ss.awaiting = 'loss';
    ss.lock = true;
    _tr('SENT', ['PROFILING']);
    if (!await _say(ls.lossAsk(), 'talk', ep)) return;
    _settle();
  }

  Future<void> _replyRecommend(int ep) async {
    final ss = s!;
    ss.awaiting = 'recommend';
    ss.lock = true;
    ss.advice = currentAdvice();
    final msg = ls.recommendMessage(ss.advice!, ss.expText, ss.lossText, ss.seed, ack: ss.keepAck ? ls.keepAck() : '');
    ss.keepAck = false;
    if (fsm.state == 'LOSS' || fsm.state == 'SHORTFALL') {
      _tr('SENT');
    } else {
      _tr('PROFILED', ['DEBT_CHECK']);
    }
    if (!await _say(msg, 'talk', ep)) return;
    _settle();
  }

  /// 손실 답변 뒤: 투자 비중대로 목표에 못 미치면 부족분을 알리고 선택지를 낸다. 닿으면 바로 추천으로 간다
  Future<void> _replyAfterLoss(int ep) async {
    final ss = s!;
    ss.advice = currentAdvice();
    final info = la.shortfall(ss.advice);
    if (info == null) return _replyRecommend(ep);
    ss.shortfall = info;
    ss.awaiting = 'shortfall';
    ss.lock = true;
    _tr('GAP', ['LOSS', 'DEBT_CHECK']);
    if (!await _say(ls.shortfallMessage(ss.advice!, info), 'talk', ep)) return;
    _settle();
  }

  /// 목표 조정은 새 목표로 다시 계산하고, 그래도 부족하면 같은 안내를 다시 낸다
  la.LumpGoal _adjustedGoal(String choiceId) {
    final cur = s!.goal ?? la.lumpGoals['goal-100']!;
    final amount = choiceId == 'sf-amount' ? 50000000 : cur.amount;
    return la.LumpGoal(amount: amount, months: 60, text: '${ls.goalPhrase(60, amount)} 만들고 싶어요');
  }

  /// 목표를 바꿔 다시 판단한다. 바뀐 목표로 판단 문장·카드·질문을 다시 내고, 판단 단계(DEBT_CHECK)로 돌아간다.
  /// 이미 성향을 답했으면 이어지는 "예"에서 성향을 다시 묻지 않는다.
  Future<void> _replyAdjust(int ep) async {
    final ss = s!;
    ss.awaiting = 'adjust';
    ss.lock = true;
    ss.goal = _adjustedGoal(ss.adjustChoice);
    ss.shortfall = null;
    ss.boldShare = null;
    ss.advice = currentAdvice();
    _tr('ADJUST', ['SHORTFALL']);
    if (!await _say(ls.decisionMessage(ss.advice!, adjusted: ss.goal, skipFill: ss.fromEmergency), 'decision', ep)) return;
    _settle();
  }

  Future<void> _handleShortfall(int ep, String? choiceId) async {
    final ss = s!;
    final info = ss.shortfall;
    if (choiceId == 'sf-bold' && info?.neededShare != null) {
      ss.boldShare = info!.neededShare;
      ss.shortfall = null;
      return _replyRecommend(ep);
    }
    if (choiceId == 'sf-amount' || choiceId == 'sf-period') {
      ss.adjustChoice = choiceId!;
      return _replyAdjust(ep);
    }
    ss.shortfall = null;
    ss.keepAck = true;
    return _replyRecommend(ep);
  }

  Future<void> _replySide(int ep) async {
    final ss = s!;
    ss.lock = true;
    _tr('OTHER');
    if (!await _say(ls.sideStop(ss.advice ?? currentAdvice()), 'talk', ep)) return;
    _settle(closePrompt: true);
  }

  /// 레버리지 상품: 이번 상담에서는 이어 가지 않는다고 말하고 국내·해외를 다시 묻는다
  Future<void> _replyLeverage(int ep) async {
    final ss = s!;
    ss.awaiting = 'leverage';
    ss.lock = true;
    ss.leverageDone = true;
    if (!await _say(ls.leverageRetry(), 'talk', ep)) return;
    _settle();
  }

  /// 계좌 개설을 다음으로 미룰 때: 마무리 말만 하고 상담을 닫는다
  Future<void> _replyLater(int ep) async {
    final ss = s!;
    ss.awaiting = 'later';
    ss.lock = true;
    if (!await _say(ls.laterMessage(), 'talk', ep)) return;
    _tr('LATER');
    _settle(closePrompt: true);
  }

  Future<void> _replyNoAccount(int ep) async {
    final ss = s!;
    ss.awaiting = 'noaccount';
    ss.lock = true;
    _tr('OVERSEAS');
    final a = ss.advice ?? currentAdvice();
    final msg = ss.both ? ls.bothMessage(a, _hasFx()) : ls.noAccount(a, false, _hasFx());
    if (!await _say(msg, 'talk', ep)) return;
    ss.both = false;
    _settle();
  }

  void _handoff() {
    final ss = s!;
    // 해외주식 첫 시작은 목돈 판단이 없으므로 월 투자 금액을 넘기지 않는다
    final advice = ss.intent == 'OVERSEAS' ? null : (ss.advice ?? currentAdvice());
    final goalText = ss.goal?.text ?? '';
    app.publishContext(
      goal: goalText,
      knownFromAccount: [
        KnownLine(label: '월급', text: formatMan(ss.snap.income), source: '조회'),
        KnownLine(label: '지출', text: formatMan(ss.snap.expense), source: '조회'),
      ],
      decisionId: advice?.decisionId,
      financialSummary: advice == null ? null : FinancialSummary(monthly: advice.monthlyInvest, source: '계좌 정보 기준', adjustable: true),
    );
    final started = app.join.start('OVERSEAS_STOCK', goalText: goalText, monthly: advice?.monthlyInvest);
    _tr('OPEN');
    ss.prompt = const LumpPrompt();
    ss.lock = false;
    if (started) {
      app.navigate(ScreenId.joinConsent);
    } else {
      _refresh();
    }
  }

  /// 채팅을 열면 AI가 먼저 목표를 묻는다. 생각 연출 없이 글자 흐름만 쓴다
  Future<void> _replyGreeting(int ep) async {
    final ss = s!;
    ss.awaiting = 'greeting';
    ss.lock = true;
    _refresh();
    if (!await _say(ls.greeting(), null, ep)) return;
    _settle();
  }

  Future<void> _continueAwaiting(int ep) async {
    final ss = s;
    if (ss == null) return;
    switch (ss.awaiting) {
      case 'analysis':
        return _replyAnalysis(ep);
      case 'decision':
        return _replyDecision(ep);
      case 'profile':
        return _replyAfterUser3(ep);
      case 'shortfall':
        return _replyAfterLoss(ep);
      case 'overseas':
        return _replyOverseasIntro(ep);
      case 'goalask':
        return _replyGoalAsk(ep);
      case 'loss':
        return _replyLoss(ep);
      case 'recommend':
        return _replyRecommend(ep);
      case 'noaccount':
        return _replyNoAccount(ep);
      case 'greeting':
        return _replyGreeting(ep);
      case 'saved':
        return _replySaved(ep);
      case 'adjust':
        return _replyAdjust(ep);
      case 'leverage':
        return _replyLeverage(ep);
      case 'later':
        return _replyLater(ep);
    }
    ss.awaiting = '';
    ss.lock = false;
  }

  Future<void> accept(String text, [String? choiceId]) {
    final ss = s;
    if (ss == null || ss.lock) return Future.value();
    final spoken = text.trim();
    if (spoken.isEmpty) return Future.value();
    _clearType();
    ss.typing = false;
    ss.draft = '';
    _push(role: 'user', text: spoken);
    final ep = app.epoch;
    final st = fsm.state;
    ss.lock = true;
    // 답한 뒤에는 이전 질문의 선택지를 치운다. 응답이 끝나면 syncPrompt가 다음 선택지를 채운다
    ss.prompt = const LumpPrompt();
    _refresh();
    return _enqueue(() async {
      if (_stale(ep)) return;
      if (st == 'INTRO') {
        // 해외주식 첫 시작은 목돈 분석과 목표 질문 없이 계좌 개설로 바로 이어 간다
        if (ls.isOverseasIntro(spoken)) {
          ss.goalKind = 'OVERSEAS_ACCOUNT';
          ss.intent = 'OVERSEAS';
          ss.market = 'os';
          return _replyOverseasIntro(ep);
        }
        ss.intent = '';
        ss.purposeLabel = ls.purposeLabelOf(spoken);
        // 비상자금: 같은 분석 카드로 점검 결과를 말하고, 목돈 마련도 볼지 묻는다
        if (ls.isEmergencyIntro(spoken)) {
          ss.goalKind = 'EMERGENCY';
          ss.intent = 'EMERGENCY';
          return _replyAnalysis(ep);
        }
        // 그 밖의 말은 목돈 마련. 금액과 기간을 함께 말했으면 그 목표로 바로 계산한다
        ss.goalKind = 'LUMP_SUM';
        final goal = await _introGoal(spoken);
        if (_stale(ep)) return;
        if (goal != null) ss.goal = goal;
        return _replyAnalysis(ep);
      }
      if (st == 'GOAL' && ss.intent == 'EMERGENCY') {
        // 비상자금 점검 뒤 "목돈 마련도 같이 볼까요?"에 대한 답. 직접 쓴 말도 "아니요"면 마친다
        final no = choiceId == 'em-no' || (choiceId == null && RegExp(r'아니|마칠|그만|괜찮|비상자금만').hasMatch(spoken));
        if (no) return _replyEmergencyStop(ep);
        ss.intent = '';
        ss.fromEmergency = true;
        ss.goalKind = 'LUMP_SUM';
        return _replyGoalAsk(ep);
      }
      if (st == 'GOAL') {
        ss.goal = _goalFrom(spoken, choiceId);
        return _replyDecision(ep);
      }
      if (st == 'DEBT_CHECK') {
        // 투자로도 어려울 때는 목표를 낮추거나 기간을 늘리는 선택지가 함께 나온다
        if (choiceId == 'sf-amount' || choiceId == 'sf-period') {
          ss.adjustChoice = choiceId!;
          return _replyAdjust(ep);
        }
        // 판단 뒤 "투자 비중도 같이 볼까요?"에 대한 답. 직접 쓴 말도 "아니요"면 마친다
        final no = choiceId == 'inv-no' || (choiceId == null && RegExp(r'아니|마칠|그만|괜찮').hasMatch(spoken));
        if (no) return _replyStop(ep);
        ss.situationDone = true;
        // 선택지로 "예"라고 한 것과 직접 쓴 것은 다르다. 직접 쓴 말만 투자 비중을 높인다
        ss.investFocus = choiceId == null;
        return _replyAfterUser3(ep);
      }
      if (st == 'SPEND_PLAN') return _replySaved(ep);
      if (st == 'PROFILING') {
        ss.expText = spoken;
        return _replyLoss(ep);
      }
      if (st == 'LOSS') {
        ss.lossText = spoken;
        return _replyAfterLoss(ep);
      }
      if (st == 'SHORTFALL') return _handleShortfall(ep, choiceId);
      if (st == 'RECOMMEND') {
        if (choiceId == null && RegExp(r'모두|둘 다|두 계좌|같이').hasMatch(spoken)) {
          ss.goalKind = 'OVERSEAS_ACCOUNT';
          ss.both = true;
          ss.market = 'both';
          return _replyNoAccount(ep);
        }
        if (choiceId == 'prod-os' || (choiceId == null && RegExp(r'해외|미국').hasMatch(spoken))) {
          ss.goalKind = 'OVERSEAS_ACCOUNT';
          ss.market = 'os';
          return _replyNoAccount(ep);
        }
        // 레버리지는 이번 상담에서 이어 가지 않고, 국내·해외를 다시 묻는다
        if (choiceId == 'prod-lev') return _replyLeverage(ep);
        ss.market = 'dom';
        ss.goalKind = 'DOMESTIC_STOCK';
        return _replySide(ep);
      }
      if (st == 'NO_ACCOUNT') {
        if (choiceId == 'open-no' || spoken.contains('다음에')) return _replyLater(ep);
        _handoff();
      }
    });
  }

  void _clearType() {
    _typeTimer?.cancel();
    _typeTimer = null;
  }

  /// 입력창을 눌렀을 때만 호출한다. 선택지에 원하는 상황이 없을 때 보여 주는 타이핑이다
  void startTyping() {
    final ss = s;
    if (ss == null || ss.lock || ss.typing || ss.prompt.typeText.isEmpty) return;
    if (_scale == 0) {
      accept(ss.prompt.typeText);
      return;
    }
    ss.typing = true;
    ss.draft = '';
    final full = ss.prompt.typeText;
    var i = 0;
    final typoAt = (full.length - 2) < (4 + ss.seed % 6) ? full.length - 2 : 4 + ss.seed % 6;
    var fixing = false, typoDone = false;
    final started = nowMs();
    final kick = 300 + ss.seed % 300;
    void next(int ms, void Function() fn) => _typeTimer = Timer(Duration(milliseconds: ms), fn);
    late void Function() step;
    step = () {
      final cur = s;
      if (cur == null || !cur.typing) return;
      if (nowMs() - started < kick) return next(40, step);
      if (!typoDone && !fixing && i == typoAt) {
        cur.draft = '${full.substring(0, i)}ㄱ';
        _paint();
        fixing = true;
        return next(140, step);
      }
      if (fixing) {
        fixing = false;
        typoDone = true;
        cur.draft = full.substring(0, i);
        _paint();
        return next(80, step);
      }
      i += 1;
      cur.draft = full.substring(0, i);
      _paint();
      if (i >= full.length) {
        cur.typing = false;
        return next(280, () => accept(full));
      }
      final ch = full[i - 1];
      next(ch == ' ' || ch == ',' || ch == '.' ? 160 : 50 + (i * 17) % 40, step);
    };
    _paint();
    next(30, step);
  }

  void finishTypeNow() {
    final ss = s;
    if (ss == null || ss.prompt.typeText.isEmpty) return;
    _clearType();
    ss.typing = false;
    accept(ss.prompt.typeText);
  }

  bool startNew() {
    final f = fsm;
    if (f.state != 'IDLE' && f.can('NEW_CASE')) f.transition('NEW_CASE');
    if (f.state != 'IDLE') return false;
    _clearType();
    app.session.lumpsum = _fresh(_readSnap());
    f.transition('START');
    _syncPrompt();
    app.refresh(_screens);
    app.navigate(ScreenId.lumpsum);
    final ss = s!;
    if (_scale == 0) {
      final row = _push(role: 'ai', blocks: ls.greeting().blocks)!;
      row.shown = row.blocks.length;
      _refresh();
    } else {
      final ep = app.epoch;
      ss.awaiting = 'greeting';
      ss.lock = true;
      _enqueue(() => _replyGreeting(ep));
    }
    return true;
  }

  /// 진행 중이던 상담이 있어도 버리고 새 채팅을 연다 (홈 프롬프트 쿠키의 물어보기).
  /// 진행 중이던 비동기 응답은 epoch를 올려 이후 상태를 건드리지 못하게 한다.
  bool startFresh([String text = '']) {
    final f = fsm;
    if (f.state != 'IDLE') {
      app.invalidate();
      if (f.can('EXIT')) f.transition('EXIT');
      if (f.can('NEW_CASE')) f.transition('NEW_CASE');
    }
    final ok = startNew();
    final line = text.trim();
    if (ok && line.isNotEmpty) {
      // 인사가 끝난 뒤 쿠키의 문장을 입력창에 타이핑하고 전송한다
      final ep = app.epoch;
      _enqueue(() async {
        if (_stale(ep)) return;
        await _sleep(500);
        final ss = s;
        if (_stale(ep) || ss == null || ss.lock || fsm.state != 'INTRO') return;
        ss.prompt = ss.prompt.withTypeText(line);
        startTyping();
      });
    }
    return ok;
  }

  bool open() {
    if (fsm.state == 'IDLE' || s == null) return startNew();
    _syncPrompt();
    app.navigate(ScreenId.lumpsum);
    return true;
  }

  void resume() {
    final ss = s;
    if (ss == null || _pending > 0) return;
    ss.typing = false;
    ss.thinking = false;
    ss.stopStream = false;
    ss.chat = ss.chat.where((m) => !m.streaming).toList();
    if (ss.awaiting.isNotEmpty) {
      final ep = app.epoch;
      ss.lock = false;
      _enqueue(() => _continueAwaiting(ep));
      return;
    }
    ss.lock = false;
    _syncPrompt();
  }

  LumpsumHint hint() {
    final ss = s;
    if (ss == null || fsm.state == 'IDLE') return const LumpsumHint(active: false);
    final p = ss.prompt;
    var line = '';
    if (p.mode == 'type' && p.typeText.isNotEmpty) {
      line = '입력창을 눌러 타이핑: ${p.typeText}';
    } else if (p.mode == 'choice') {
      line = '선택지를 누르세요: ${p.demoChoice}${p.typeText.isNotEmpty ? ' · 맞는 게 없으면 입력창 타이핑: ${p.typeText}' : ''}';
    }
    final a = ss.advice;
    final decision = a != null ? '이번 채팅: ${decisionLabel[a.decisionId] ?? a.decisionId} · 월 여유 ${formatMan(a.surplus < 0 ? 0 : a.surplus)}' : '';
    return LumpsumHint(active: !['IDLE', 'CLOSED', 'TO_JOIN'].contains(fsm.state), line: line, decision: decision);
  }

  /* ------------------------------------------------------------------
   * 화면 동작
   * ------------------------------------------------------------------ */

  /// 보내기 버튼: 글자 흐름 중이면 멈추고, 타이핑 중이면 바로 끝내고, 아니면 타이핑을 시작한다
  void send() {
    final ss = s;
    if (ss == null) return;
    if (ss.chat.any((m) => m.streaming)) {
      ss.stopStream = true;
      return;
    }
    if (ss.typing) return finishTypeNow();
    startTyping();
  }

  Future<void> choice(String id, String label) async {
    if (id == 'spend-view') {
      if (fsm.state == 'SPEND_PLAN') await app.navigate(ScreenId.spend);
      return;
    }
    return accept(textOf(id, label), id);
  }

  Future<void> end() async {
    _clearType();
    if (fsm.can('EXIT')) fsm.transition('EXIT');
    if (fsm.can('NEW_CASE')) fsm.transition('NEW_CASE');
    app.session.lumpsum = null;
    app.save();
    await app.navigate(ScreenId.home, resetHistory: true);
  }

  void toggle(String rowId) {
    final row = s?.chat.where((m) => m.id == rowId).lastOrNull;
    if (row == null) return;
    row.open = !row.open;
    _refresh();
  }
}
