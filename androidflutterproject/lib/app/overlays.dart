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

class DiagRow {
  DiagRow(this.key, this.label);

  final String key;
  final String label;
  String sub = '';

  /// null이면 조회 중(스피너)
  ({String text, UiTone tone})? badge;
}

class DiagSummary {
  const DiagSummary({required this.tone, required this.title, required this.body, required this.buttonLabel, this.codeLine});

  final UiTone tone;
  final String title;
  final String body;
  final String buttonLabel;
  final String? codeLine;
}

/// 자동 진단 시트: 6개 항목을 순서대로 조회해 표시하고, 요약 버튼을 눌러야 다음으로 진행한다.
class DiagnosisSheetState extends SheetState {
  DiagnosisSheetState({required this.isFailure});

  final bool isFailure;
  final List<DiagRow> rows = [
    DiagRow('request', '이체 요청 정보'),
    DiagRow('limit', '1일 이체한도'),
    DiagRow('otp', '디지털 OTP'),
    DiagRow('kyc', '고객확인'),
    DiagRow('account', '계좌 이용 상태'),
    DiagRow('balance', '출금 가능 잔액'),
  ];
  DiagSummary? summary;

  void revealRow(String key, String sub, String text, UiTone tone) {
    final row = rows.firstWhere((r) => r.key == key);
    row.sub = sub;
    row.badge = (text: text, tone: tone);
    notifyListeners();
  }

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
