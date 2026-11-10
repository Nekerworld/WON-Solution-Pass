import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/bank_state.dart';
import '../domain/event_log.dart';
import 'key_value_storage.dart';

/// 중앙 상태 저장소: 모든 화면/모듈이 같은 저장소를 참조한다.
/// 모든 값은 시연용 가상 데이터이며 실제 은행 시스템/정책과 무관하다.
class BankStore extends ChangeNotifier {
  BankStore({required this.events, this.storage, this.storageKey = 'wsp.bankState.v1'}) {
    _state = _load() ?? BankState.initial();
  }

  final EventLog events;
  final KeyValueStorage? storage;
  final String storageKey;
  late BankState _state;
  bool _silent = false;

  BankState? _load() {
    final raw = storage?.read(storageKey);
    if (raw == null) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map || parsed['system'] is! Map || parsed['system']['stateVersion'] is! num) return null;
      return BankState.fromJson(parsed.cast());
    } catch (_) {
      return null;
    }
  }

  void _persist() {
    try {
      storage?.write(storageKey, jsonEncode(_state.toJson()));
    } catch (_) {
      // 저장 실패는 시연에 영향 없음
    }
  }

  void _emit() {
    if (!_silent) notifyListeners();
  }

  /// 항상 깊은 복사본을 반환하여 외부에서 직접 변경하지 못하게 한다.
  BankState get state => _state.clone();

  /// 모든 상태 변경은 이 함수를 거치며 stateVersion이 1 증가한다.
  BankState update(void Function(BankState draft) mutator, [String? reason]) {
    final draft = _state.clone();
    mutator(draft);
    draft.system.stateVersion = _state.system.stateVersion + 1;
    _state = draft;
    _persist();
    events.add('STORE', reason ?? '상태 변경', {'stateVersion': _state.system.stateVersion});
    _emit();
    return _state.clone();
  }

  BankState reset([String? reason]) {
    _state = BankState.initial();
    _persist();
    events.add('STORE', reason ?? '데모 초기화', {'stateVersion': _state.system.stateVersion});
    _emit();
    return _state.clone();
  }

  void replace(BankState snapshot, [String? reason]) {
    _state = snapshot.clone();
    _persist();
    if (reason != null) events.add('STORE', reason, {'stateVersion': _state.system.stateVersion});
    _emit();
  }

  set silent(bool value) => _silent = value;
}
