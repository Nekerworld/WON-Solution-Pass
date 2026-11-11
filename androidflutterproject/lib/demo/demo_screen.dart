/// 발표자용 시연 제어 화면 (홈 상단 </> 버튼으로 연다).
/// 실제 금융 앱의 기능이 아니며, 가상 은행 상태를 바꾸고 내부 상태를 관찰하는 도구다.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/router.dart';
import '../domain/bank_state.dart';
import '../domain/formatters.dart';
import '../domain/policy.dart';
import '../ui/app_scope.dart';
import '../ui/theme.dart';
import 'graph_painters.dart';

class DemoPreset {
  const DemoPreset(this.id, this.label, this.desc, this.apply);

  final String id;
  final String label;
  final String desc;
  final void Function(BankState d) apply;
}

final List<DemoPreset> demoPresets = [
  DemoPreset('A', 'A 정상 복구', 'OTP 미등록 + 한도 부족 (기본 시나리오)', (_) {}),
  DemoPreset('B', 'B OTP만', '한도 200만원, OTP 미등록', (d) => d.customer.transferLimit = 2000000),
  DemoPreset('C', 'C 한도만', 'OTP 등록, 한도 100만원', (d) => d.customer.digitalOtpRegistered = true),
  DemoPreset('D', 'D 모두 충족', 'OTP 등록, 한도 200만원', (d) {
    d.customer.digitalOtpRegistered = true;
    d.customer.transferLimit = 2000000;
  }),
  DemoPreset('E', 'E 계좌 제한', '계좌 이용 제한 상태', (d) => d.customer.accountRestricted = true),
  DemoPreset('F', 'F 은행 장애', '은행 시스템 이용 불가', (d) => d.system.bankAvailable = false),
  DemoPreset('K', 'KYC 미완료', '고객확인 → OTP → 한도 순서 계산', (d) => d.customer.kycCompleted = false),
  DemoPreset('N', '경로 없음', '비대면 한도 변경 불가', (d) => d.customer.transferLimitChangeAllowed = false),
];

class _Switch {
  const _Switch(this.label, this.read, this.write);

  final String label;
  final bool Function(BankState s) read;
  final void Function(BankState d, bool v) write;
}

final List<_Switch> _switches = [
  _Switch('디지털 OTP 등록', (s) => s.customer.digitalOtpRegistered, (d, v) => d.customer.digitalOtpRegistered = v),
  _Switch('고객확인 완료', (s) => s.customer.kycCompleted, (d, v) => d.customer.kycCompleted = v),
  _Switch('계좌 이용 제한', (s) => s.customer.accountRestricted, (d, v) => d.customer.accountRestricted = v),
  _Switch('은행 시스템 정상', (s) => s.system.bankAvailable, (d, v) => d.system.bankAvailable = v),
  _Switch('비대면 한도 변경 허용', (s) => s.customer.transferLimitChangeAllowed, (d, v) => d.customer.transferLimitChangeAllowed = v),
  _Switch('상태 조회 실패 주입', (s) => s.simulation.queryFailure, (d, v) => d.simulation.queryFailure = v),
];

const List<int> _limits = [500000, 1000000, 1500000, 2000000, 5000000];

const _panelBg = Color(0xFF10161F);
const _panelText = Color(0xFFD7DEE8);
const _muted = Color(0xFF7F8B9B);
const _dim = Color(0xFF5B6879);
const _accent = Color(0xFF7CC4FF);
const _boxBg = Color(0xFF0B1017);
const _boxBorder = Color(0xFF1E2734);
const _btnBg = Color(0xFF18212D);
const _btnBorder = Color(0xFF2B3646);

class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final app = s.controller;
    final store = s.store;

    void applyPreset(DemoPreset p) {
      app.resetDemo(silent: true, navigate: false);
      store.update((d) => p.apply(d), '[시연] 프리셋 ${p.label} - ${p.desc}');
      app.router.navigate(ScreenId.home, resetHistory: true, animate: false);
      app.toast('시연 프리셋: ${p.label}');
      Navigator.of(context).pop();
    }

    return Scaffold(
      backgroundColor: _panelBg,
      body: SafeArea(
        child: DefaultTextStyle(
          style: ts(12.5, color: _panelText),
          child: ListenableBuilder(
            listenable: Listenable.merge([store, app.fsm, s.events]),
            builder: (context, _) {
              final st = store.state;
              final open = st.transactions.values.where((t) => t.status.isUnresolved).toList();
              final hist = app.fsm.history();
              final last = s.pathfinder.lastResult;
              final logs = s.events.list().reversed.take(60).toList();
              return Column(
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
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                      children: [
                        _Section(
                          title: '시나리오 프리셋',
                          children: [
                            _Grid([for (final p in demoPresets) _DpButton(p.label, tooltip: p.desc, onTap: () => applyPreset(p))]),
                            const _Note('프리셋은 데모를 초기화한 뒤 가상 은행 상태를 설정합니다. 이후 앱에서 이체를 시도하세요.'),
                          ],
                        ),
                        _Section(
                          title: '가상 은행 상태',
                          children: [
                            for (final sw in _switches)
                              _Row(
                                label: sw.label,
                                trailing: Switch(
                                  value: sw.read(st),
                                  activeTrackColor: const Color(0xFF0067AC),
                                  inactiveTrackColor: _btnBg,
                                  inactiveThumbColor: _muted,
                                  trackOutlineColor: const WidgetStatePropertyAll(_btnBorder),
                                  onChanged: (v) => store.update((d) => sw.write(d, v), '[시연] ${sw.label} → ${v ? 'ON' : 'OFF'}'),
                                ),
                              ),
                            _Row(
                              label: '1일 이체한도',
                              trailing: DropdownButton<int>(
                                value: st.customer.transferLimit,
                                dropdownColor: _btnBg,
                                style: ts(12.5, color: _panelText),
                                underline: const SizedBox.shrink(),
                                items: [
                                  for (final v in {..._limits, st.customer.transferLimit}.toList()..sort())
                                    DropdownMenuItem(value: v, child: Text(formatWon(v))),
                                ],
                                onChanged: (v) {
                                  if (v != null) store.update((d) => d.customer.transferLimit = v, '[시연] 1일 이체한도 → ${formatWon(v)}');
                                },
                              ),
                            ),
                          ],
                        ),
                        _Section(
                          title: '다음 거래 결과 (가상 은행 응답)',
                          children: [
                            _Grid([
                              for (final o in const [TransferStatus.success, TransferStatus.failed, TransferStatus.pending, TransferStatus.unknown])
                                _DpButton(
                                  o.code,
                                  active: st.simulation.nextTransferOutcome == o,
                                  onTap: () => store.update((d) => d.simulation.nextTransferOutcome = o, '[시연] 다음 거래 결과 → ${o.code}'),
                                ),
                            ]),
                            if (open.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              for (final t in open)
                                _Row(
                                  label: '${t.id} · ${t.status.code}',
                                  trailing: Wrap(
                                    spacing: 6,
                                    children: [
                                      _DpButton('은행 확정 SUCCESS', onTap: () => s.bank.demoResolveTransaction(t.id, TransferStatus.success)),
                                      _DpButton('FAILED', onTap: () => s.bank.demoResolveTransaction(t.id, TransferStatus.failed)),
                                    ],
                                  ),
                                ),
                              const _Note('은행 측 처리 확정을 시뮬레이션합니다. 앱에서는 사용자가 결과 조회를 눌러야 반영됩니다.'),
                            ],
                          ],
                        ),
                        _Section(
                          title: '정책 가중치',
                          tag: DemoPolicy.version,
                          children: [
                            for (final e in DemoPolicy.actionWeights.entries)
                              _Row(
                                label: '${actionShort(e.key)}  ${e.key}',
                                trailing: Text('${e.value}', style: ts(12.5, weight: FontWeight.w700, color: Colors.white)),
                              ),
                            const _Note('상태 그래프 간선의 비용입니다. 경로 탐색은 비용 합이 가장 작은 경로를 고릅니다. (가상 정책)'),
                          ],
                        ),
                        _Section(
                          title: '해결패스 상태머신',
                          tag: app.fsm.state.code,
                          children: [
                            _GraphBox(
                              width: FsmGraphPainter.canvasSize.width,
                              height: FsmGraphPainter.canvasSize.height,
                              painter: FsmGraphPainter(app.fsm.state, hist),
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
                                          TextSpan(text: '${h.from.code} '),
                                          TextSpan(text: '--${h.event.code}--> ', style: const TextStyle(color: _accent)),
                                          TextSpan(text: h.to.code),
                                        ]),
                                    ],
                            ),
                          ],
                        ),
                        _Section(
                          title: '해결 경로 · 상태 그래프 (다익스트라)',
                          children: [
                            if (last == null)
                              const _Note('아직 계산된 경로가 없어요. 앱에서 이체를 시도하세요.')
                            else if (last.graph == null)
                              _Note('차단 사유(${last.blocker?.code ?? last.status.name})가 있어 상태 그래프를 만들지 않았어요. 자동 해결 경로 대신 상담으로 안내합니다.')
                            else
                              Builder(builder: (context) {
                                final painter = StateGraphPainter(last.graph!);
                                return _GraphBox(width: painter.size.width, height: painter.size.height, painter: painter);
                              }),
                            if (last != null) ...[
                              const SizedBox(height: 8),
                              Text.rich(TextSpan(children: [
                                const TextSpan(text: '상태: '),
                                TextSpan(text: last.status.name.toUpperCase(), style: weightStyle(FontWeight.w700, color: Colors.white)),
                                if (last.blocker != null) TextSpan(text: ' (${last.blocker!.code})'),
                                if (last.cost != null) ...[
                                  const TextSpan(text: ' · 최소 비용 '),
                                  TextSpan(text: '${last.cost}', style: weightStyle(FontWeight.w700, color: Colors.white)),
                                ],
                              ])),
                              const SizedBox(height: 2),
                              Text(
                                last.steps.isNotEmpty ? last.steps.map((x) => x.actionId).join(' → ') : (last.fallback?.id ?? '-'),
                                style: monoStyle(11, color: _accent),
                              ),
                              _Note(
                                '상태 그래프 ${last.visited}개 노드 · 다익스트라 확정 ${last.explored}개'
                                '${last.evaluation != null ? ' · 발동 규칙 ${last.evaluation!.firedRules.isEmpty ? '없음' : last.evaluation!.firedRules.join(', ')}' : ''}',
                              ),
                            ],
                          ],
                        ),
                        _Section(
                          title: '현재 상태 JSON',
                          tag: 'v${st.system.stateVersion}',
                          children: [
                            Container(
                              constraints: const BoxConstraints(maxHeight: 220),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(color: _boxBg, border: Border.all(color: _boxBorder), borderRadius: BorderRadius.circular(8)),
                              child: SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    const JsonEncoder.withIndent('  ').convert(st.toJson()),
                                    style: monoStyle(10.5, color: const Color(0xFFA8D1FF)).copyWith(height: 1.5),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        _Section(
                          title: '이벤트 로그',
                          children: [
                            _LogBox(
                              maxHeight: 220,
                              lines: [
                                for (final l in logs)
                                  TextSpan(children: [
                                    TextSpan(text: '${formatClock(l.at)} ', style: const TextStyle(color: _dim)),
                                    TextSpan(text: '${l.source} ', style: const TextStyle(color: _accent)),
                                    TextSpan(text: l.message),
                                  ]),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.tag, required this.children});

  final String title;
  final String? tag;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: ts(11, weight: FontWeight.w700, color: _muted, letterSpacing: 0.06))),
              if (tag != null) Text(tag!, style: monoStyle(11, color: _accent)),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          trailing,
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

class _Grid extends StatelessWidget {
  const _Grid(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 6 * 3) / 4;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class _DpButton extends StatelessWidget {
  const _DpButton(this.label, {required this.onTap, this.danger = false, this.active = false, this.tooltip});

  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: active ? const Color(0xFF0067AC) : _btnBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: active ? const Color(0xFF0A7FD0) : (danger ? const Color(0xFF6B2A2D) : _btnBorder)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ts(12, weight: FontWeight.w700, color: active ? Colors.white : (danger ? const Color(0xFFFFB4B6) : _panelText), height: 1.2),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
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
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: _boxBg, border: Border.all(color: _boxBorder), borderRadius: BorderRadius.circular(10)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: CustomPaint(size: Size(width, height), painter: painter),
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
