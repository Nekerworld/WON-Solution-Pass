/// 가입 지원 - AI와 함께 (상태머신 join)
/// - 자동 단계(CHECKING, CLARIFYING, ROUTE_CHECK, RECHECKING, APPLYING, VERIFYING)는 advance()가 은행 조회로 진행한다.
///   앱을 다시 열어도 같은 단계를 은행 재조회로 이어 간다.
/// - 고객 응답이 필요한 단계에서는 멈추고 화면이 동작을 기다린다.
/// - 조건 판정은 rule_engine, 경로는 pathfinder, 문장·질문은 ai_agent가 맡는다.
/// - 업무 모달을 닫으면 결과와 상관없이 은행 조건을 다시 조회한다.
/// - 가입 요청은 고객이 승인 화면에서 승인했을 때만 보낸다.
library;

import '../domain/bank_state.dart';
import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/pathfinder.dart';
import '../domain/rule_engine.dart';
import '../domain/scenario.dart';
import 'ai_agent.dart';
import 'app_controller.dart';
import 'overlays.dart';
import 'router.dart';
import 'sessions.dart';

const List<ScreenId> _screens = [ScreenId.join, ScreenId.apply, ScreenId.applyResult, ScreenId.support, ScreenId.home];
const List<String> _auto = ['CHECKING', 'CLARIFYING', 'ROUTE_CHECK', 'RECHECKING', 'APPLYING', 'VERIFYING', 'TASK_OPEN', 'OPTIONS_READY', 'REMAINING', 'INVESTIGATING'];

const Map<String, String> exceptionLabel = {
  'QUERY_FAILED': '은행 기록 조회 실패',
  'IN_PROGRESS': '은행 처리 중',
  'ERROR': '업무 처리 오류',
  'MISMATCH': '완료 표시와 은행 기록 불일치',
};

class JoinFlow {
  JoinFlow(this.app);

  final AppController app;

  Fsm get fsm => app.joinFsm;
  JoinSession? get s => app.session.join;
  ProductDef get product => getProduct(s!.productId)!;

  bool _running = false;
  bool _again = false;
  bool get isRunning => _running;

  /* ---------------- 대화 ---------------- */
  void _push(ChatMsg Function(int id, int at) make) {
    final j = s;
    if (j == null) return;
    j.chat.add(make(j.chat.length + 1, nowMs()));
    if (j.chat.length > 80) j.chat.removeAt(0);
  }

  void _sayAI(AiResult res, {String? kind, String? tone, String? key, String? why, List<String>? plan}) {
    _push((id, at) => ChatMsg(id: id, at: at, role: 'ai', text: res.output.message, fallback: res.fallback, kind: kind, tone: tone, key: key, why: why, plan: plan));
  }

  void _sayUser(String text) => _push((id, at) => ChatMsg(id: id, at: at, role: 'user', text: text));

  void _saySystem(String text, [String? tone]) => _push((id, at) => ChatMsg(id: id, at: at, role: 'system', text: text, tone: tone));

  void _think(bool on) {
    s?.thinking = on;
    app.refresh(_screens);
  }

  bool _stale(int ep) => ep != app.epoch || s == null;

  bool _setConstraint(String key, bool value, String source, [String note = '']) {
    final j = s!;
    final prev = j.constraints[key];
    j.constraints[key] = value;
    j.constraintSource[key] = (source, note);
    app.events.add('JOIN', '고객 제약 $key = $value ($source)');
    return prev != null && prev != value;
  }

  /* ---------------- 시작 / 동의 / 종료 ---------------- */
  bool start(String productId, [HandoffTerms? ctx]) {
    if (fsm.state != 'IDLE') return false;
    app.session.join = JoinSession(caseId: newId('JOIN'), productId: productId, assetContext: ctx);
    fsm.transition('START', {'productId': productId});
    return true;
  }

  Future<void> agree() async {
    if (fsm.state != 'CONSENT') return;
    fsm.transition('AGREE');
    s!.metrics.screens += 1;
    app.navigate(ScreenId.join, replace: true);
    await advance();
  }

  List<String> doneTaskLabels() {
    final j = s;
    return j == null ? [] : [for (final t in j.tasks) if (t.reflected) getTask(t.taskId)!.label];
  }

  Future<void> exit() async {
    if (!fsm.can('EXIT')) return;
    final done = doneTaskLabels();
    final joined = done.join(', ');
    final ok = await app.confirm(ConfirmRequest(
      title: '가입 지원을 멈출까요?',
      paragraphs: [
        '상품 가입은 진행되지 않아요.',
        done.isNotEmpty
            ? '지금까지 완료한 **$joined**${josa(joined, '은').substring(joined.length)} 은행에 그대로 남아요. 다음에 다시 시작하면 남은 조건만 확인해요.'
            : '은행에 변경된 내용은 없어요.',
      ],
      confirmText: '멈추기',
      cancelText: '계속하기',
    ));
    if (!ok || !fsm.can('EXIT')) return;
    fsm.transition('EXIT', {'done': done});
    app.session.join = null;
    app.navigate(ScreenId.home, resetHistory: true);
    app.toast(done.isNotEmpty ? '완료한 업무는 유지돼요' : '가입 지원을 멈췄어요');
  }

  void newCase() {
    if (!fsm.can('NEW_CASE')) return;
    final j = s;
    if (j != null && j.metrics.endedAt != null) app.session.lastJoinMetrics = j.metrics;
    fsm.transition('NEW_CASE');
    app.session.join = null;
    app.navigate(ScreenId.home, resetHistory: true);
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
    for (var i = 0; i < 24; i++) {
      if (_stale(ep)) return;
      final st = fsm.state;
      if (st == 'CHECKING') {
        await _stepCheck(ep);
      } else if (st == 'CLARIFYING') {
        if (await _stepClarify(ep)) return;
      } else if (st == 'ROUTE_CHECK') {
        await _stepRoute(ep);
      } else if (st == 'OPTIONS_READY' || st == 'REMAINING') {
        await _stepPlanInPlace(ep);
        return;
      } else if (st == 'TASK_OPEN') {
        if (app.isTaskModalOpen) return;
        // 앱을 다시 여는 등으로 모달이 사라진 경우: 닫힌 것으로 보고 재확인한다
        final ct = s!.currentTask;
        if (ct != null) app.bank.cancelTask(ct.sessionId);
        fsm.transition('MODAL_CLOSED', {'reason': 'RESUME'});
      } else if (st == 'RECHECKING') {
        await _stepRecheck(ep);
      } else if (st == 'INVESTIGATING') {
        await _stepInvestigate(ep);
        return;
      } else if (st == 'APPLYING') {
        await _stepApply(ep);
      } else if (st == 'VERIFYING') {
        await _stepVerify(ep);
      } else {
        return;
      }
    }
  }

  Future<void> _stepCheck(int ep) async {
    final j = s!;
    _think(true);
    final (c, l) = await (app.bank.checkConditions(j.productId), app.bank.getLinkedAccounts()).wait;
    if (_stale(ep)) return;
    j.evaluation = evaluate(j.productId, c);
    if (!c.ok || !l.ok) {
      _think(false);
      final e = (!c.ok ? c.error : l.error)!;
      app.events.add('JOIN', '은행 기록 조회 실패: ${e.code}', {'level': 'warn'});
      _saySystem('은행 기록을 확인하지 못했어요. 잠시 후 다시 확인해 주세요.', 'warning');
      fsm.transition('QUERY_FAILED', {'code': e.code});
      return;
    }
    // 은행이 이미 아는 정보는 다시 묻지 않는다
    j.skipped = [];
    final linked = l.data!;
    if (linked.mobileOwnerVerified) j.skipped.add(('휴대폰 본인 명의', '로그인 시 확인됨'));
    if (linked.otherBankAccounts.isNotEmpty) {
      final a = linked.otherBankAccounts.first;
      _setConstraint('hasOtherBankAccount', true, 'BANK', '마이데이터 연결 계좌 ${a.bank} ${a.masked}');
      j.skipped.add(('다른 은행 계좌', '마이데이터로 확인됨 (${a.bank})'));
    }
    if (j.skipped.isNotEmpty) app.events.add('AI', '묻지 않은 질문: ${j.skipped.map((x) => '${x.$1}(${x.$2})').join(', ')}');
    final ai = await app.ai.joinExplainCheck(j.evaluation!, RouteResult(status: '-'));
    if (_stale(ep)) return;
    _think(false);
    _sayAI(ai, kind: 'check');
    fsm.transition(j.evaluation!.allMet ? 'NONE_MISSING' : 'MISSING', {'unmet': j.evaluation!.unmet});
  }

  /// 고객 답변을 기다려야 하면 true
  Future<bool> _stepClarify(int ep) async {
    final j = s!;
    final route = app.pathfinder.computeRoute(j.evaluation!, j.constraints);
    j.route = route;
    if (route.status == 'BLOCKED') {
      _escalate('BLOCKER', '앱 안에서 해결할 수 없는 가입 조건(${route.blockers.map((id) => conditions[id]!.label).join(', ')})이 있어요.');
      fsm.transition('ESCALATE', {'reason': 'BLOCKER'});
      return false;
    }
    if (await _askIfNeeded(ep, route)) return true;
    fsm.transition('CLARIFIED');
    return false;
  }

  /// P4: 경로 결정에 꼭 필요한 고객 사정만, 한도 안에서 묻는다
  Future<bool> _askIfNeeded(int ep, RouteResult route) async {
    final j = s!;
    if (route.status != 'PLAN' || route.questions.isEmpty) {
      j.pendingKey = null;
      return false;
    }
    final key = route.questions.first;
    if (j.pendingKey == key) return true;
    if (j.questionsAsked >= Policy.joinQuestionLimit) {
      app.events.add('JOIN', '질문 한도 도달: 확인 안 된 사정은 선택지에서 고르게 함');
      j.pendingKey = null;
      return false;
    }
    _think(true);
    final ai = await app.ai.joinAsk(key, [for (final x in j.skipped) x.$1]);
    if (_stale(ep)) return true;
    _think(false);
    j.pendingKey = key;
    j.questionsAsked += 1;
    j.metrics.questions += 1;
    _sayAI(ai, kind: 'question', key: key, why: ai.output.why ?? constraintWhy[key]);
    return true;
  }

  Future<void> _stepRoute(int ep) async {
    final j = s!;
    final route = app.pathfinder.computeRoute(j.evaluation!, j.constraints);
    j.route = route;
    if (route.status == 'PLAN') {
      fsm.transition('ROUTE_FOUND', {'steps': route.steps.map((x) => x.actionId).toList()});
      return;
    }
    await _noRoute(ep, route, 'NO_ROUTE');
  }

  Future<void> _noRoute(int ep, RouteResult route, String event) async {
    _think(true);
    final ai = await app.ai.joinExplainNoRoute(route.cause);
    if (_stale(ep)) return;
    _think(false);
    _sayAI(ai, kind: 'noroute', tone: 'warning');
    _escalate(route.cause?.type == 'CYCLE' ? 'CYCLE' : 'NO_ROUTE', ai.output.message, route.cause);
    fsm.transition(event, {'cause': route.cause?.toJson()});
  }

  /// OPTIONS_READY / REMAINING: 경로를 다시 확인하고(P1) 필요한 질문 또는 선택지를 보여 준다
  Future<void> _stepPlanInPlace(int ep) async {
    final j = s!;
    if (fsm.state == 'REMAINING' || j.route == null || j.route!.status != 'PLAN') {
      j.route = app.pathfinder.computeRoute(j.evaluation!, j.constraints);
    }
    final route = j.route!;
    if (route.status != 'PLAN') {
      await _noRoute(ep, route, fsm.state == 'REMAINING' ? 'NO_ROUTE' : 'ESCALATE');
      return;
    }
    if (fsm.state == 'REMAINING' && await _askIfNeeded(ep, route)) return;
    final key = '${fsm.state}|${route.steps.map((x) => x.actionId).join('>')}|${route.options.map((o) => '${o.actionId}${o.availability}').join(',')}';
    if (j.presentedKey == key) return;
    _think(true);
    final ai = await app.ai.joinPresent(route);
    if (_stale(ep)) return;
    _think(false);
    List<String>? allowed;
    if (ai.valid) {
      for (final a in ai.output.actions) {
        if (a.type == 'PRESENT_OPTIONS') {
          allowed = (a['options'] as List).cast<String>();
          break;
        }
      }
    }
    j.options = [
      for (final o in route.options) o.withShown(o.availability != 'BLOCKED' && o.reachable && (allowed == null || allowed.contains(o.actionId))),
    ];
    j.presentedKey = key;
    _sayAI(ai, kind: 'options', plan: route.steps.map((x) => x.label).toList());
  }

  /* ---------------- 고객 입력 ---------------- */
  Future<void> sendText(String text) async {
    final t = text.trim();
    final j = s;
    if (t.isEmpty || j == null) return;
    final st = fsm.state;
    _sayUser(t);
    app.refresh(_screens);
    final ep = app.epoch;
    _think(true);
    final ai = await app.ai.joinInterpret(t, pendingKey: j.pendingKey);
    if (_stale(ep)) return;
    _think(false);
    final out = ai.output;
    final types = out.actions.map((a) => a.type).toList();
    if (types.contains('ESCALATE')) {
      _sayAI(ai);
      return requestConsult('CUSTOMER_REQUEST', '고객이 상담 연결을 요청했어요.');
    }
    if (types.contains('END')) {
      _sayAI(ai);
      return exit();
    }
    if (out.intent == 'REPORT_MISMATCH') {
      _sayAI(ai);
      return _reportMismatch();
    }
    final sets = out.actions.where((a) => a.type == 'SET_CONSTRAINT').toList();
    if (sets.isEmpty) {
      _sayAI(ai);
      app.refresh(_screens);
      return;
    }
    var changed = false;
    for (final a in sets) {
      if (_setConstraint(a['key'] as String, a['value'] as bool, 'CUSTOMER', '"$t"')) changed = true;
    }
    j.pendingKey = null;
    await _afterConstraints(changed, st);
  }

  /// 질문 칩(예/아니오)으로 답한 경우
  Future<void> answer(String key, bool value) async {
    final j = s;
    if (j == null || !constraintLabels.containsKey(key)) return;
    final st = fsm.state;
    _sayUser(value ? '네, 있어요' : '아니요, 없어요');
    final changed = _setConstraint(key, value, 'CUSTOMER', '질문 응답');
    j.pendingKey = null;
    await _afterConstraints(changed, st);
  }

  Future<void> _afterConstraints(bool changed, String st) async {
    final j = s!;
    if (st == 'OPTIONS_READY') {
      fsm.transition('CONSTRAINT_CHANGED', {'changed': changed});
      j.presentedKey = null;
    } else if (st == 'REMAINING') {
      j.presentedKey = null;
      j.route = null;
    }
    await advance();
  }

  /// 고객이 "완료했다고 떴는데 다시 하래요"라고 말한 경우: 은행 기록으로 다시 확인한다
  Future<void> _reportMismatch() async {
    final st = fsm.state;
    final j = s!;
    if (st != 'OPTIONS_READY' && st != 'REMAINING') return;
    final ep = app.epoch;
    _think(true);
    final c = await app.bank.checkConditions(j.productId);
    if (_stale(ep)) return;
    _think(false);
    j.evaluation = evaluate(j.productId, c);
    final last = j.lastTask;
    if (last != null) {
      final f = getTask(last.$1)!.effects.keys.first;
      if (c.ok && c.data!.facts[f] != true) {
        _saySystem('은행 기록에서 ${josa(factLabel(f), '이')} 아직 확인되지 않아요. 업무 화면 표시와 은행 기록이 달라요.', 'warning');
      }
    }
    j.presentedKey = null;
    j.route = null;
    await advance();
  }

  /// 선택지 선택 → 기존 업무 화면을 모달로 연다
  Future<void> chooseOption(String actionId) async {
    final j = s;
    final st = fsm.state;
    if (j == null || (st != 'OPTIONS_READY' && st != 'REMAINING')) return;
    RouteOption? opt;
    for (final o in j.options) {
      if (o.actionId == actionId) opt = o;
    }
    if (opt == null || opt.availability == 'BLOCKED') {
      app.toast('지금 선택할 수 없는 방법이에요.', UiTone.warning);
      return;
    }
    final task = getTask(actionId)!;
    // 이 방법을 고른 것은 필요한 준비물이 있다는 고객의 선택으로 기록한다
    for (final k in opt.unknownNeeds) {
      _setConstraint(k, true, 'CUSTOMER', '방법 선택: ${task.label}');
    }
    final r = app.bank.openTask(actionId, mode: 'modal');
    if (!r.ok) {
      app.toast(r.error!.message, UiTone.danger);
      return;
    }
    final sid = r.data!;
    j.currentTask = CurrentTask(taskId: actionId, sessionId: sid, facts: task.effects.keys.toList());
    j.metrics.tasks += 1;
    j.pendingKey = null;
    fsm.transition('TASK_OPENED', {'taskId': actionId, 'sessionId': sid});
    app.openTaskModal(actionId, sid, mode: 'ai', onClose: (status) => modalClosed(status));
  }

  Future<void> modalClosed(String? status) async {
    final j = s;
    if (j == null || fsm.state != 'TASK_OPEN') return;
    final ct = j.currentTask;
    if (ct != null && status == 'OPEN') app.bank.cancelTask(ct.sessionId);
    fsm.transition('MODAL_CLOSED', {'status': status ?? 'UNKNOWN'});
    await advance();
  }

  /* ---------------- 재확인 / 예외 ---------------- */
  Future<void> _stepRecheck(int ep) async {
    final j = s!;
    _think(true);
    final ct = j.currentTask;
    final tr = ct != null ? await app.bank.getTaskResult(ct.sessionId) : null;
    if (_stale(ep)) return;
    final c = await app.bank.checkConditions(j.productId);
    if (_stale(ep)) return;
    final ev = evaluate(j.productId, c);
    j.evaluation = ev;
    final status = tr != null && tr.ok ? tr.data!.status : null;

    String? cause;
    if (!c.ok) {
      cause = 'QUERY_FAILED';
    } else if (ev.inProgress.isNotEmpty) {
      cause = 'IN_PROGRESS';
    } else if (status == 'ERROR') {
      cause = 'ERROR';
    } else if (ct != null && status == 'COMPLETED' && ct.facts.any((f) => ev.facts![f] != true)) {
      cause = 'MISMATCH';
    }

    if (ct != null) {
      final reflected = c.ok && ct.facts.every((f) => ev.facts![f] == true);
      final rec = TaskRecord(taskId: ct.taskId, sessionId: ct.sessionId, status: status ?? 'UNKNOWN', reflected: reflected, at: nowMs());
      final idx = j.tasks.indexWhere((x) => x.sessionId == ct.sessionId);
      if (idx == -1) {
        j.tasks.add(rec);
      } else {
        j.tasks[idx] = rec;
      }
      j.lastTask = (ct.taskId, ct.sessionId, status);
      if (cause == 'MISMATCH' || cause == 'ERROR') {
        for (final f in ct.facts) {
          j.repeat[f] = (j.repeat[f] ?? 0) + 1;
        }
      }
    }
    j.presentedKey = null;
    j.route = null;

    if (cause != null) {
      j.exception = JoinException(cause: cause, taskId: ct?.taskId, sessionId: ct?.sessionId, facts: ct?.facts ?? const []);
      final ai = await app.ai.joinAfterRecheck('EXCEPTION');
      if (_stale(ep)) return;
      _think(false);
      _sayAI(ai, tone: 'warning');
      fsm.transition('EXCEPTION', {'cause': cause});
      return;
    }
    j.currentTask = null;
    j.exception = null;
    if (ev.allMet) {
      final ai = await app.ai.joinAfterRecheck('ALL_MET');
      if (_stale(ep)) return;
      _think(false);
      _sayAI(ai, kind: 'ready');
      fsm.transition('ALL_MET');
      return;
    }
    var detail = '';
    if (status == 'CANCELLED') {
      detail = '업무를 마치지 않고 닫으셨어요.';
    } else if (status == 'PARTIAL') {
      detail = '일부 단계만 저장돼서 아직 완료되지 않았어요.';
    } else if (ct != null && status == 'COMPLETED') {
      detail = '${josa(getTask(ct.taskId)!.label, '이')} 은행 기록에 반영됐어요.';
    }
    final remain = [for (final x in ev.conditions) if (x.status != 'MET') x.label];
    final ai = await app.ai.joinAfterRecheck('REMAINING', '$detail 남은 조건은 ${josa(remain.join(', '), '이에요')}.');
    if (_stale(ep)) return;
    _think(false);
    _sayAI(ai);
    fsm.transition('REMAINING', {'remain': ev.unmet});
  }

  Future<void> _stepInvestigate(int ep) async {
    final j = s!;
    final ex = j.exception;
    if (ex == null || ex.explained) return;
    final over = ex.facts.any((f) => (j.repeat[f] ?? 0) >= Policy.repeatLimit);
    if ((ex.cause == 'MISMATCH' || ex.cause == 'ERROR') && over) {
      final label = ex.taskId != null ? getTask(ex.taskId!)!.label : '업무';
      _saySystem('${josa(label, '을')} ${Policy.repeatLimit}번 진행했지만 은행 기록에 반영되지 않았어요. 같은 업무를 계속 반복하지 않고 상담으로 연결할게요.', 'warning');
      _escalate('REPEAT', '$label 완료 후에도 은행 기록 미반영이 ${Policy.repeatLimit}회 반복됐어요.');
      fsm.transition('UNRESOLVABLE', {'cause': ex.cause});
      return;
    }
    ex.explained = true;
    const text = {
      'QUERY_FAILED': '은행 기록을 다시 조회하지 못했어요. 확인되지 않은 상태로 다음 단계로 넘어가지 않아요.',
      'IN_PROGRESS': '업무가 은행에서 아직 처리 중이에요. 처리 결과를 조회해서 확인할게요.',
      'ERROR': '업무 처리 중 오류가 났어요. 은행에 바뀐 내용은 없어요.',
      'MISMATCH': '업무 화면에서는 완료로 표시됐지만 은행 기록에는 아직 반영되지 않았어요.',
    };
    _saySystem(text[ex.cause] ?? '', 'warning');
    app.refresh(_screens);
  }

  /// 예외 화면의 버튼: requery | retry | consult
  Future<void> investigate(String kind) async {
    final j = s;
    if (j == null || fsm.state != 'INVESTIGATING') return;
    final ex = j.exception;
    final ep = app.epoch;
    if (kind == 'consult') {
      _escalate('EXCEPTION', '업무 처리 결과를 확인하지 못했어요.');
      fsm.transition('UNRESOLVABLE', {'cause': ex?.cause, 'by': 'customer'});
      app.refresh(_screens);
      return;
    }
    if (kind == 'retry') {
      _sayUser('다시 진행할게요');
      j.currentTask = null;
      j.exception = null;
      fsm.transition('RETRY');
      return advance();
    }
    // requery: 처리 중이던 업무 결과를 조회하면 은행 처리가 끝났는지 알 수 있다
    _sayUser('처리 결과 다시 확인해 주세요');
    if (ex?.cause == 'IN_PROGRESS' && ex?.sessionId != null) {
      _think(true);
      final r = await app.bank.getTaskResult(ex!.sessionId!);
      if (_stale(ep)) return;
      _think(false);
      if (r.ok && r.data!.status == 'IN_PROGRESS') {
        _saySystem('아직 처리 중이에요. 잠시 후 다시 확인해 주세요.', 'warning');
        app.refresh(_screens);
        return;
      }
    }
    j.exception = null;
    fsm.transition('RESOLVED');
    await advance();
  }

  /* ---------------- 상담 연결 ---------------- */
  void _escalate(String reason, String text, [RouteCause? cause]) {
    final j = s!;
    j.escalation = Escalation(reason: reason, text: text, cause: cause);
    j.consult = null;
    j.handoff = null;
    j.handoffConsent = false;
  }

  Future<void> requestConsult(String reason, String text) async {
    if (fsm.state == 'INVESTIGATING') {
      await investigate('consult');
      app.navigate(ScreenId.support, params: {'track': 'join'});
      return;
    }
    if (!fsm.can('ESCALATE')) {
      app.toast('지금 단계에서는 상담 연결 대신 진행 중인 처리를 먼저 확인해요.', UiTone.warning);
      return;
    }
    _escalate(reason, text);
    fsm.transition('ESCALATE', {'reason': reason});
    app.refresh(_screens);
    app.navigate(ScreenId.support, params: {'track': 'join'});
  }

  Future<void> recheckFromEscalated() async {
    if (fsm.state != 'ESCALATED') return;
    final j = s!;
    j.escalation = null;
    j.presentedKey = null;
    fsm.transition('RECHECK');
    app.navigate(ScreenId.join, backTo: true);
    await advance();
  }

  /* ---------------- 가입 신청 ---------------- */
  Future<void> approve(ApplyTerms terms) async {
    final j = s;
    if (j == null || fsm.state != 'READY_TO_APPLY') return;
    final p = product;
    final ok = await app.confirm(ConfirmRequest(
      title: '가입을 승인할까요?',
      rows: terms.market != null
          ? [
              ConfirmRow('상품', p.name),
              ConfirmRow('거래 시장', terms.market!),
              ConfirmRow('연결 원화 계좌', terms.account ?? ''),
              ConfirmRow('연결 외화 계좌', terms.fxAccount ?? ''),
            ]
          : [
              ConfirmRow('상품', p.name),
              ConfirmRow('월 납입액', formatMan(terms.monthly ?? 0)),
              ConfirmRow('가입 기간', '${terms.months}개월'),
              ConfirmRow('출금 계좌', terms.account ?? ''),
            ],
      fineprint: '승인하시면 은행에 가입을 요청해요. 가입 완료는 은행 처리 결과로 확인해요.',
      confirmText: '승인하고 가입 요청',
      cancelText: '취소',
    ));
    if (!ok || fsm.state != 'READY_TO_APPLY') return;
    j.terms = terms;
    j.requestId ??= app.bank.newRequestId();
    j.applyNotice = null;
    fsm.transition('APPROVED', {'requestId': j.requestId});
    app.navigate(ScreenId.applyResult, params: {'track': 'join'}, replace: true);
    await advance();
  }

  Future<void> _stepApply(int ep) async {
    final j = s!;
    final r = await app.bank.submitApplication(requestId: j.requestId!, productId: j.productId, terms: j.terms, channel: 'AI');
    if (_stale(ep)) return;
    if (!r.ok) {
      final e = r.error!;
      if (e.code == 'CONDITION_UNMET') {
        j.applyNotice = ApplyNotice('warning', '은행이 가입 조건을 다시 확인한 결과 충족하지 않은 조건이 있어요 (${(e.unmet ?? const []).join(', ')}). 가입되지 않았어요.');
        _saySystem(j.applyNotice!.text, 'warning');
        fsm.transition('REJECTED', {'code': e.code});
        app.navigate(ScreenId.join, replace: true);
        return;
      }
      j.applyNotice = ApplyNotice('warning', '${e.message} 같은 요청 번호로 다시 승인할 수 있어요.');
      fsm.transition('NOT_SENT', {'code': e.code});
      app.navigate(ScreenId.apply, replace: true);
      return;
    }
    j.appId = r.data!.application.id;
    j.application = r.data!.application;
    fsm.transition('SUBMITTED', {'appId': j.appId, 'duplicate': r.data!.duplicate});
  }

  Future<void> _stepVerify(int ep) async {
    final j = s!;
    final r = await app.bank.getApplicationResult(j.appId!);
    if (_stale(ep)) return;
    if (r.ok) j.application = r.data;
    final status = r.ok ? r.data!.status : 'UNKNOWN';
    if (status == 'SUCCESS') {
      j.metrics.endedAt = nowMs();
      app.session.lastJoinMetrics = j.metrics;
      fsm.transition('RESULT_SUCCESS', {'appId': j.appId});
    } else if (status == 'FAILED') {
      fsm.transition('RESULT_FAILED', {'appId': j.appId});
    } else {
      fsm.transition('RESULT_UNKNOWN', {'appId': j.appId, 'status': status});
    }
  }

  Future<void> queryResult() async {
    if (fsm.state != 'RESULT_UNCERTAIN') return;
    fsm.transition('RESULT_QUERY');
    await advance();
  }

  void escalateFailed() {
    if (fsm.state != 'FAILED') return;
    _escalate('APPLY_FAILED', s!.application?.failureReason ?? '은행이 가입 요청을 처리하지 못했어요.');
    fsm.transition('ESCALATE', {'reason': 'APPLY_FAILED'});
    app.navigate(ScreenId.support, params: {'track': 'join'}, replace: true);
  }

  /// 화면 진입 시: 처리 중이던 단계를 이어 간다
  void resume() {
    if (s == null) return;
    if (_auto.contains(fsm.state) && !_running) advance();
  }

  /// 상담 인계 요약 재료
  HandoffCtx? handoffContext() {
    final j = s;
    if (j == null) return null;
    final ev = j.evaluation;
    final cons = [
      for (final e in j.constraints.entries)
        if (e.value != null) '${constraintLabels[e.key]} ${e.value! ? '있음' : '없음'}',
    ];
    return HandoffCtx(
      reason: j.escalation?.reason ?? 'HANDOFF',
      reasonText: j.escalation?.text ?? '',
      productName: product.name,
      done: doneTaskLabels(),
      remaining: ev != null && ev.ok ? [for (final c in ev.conditions) if (c.status != 'MET') c.label] : ['은행 기록 미확인'],
      constraints: cons,
    );
  }

  /* ---------------- 화면 동작 ---------------- */

  /// 'AI와 함께 가입' 선택
  Future<void> startAction(String productId, {String? from}) async {
    final a = app.session.asset;
    final ctx = a != null && a.handoffTerms != null && from == 'asset' ? a.handoffTerms : null;
    if (fsm.state != 'IDLE') {
      if (s?.productId == productId) {
        await app.navigate(fsm.state == 'CONSENT' ? ScreenId.joinConsent : ScreenId.join);
        return;
      }
      app.toast('다른 상품의 가입 지원이 진행 중이에요. 홈에서 이어 가거나 멈춰 주세요.', UiTone.warning);
      return;
    }
    if (start(productId, ctx)) await app.navigate(ScreenId.joinConsent);
  }

  Future<void> retryCheck() async {
    if (fsm.state != 'CHECK_FAILED') return;
    fsm.transition('RETRY');
    await advance();
  }

  void openApply() {
    if (fsm.state == 'READY_TO_APPLY') app.navigate(ScreenId.apply);
  }

  /// 진행 중인 건 열기
  void open() {
    final st = fsm.state;
    if (st == 'IDLE') return;
    if (st == 'CONSENT') {
      app.navigate(ScreenId.joinConsent);
    } else if (st == 'ESCALATED') {
      app.navigate(ScreenId.support, params: {'track': 'join'});
    } else if (const ['APPLYING', 'VERIFYING', 'RESULT_UNCERTAIN', 'COMPLETED', 'FAILED'].contains(st)) {
      app.navigate(ScreenId.applyResult, params: {'track': 'join'});
    } else {
      app.navigate(ScreenId.join);
    }
  }

  /// 가입 정보 화면의 승인 버튼 (입력값 검증 후 확인 모달)
  Future<void> approveFromForm({String? market, String? account, String? fxAccount, String? monthlyText, int? months}) async {
    final p = product;
    if (p.isBrokerage) {
      await app.guard('join-approve', () => approve(ApplyTerms(market: market ?? p.markets.first, account: account, fxAccount: fxAccount)));
      return;
    }
    final monthly = digitsOf(monthlyText ?? '');
    if (monthly == 0 || monthly < p.minMonthly || monthly > p.maxMonthly) {
      app.toast('월 납입액은 ${formatMan(p.minMonthly)}~${formatMan(p.maxMonthly)} 사이로 입력해 주세요.', UiTone.warning);
      return;
    }
    if (months == null || months == 0) {
      app.toast('가입 기간을 선택해 주세요.', UiTone.warning);
      return;
    }
    await app.guard('join-approve', () => approve(ApplyTerms(monthly: monthly, months: months, account: account)));
  }
}
