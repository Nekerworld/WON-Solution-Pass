import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/bank_types.dart';
import '../domain/bank_state.dart';

enum UiTone { neutral, info, success, warning, danger }

class ToastMessage {
  ToastMessage({required this.id, required this.text, required this.tone});

  final int id;
  final String text;
  final UiTone tone;
}

/// 하단 시트 공통
abstract class SheetState extends ChangeNotifier {
  bool dismissible = false;
  VoidCallback? onClose;

  void setDismissible(bool value) {
    dismissible = value;
    notifyListeners();
  }
}

class DiagSummary {
  const DiagSummary({required this.tone, required this.title, required this.body, required this.buttonLabel});

  final UiTone tone;
  final String title;
  final String body;
  final String buttonLabel;
}

/// 이체 실패 뒤 하단 모달. 조회 과정은 보여 주지 않고, 결과와 다음 화면으로 가는 버튼만 둔다.
class DiagnosisSheetState extends SheetState {
  DiagSummary? summary;

  void showSummary(DiagSummary value) {
    summary = value;
    notifyListeners();
  }
}

class AccountSheetState extends SheetState {
  AccountSheetState({required this.customer, required this.transactions}) {
    dismissible = true;
  }

  final CustomerSnapshot customer;
  final List<Transaction> transactions;
}

class ConfirmRow {
  const ConfirmRow(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;
}

/// 확인 모달. 사용자가 버튼을 눌러야만 완료된다.
class ConfirmRequest {
  ConfirmRequest({
    required this.title,
    this.body,
    this.rows = const [],
    this.fineprint,
    this.confirmText = '확인',
    this.cancelText = '취소',
  });

  final String title;
  final String? body;
  final List<ConfirmRow> rows;
  final String? fineprint;
  final String confirmText;
  final String cancelText;
  final Completer<bool> completer = Completer<bool>();

  void resolve(bool value) {
    if (!completer.isCompleted) completer.complete(value);
  }
}

/// OTP 등록·고객확인 처리 중 단계 표시
class ProgressAnim extends ChangeNotifier {
  ProgressAnim({required this.total, required this.sleep, int tickMs = 280}) {
    _timer = Timer.periodic(Duration(milliseconds: tickMs), (_) {
      if (done < total - 1) {
        done++;
        notifyListeners();
      }
    });
  }

  final int total;
  final Future<void> Function(int ms) sleep;
  late final Timer _timer;
  int done = 0;

  Future<void> finish(bool success) async {
    _timer.cancel();
    if (!success) return;
    while (done < total) {
      done++;
      notifyListeners();
      await sleep(150);
    }
    await sleep(250);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
