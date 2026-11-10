import 'package:flutter/foundation.dart';

class EventEntry {
  EventEntry({required this.at, required this.source, required this.message, this.meta});

  final DateTime at;
  final String source;
  final String message;
  final Map<String, Object?>? meta;
}

/// 해결패스 내부 이벤트 로그 (시연 제어 화면에서 관찰한다).
class EventLog extends ChangeNotifier {
  EventLog({this.max = 300});

  final int max;
  List<EventEntry> _items = [];

  EventEntry add(String source, String message, [Map<String, Object?>? meta]) {
    final entry = EventEntry(at: DateTime.now(), source: source, message: message, meta: meta);
    _items.add(entry);
    if (_items.length > max) _items = _items.sublist(_items.length - max);
    notifyListeners();
    return entry;
  }

  List<EventEntry> list() => List.unmodifiable(_items);

  void clear() {
    _items = [];
    notifyListeners();
  }
}
