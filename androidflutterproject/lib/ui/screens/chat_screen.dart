import 'package:flutter/material.dart';

import '../../app/chatbot_service.dart';
import '../../app/router.dart';
import '../../app/screen_data.dart';
import '../../app/session.dart';
import '../../domain/formatters.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

const List<(String, String)> _chatChips = [
  ('이체 안 됨', '이체가 왜 안 돼?'),
  ('이체한도', '이체한도 어디서 바꿔?'),
  ('디지털 OTP', 'OTP 등록했는데 아직 안 돼요.'),
  ('고객확인', '고객확인은 어떻게 해?'),
  ('이체 결과', '이체 결과 알려줘'),
];

class _ChatCard {
  const _ChatCard({required this.kw, required this.rest, required this.line2, required this.desc, required this.cta, this.q, required this.icon});

  final String kw;
  final String rest;
  final String line2;
  final String desc;
  final String cta;

  /// null이면 이체 상태 진단을 시작한다.
  final String? q;
  final SvgArt Function() icon;
}

final List<_ChatCard> _chatCards = [
  _ChatCard(
    kw: '이체',
    rest: '가 안 되나요?',
    line2: '막힌 이유를 찾아드려요',
    desc: '은행 상태로 막힌 이유를 확인해요',
    cta: '이체 상태 확인하기',
    icon: () => AppIcons.transfer,
  ),
  _ChatCard(
    kw: '이체한도',
    rest: '에 대해',
    line2: '궁금한 내용이 있으신가요?',
    desc: '현재 한도와 변경 절차를 알려드려요',
    cta: '이체한도 물어보기',
    q: '이체한도 어디서 바꿔?',
    icon: () => AppIcons.gauge,
  ),
  _ChatCard(
    kw: '이체 결과',
    rest: '가',
    line2: '궁금하신가요?',
    desc: '은행에서 확인된 결과만 안내해요',
    cta: '이체 결과 물어보기',
    q: '이체 결과 알려줘',
    icon: () => AppIcons.clock,
  ),
];

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final DateTime _openedAt = DateTime.now();
  int _lastCount = -1;
  bool _lastTyping = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = text ?? _input.text;
    if (text == null) _input.clear();
    AppScope.controllerOf(context).sendChat(q);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: appEase);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final data = widget.entry.data is ChatData ? widget.entry.data as ChatData : null;
    final name = data?.customer.data != null ? '${data!.customer.data!.customerName} 고객님' : '고객님';
    final chat = app.session.chat;
    if (chat.length != _lastCount || app.chatTyping != _lastTyping) {
      final first = _lastCount < 0;
      _lastCount = chat.length;
      _lastTyping = app.chatTyping;
      if (!first || chat.isNotEmpty) _scrollToEnd();
    }
    final now = _openedAt;
    final date = '${now.year}.${pad2(now.month)}.${pad2(now.day)}';
    final time = '${pad2(now.hour)}:${pad2(now.minute)}:${pad2(now.second)}';
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            WspAppBar(title: 'AI챗봇과 대화중', onBack: app.back, right: const _AiBadge()),
            Container(
              height: 46,
              color: Colors.white,
              child: Row(
                children: [
                  _ToolButton(icon: AppIcons.talk, label: '톡상담', onTap: () => app.goSupport()),
                  const _ToolDivider(),
                  _ToolButton(icon: AppIcons.eyeOff, label: '상담숨기기', onTap: app.noop),
                  const _ToolDivider(),
                  _ToolButton(icon: AppIcons.refresh, label: '처음으로', onTap: app.chatReset),
                ],
              ),
            ),
            Expanded(
              child: Material(
                color: AppColors.chatBg,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    _DayDivider(date),
                    const SizedBox(height: 14),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.connectedBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Text('AI챗봇 해결패스와 연결하였습니다', style: ts(12, color: AppColors.chatTool)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.chatAvatarBg, shape: BoxShape.circle),
                        child: SvgIcon(AppIcons.robotFace, size: 32),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('$name, 안녕하세요.\nWON 해결패스입니다.', style: ts(21, weight: FontWeight.w700, height: 1.45, letterSpacing: -0.03)),
                    const SizedBox(height: 10),
                    Text('이체가 막혔을 때 무엇이 궁금하신가요?', style: ts(15.5, color: AppColors.text, height: 1.5)),
                    const SizedBox(height: 4),
                    Text('생성형 AI가 아닌 규칙 기반 안내예요.', style: ts(12.5, color: AppColors.text3, height: 1.5)),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 36,
                      child: OverflowBox(
                        minWidth: MediaQuery.sizeOf(context).width,
                        maxWidth: MediaQuery.sizeOf(context).width,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _chatChips.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final (label, q) = _chatChips[i];
                            return Material(
                              color: AppColors.chip,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                onTap: () => _send(q),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 13),
                                  child: Center(widthFactor: 1, child: Text(label, style: ts(14, color: AppColors.chatTool))),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 252,
                      child: OverflowBox(
                        minWidth: MediaQuery.sizeOf(context).width,
                        maxWidth: MediaQuery.sizeOf(context).width,
                        child: Carousel(
                          height: 236,
                          viewportFraction: 0.82,
                          padEnds: false,
                          children: [
                            for (var i = 0; i < _chatCards.length; i++)
                              Padding(
                                padding: EdgeInsets.fromLTRB(i == 0 ? 20 : 6, 0, i == _chatCards.length - 1 ? 20 : 6, 0),
                                child: _ChatCardView(
                                  card: _chatCards[i],
                                  onTap: _chatCards[i].q == null ? () => app.startDiagnosis('MANUAL') : () => _send(_chatCards[i].q),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
                      child: Text(time, style: ts(12, color: AppColors.text3)),
                    ),
                    for (var i = 0; i < chat.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      RiseIn(
                        key: ValueKey('msg-$i-${chat[i].text.hashCode}'),
                        duration: const Duration(milliseconds: 250),
                        child: _Message(chat[i], onLink: app.openFlow),
                      ),
                    ],
                    if (app.chatTyping) ...[
                      if (chat.isNotEmpty) const SizedBox(height: 12),
                      const Align(alignment: Alignment.centerLeft, child: _Typing()),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(8, 10, 20, bottomInset > 0 ? bottomInset + 4 : 14),
              color: Colors.white,
              child: Row(
                children: [
                  AppIconButton(icon: AppIcons.plus, label: '더보기', color: AppColors.chatTool, onTap: app.noop),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.only(left: 14, right: 4),
                      decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              maxLength: 120,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              style: ts(14.5),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                counterText: '',
                                hintText: '메시지를 입력해 주세요',
                                hintStyle: ts(14.5, color: AppColors.text3),
                              ),
                            ),
                          ),
                          AppIconButton(icon: AppIcons.send, label: '전송', size: 36, iconSize: 20, color: AppColors.chatTool, onTap: _send),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '규칙 기반 AI 시뮬레이션',
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.aiBadgeFrom, AppColors.aiBadgeTo]),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('AI', style: ts(15, weight: FontWeight.w700, color: Colors.white, height: 1.1)),
            Text('규칙기반', style: ts(9, color: Colors.white, height: 1.15, letterSpacing: -0.04)),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});

  final SvgArt icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgIcon(icon, size: 18, color: AppColors.chatTool),
            const SizedBox(width: 5),
            Text(label, style: ts(14.5, color: AppColors.chatTool)),
          ],
        ),
      ),
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 18, color: const Color(0xFFE3E6EA));
}

class _DayDivider extends StatelessWidget {
  const _DayDivider(this.date);

  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE6E8EB), height: 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(date, style: ts(12, color: AppColors.text3))),
        const Expanded(child: Divider(color: Color(0xFFE6E8EB), height: 1)),
      ],
    );
  }
}

class _ChatCardView extends StatelessWidget {
  const _ChatCardView({required this.card, required this.onTap});

  final _ChatCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  right: 4,
                  bottom: 2,
                  child: Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.homeBand, shape: BoxShape.circle),
                    child: SvgIcon(card.icon(), size: 30, color: AppColors.blue),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: card.kw, style: const TextStyle(color: AppColors.blue)),
                          TextSpan(text: '${card.rest}\n${card.line2}'),
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ts(17, weight: FontWeight.w700, height: 1.45, letterSpacing: -0.03),
                      ),
                      const SizedBox(height: 10),
                      Text(card.desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, color: AppColors.text, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: Center(child: Text(card.cta, style: ts(15, weight: FontWeight.w700, color: Colors.white))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.m, {required this.onLink});

  final ChatMessage m;
  final void Function(String flowId) onLink;

  @override
  Widget build(BuildContext context) {
    final maxW = (MediaQuery.sizeOf(context).width - 36) * 0.88;
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(m.text, style: ts(14, color: Colors.white, height: 1.6)),
          ),
        ),
      );
    }
    final meta = <InlineSpan>[];
    WidgetSpan code(String t) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(4)),
            child: Text(t, style: monoStyle(10.5, color: AppColors.text3)),
          ),
        );
    if (m.intents.isNotEmpty || m.ruleIds.isNotEmpty || m.stateVersion != null) {
      meta.add(TextSpan(text: '의도 ${m.intents.map((i) => i.label).join(' · ')}'));
      if (m.amount != null && m.amount! > 0) meta.add(TextSpan(text: ' · 금액 ${formatMan(m.amount)}'));
      if (m.ruleIds.isNotEmpty) {
        meta.add(const TextSpan(text: ' · 근거 '));
        for (final r in m.ruleIds) {
          meta.add(code(r));
        }
      }
      if (m.stateVersion != null && m.stateVersion! > 0) {
        meta
          ..add(const TextSpan(text: ' · 상태 '))
          ..add(code('v${m.stateVersion}'));
      }
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgIcon(AppIcons.spark, size: 13, color: AppColors.blue),
                  const SizedBox(width: 4),
                  Text('WON 해결패스', style: ts(12, weight: FontWeight.w700, color: AppColors.blue)),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                ),
                boxShadow: shadowCard,
              ),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: m.tone == Tone.warning
                    ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.warning, width: 3)))
                    : null,
                child: Text(m.text, style: ts(14, height: 1.6)),
              ),
            ),
            if (m.links.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < m.links.length; i++)
                      AppButton(
                        m.links[i].label,
                        size: BtnSize.sm,
                        block: false,
                        kind: i == 0 ? BtnKind.primary : BtnKind.secondary,
                        onPressed: () => onLink(m.links[i].flowId),
                      ),
                  ],
                ),
              ),
            if (meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text.rich(TextSpan(children: meta), style: ts(11, color: AppColors.text3, height: 1.6)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(18),
        ),
        boxShadow: shadowCard,
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Builder(builder: (context) {
                // 0~80%~100% 0.3, 40%에서 1 (CSS blink), 점마다 0.15초 지연
                var t = (_c.value - i * 0.15) % 1;
                if (t < 0) t += 1;
                final k = t < 0.4 ? t / 0.4 : (t < 0.8 ? (0.8 - t) / 0.4 : 0.0);
                return Transform.translate(
                  offset: Offset(0, -3 * k),
                  child: Opacity(
                    opacity: 0.3 + 0.7 * k,
                    child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.text3, shape: BoxShape.circle)),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
