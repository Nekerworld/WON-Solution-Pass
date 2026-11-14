import 'dart:async';

import 'package:flutter/foundation.dart';

enum UiTone { neutral, info, success, warning, danger }

UiTone toneOf(String? s) => switch (s) {
      'info' => UiTone.info,
      'success' => UiTone.success,
      'warning' => UiTone.warning,
      'danger' => UiTone.danger,
      _ => UiTone.neutral,
    };

class ToastMessage {
  ToastMessage({required this.id, required this.text, required this.tone});

  final int id;
  final String text;
  final UiTone tone;
}

/// 하단 시트 공통
abstract class SheetState extends ChangeNotifier {
  bool dismissible = true;
  VoidCallback? onClose;
}

/// 상품 상세의 가입 방법 선택 (AI와 함께 / 직접 가입)
class JoinMethodSheet extends SheetState {
  JoinMethodSheet({required this.productId, required this.from, required this.joinActive, required this.directActive});

  final String productId;
  final String? from;
  final bool joinActive;
  final bool directActive;
}

/// 자산관리 상담의 정보 고치기
class AssetEditSheet extends SheetState {
  AssetEditSheet({required this.itemKey});

  final String itemKey;
}

class ConfirmRow {
  const ConfirmRow(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;
}

/// 확인 모달. 사용자가 버튼을 눌러야만 완료된다.
/// [paragraphs]의 **굵게** 표시는 굵은 글씨로 그린다.
class ConfirmRequest {
  ConfirmRequest({
    required this.title,
    this.paragraphs = const [],
    this.rows = const [],
    this.fineprint,
    this.confirmText = '확인',
    this.cancelText = '취소',
    this.danger = false,
  });

  final String title;
  final List<String> paragraphs;
  final List<ConfirmRow> rows;
  final String? fineprint;
  final String confirmText;
  final String cancelText;
  final bool danger;
  final Completer<bool> completer = Completer<bool>();

  void resolve(bool value) {
    if (!completer.isCompleted) completer.complete(value);
  }
}

/// 업무 모달의 결과 표시 (tone, 제목)
const Map<String, (UiTone, String)> taskModalStatus = {
  'COMPLETED': (UiTone.success, '업무 화면에서 완료됐어요'),
  'IN_PROGRESS': (UiTone.warning, '은행에서 처리 중이에요'),
  'PARTIAL': (UiTone.warning, '일부 단계만 저장됐어요'),
  'ERROR': (UiTone.danger, '처리 중 오류가 발생했어요'),
  'REJECTED': (UiTone.danger, '지금은 진행할 수 없어요'),
};

/// 업무 모달: 기존 업무 화면을 그대로 열고, 닫힐 때 호출자에게 알린다.
/// 업무 화면은 결과를 보여 줄 뿐이며, 완료 판정은 호출자가 은행 재조회로 한다.
class TaskModalState extends ChangeNotifier {
  TaskModalState({required this.taskId, required this.sessionId, required this.mode, this.onClose});

  final String taskId;
  final String sessionId;

  /// ai | menu
  final String mode;

  /// 닫힐 때 (status, taskId, sessionId)
  final void Function(String status)? onClose;

  /// OPEN | RUNNING | COMPLETED | IN_PROGRESS | PARTIAL | ERROR | REJECTED
  String status = 'OPEN';
  int progress = 0;
  String message = '';
  final Map<String, String> input = {};

  bool get running => status == 'RUNNING';
  bool get finished => taskModalStatus.containsKey(status);

  void changed() => notifyListeners();
}
