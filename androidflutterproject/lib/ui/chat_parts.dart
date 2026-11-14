import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/sessions.dart';
import '../domain/asset_advisor.dart' as aa;
import '../domain/formatters.dart';
import 'icons.dart';
import 'responsive.dart';
import 'theme.dart';
import 'widgets.dart';

/// 우리WON뱅킹 AI챗봇 화면 머리: 제목, AI 배지, 보조 도구 줄.
/// [exitLabel]이 있으면 세 번째 도구 자리에 둔다 (없으면 '처음으로', 동작 없음).
class ChatHeader extends StatelessWidget {
  const ChatHeader({super.key, required this.onBack, this.exitLabel, this.onExit});

  final VoidCallback onBack;
  final String? exitLabel;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WspAppBar(title: 'AI챗봇과 대화중', onBack: onBack, right: const _AiBadge()),
        Container(
          height: 46,
          color: Colors.white,
          child: MaxWidth(
            child: Row(
              children: [
                _ToolButton(icon: AppIcons.talk, label: '톡상담', onTap: () {}),
                const _ToolDivider(),
                _ToolButton(icon: AppIcons.eyeOff, label: '상담숨기기', onTap: () {}),
                const _ToolDivider(),
                _ToolButton(icon: AppIcons.refresh, label: exitLabel ?? '처음으로', onTap: exitLabel != null ? onExit : () {}),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
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
            Text('챗봇', style: ts(9, color: Colors.white, height: 1.15)),
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
  final VoidCallback? onTap;

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

class BotAvatar extends StatelessWidget {
  const BotAvatar({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) => SvgIcon(AppIcons.botFace, size: size);
}

/// 대화 시작 머리말: 날짜, 연결 안내, 인사
class ChatIntro extends StatelessWidget {
  const ChatIntro({super.key, required this.service, required this.customerName, this.startedAt});

  final String service;
  final String customerName;
  final int? startedAt;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.fromMillisecondsSinceEpoch(startedAt ?? DateTime.now().millisecondsSinceEpoch);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE6E8EB), height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('${d.year}.${pad2(d.month)}.${pad2(d.day)}', style: ts(12, color: AppColors.text3)),
              ),
              const Expanded(child: Divider(color: Color(0xFFE6E8EB), height: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.connectedBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text('$service이 연결되었습니다.', style: ts(12, color: AppColors.chatTool)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.chatAvatarBg, shape: BoxShape.circle),
                child: const BotAvatar(size: 30),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$customerName 고객님, 안녕하세요.\n우리은행 AI챗봇입니다.',
                  style: ts(19, weight: FontWeight.w700, height: 1.45, letterSpacing: -0.03),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _clock(int at) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  return '${pad2(d.hour)}:${pad2(d.minute)}:${pad2(d.second)}';
}

/// 대화 메시지 1개
class ChatMessageView extends StatelessWidget {
  const ChatMessageView(this.m, {super.key});

  final ChatMsg m;

  @override
  Widget build(BuildContext context) {
    final maxW = (math.min(MediaQuery.sizeOf(context).width, kContentMaxWidth) - 40) * 0.86;
    final time = Text(_clock(m.at), style: ts(10.5, color: AppColors.text3));
    if (m.role == 'user') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
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
              child: Text('"${m.text}"', style: ts(14, color: Colors.white, height: 1.55)),
            ),
          ),
          const SizedBox(height: 3),
          time,
        ],
      );
    }
    if (m.role == 'system') {
      final warn = m.tone == 'warning';
      final c = warn ? AppColors.warningText : AppColors.text2;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: warn ? AppColors.warningBg : AppColors.neutralBg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: SvgIcon(warn ? AppIcons.alert : AppIcons.info, size: 16, color: c)),
            const SizedBox(width: 8),
            Expanded(child: Text(m.text, style: ts(13, color: c, height: 1.5))),
          ],
        ),
      );
    }
    final warn = m.tone == 'warning';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: BotAvatar(size: 28)),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    boxShadow: shadowCard,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: warn ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.warning, width: 3))) : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.text, style: ts(14, height: 1.6)),
                        if (m.plan != null && m.plan!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (var i = 0; i < m.plan!.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('${i + 1}. ${m.plan![i]}', style: ts(13, color: AppColors.text2, height: 1.5)),
                            ),
                        ],
                        if (m.figures != null && m.figures!.isNotEmpty) ...[const SizedBox(height: 10), FigureGrid(m.figures!)],
                        if (m.why != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(padding: const EdgeInsets.only(top: 2), child: SvgIcon(AppIcons.question, size: 13, color: AppColors.text3)),
                              const SizedBox(width: 5),
                              Expanded(child: Text(m.why!, style: ts(12, color: AppColors.text3, height: 1.5))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              time,
            ],
          ),
        ),
      ],
    );
  }
}

/// 큰 숫자 (한 번에 3개까지)
class FigureGrid extends StatelessWidget {
  const FigureGrid(this.figures, {super.key});

  final List<aa.Figure> figures;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final f in figures)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: f.tone == 'warning' ? AppColors.warningBg : const Color(0xFFF4F8FE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.label, style: ts(12, color: AppColors.text2)),
                const SizedBox(height: 2),
                Text(f.value, style: ts(18, weight: FontWeight.w700, color: f.tone == 'warning' ? AppColors.warningText : AppColors.text, letterSpacing: -0.02)),
                if (f.note.isNotEmpty) Text(f.note, style: ts(11.5, color: AppColors.text3, height: 1.45)),
              ],
            ),
          ),
      ],
    );
  }
}

/// AI가 확인하는 중 표시
class ThinkingView extends StatefulWidget {
  const ThinkingView({super.key});

  @override
  State<ThinkingView> createState() => _ThinkingViewState();
}

class _ThinkingViewState extends State<ThinkingView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AI가 생각하는 중',
      child: Row(
        children: [
          const BotAvatar(size: 28),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Builder(builder: (context) {
                    var t = (_c.value - i * 0.15) % 1;
                    if (t < 0) t += 1;
                    final k = t < 0.4 ? t / 0.4 : (t < 0.8 ? (0.8 - t) / 0.4 : 0.0);
                    return Transform.translate(
                      offset: Offset(0, -3 * k),
                      child: Opacity(
                        opacity: 0.3 + 0.7 * k,
                        child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle)),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('AI가 확인하고 있어요', style: ts(12.5, color: AppColors.text3)),
        ],
      ),
    );
  }
}

/// 메시지 목록. 마지막 메시지에 [lastKey]를 붙여 스크롤 위치를 맞춘다.
class ChatLogView extends StatelessWidget {
  const ChatLogView({super.key, required this.messages, required this.thinking, required this.lastKey});

  final List<ChatMsg> messages;
  final bool thinking;
  final GlobalKey lastKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < messages.length; i++)
          Padding(
            key: i == messages.length - 1 ? lastKey : ValueKey('m${messages[i].id}-${messages[i].at}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: RiseIn(
              key: ValueKey('r${messages[i].id}-${messages[i].at}'),
              duration: const Duration(milliseconds: 250),
              child: ChatMessageView(messages[i]),
            ),
          ),
        if (thinking) const Padding(padding: EdgeInsets.only(bottom: 12), child: ThinkingView()),
      ],
    );
  }
}

/// 가장 최근 메시지의 첫 줄이 화면 위로 밀려나지 않는 만큼만 아래로 내린다
void scrollToLatest(GlobalKey lastKey, ScrollController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    final ctx = lastKey.currentContext;
    if (ctx == null) {
      controller.animateTo(controller.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: appEase);
      return;
    }
    Scrollable.ensureVisible(ctx, alignment: 0, duration: const Duration(milliseconds: 250), curve: appEase, alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
  });
}

/// 빠른 문장 칩 줄
class QuickChips extends StatelessWidget {
  const QuickChips({super.key, required this.items, required this.onTap});

  final List<String> items;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final side = wideInsetOf(context);
    return Container(
      color: Colors.white,
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16 + side, 6, 16 + side, 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Material(
          color: AppColors.chip,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () => onTap(items[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Center(widthFactor: 1, child: Text(items[i], style: ts(13.5, color: AppColors.chatTool))),
            ),
          ),
        ),
      ),
    );
  }
}

/// 대화 입력줄
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key, required this.placeholder, required this.enabled, required this.onSend, this.fieldKey});

  final String placeholder;
  final bool enabled;
  final void Function(String text) onSend;
  final Key? fieldKey;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    if (!widget.enabled) return;
    final v = _input.text;
    _input.clear();
    widget.onSend(v);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final side = wideInsetOf(context);
    return Container(
      padding: EdgeInsets.fromLTRB(8 + side, 8, 16 + side, bottomInset > 0 ? bottomInset + 4 : 12),
      color: Colors.white,
      child: Row(
        children: [
          AppIconButton(icon: AppIcons.plus, label: '더보기', color: AppColors.chatTool, onTap: () {}),
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
                      key: widget.fieldKey,
                      controller: _input,
                      enabled: widget.enabled,
                      maxLength: 120,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: ts(14.5),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        counterText: '',
                        hintText: widget.placeholder,
                        hintStyle: ts(14, color: AppColors.text3),
                      ),
                    ),
                  ),
                  AppIconButton(
                    icon: AppIcons.send,
                    label: '전송',
                    size: 36,
                    iconSize: 20,
                    color: widget.enabled ? AppColors.chatTool : AppColors.muted,
                    onTap: widget.enabled ? _send : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
