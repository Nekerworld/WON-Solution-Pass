import 'package:shared_preferences/shared_preferences.dart';

/// 상태 저장소 추상화. 앱에서는 shared_preferences, 테스트에서는 메모리를 쓴다.
abstract class KeyValueStorage {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

class MemoryStorage implements KeyValueStorage {
  final Map<String, String> _data = {};

  @override
  String? read(String key) => _data[key];

  @override
  void write(String key, String value) => _data[key] = value;

  @override
  void remove(String key) => _data.remove(key);
}

class PrefsStorage implements KeyValueStorage {
  PrefsStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsStorage> open() async => PrefsStorage(await SharedPreferences.getInstance());

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  void write(String key, String value) {
    // 저장 실패는 시연에 영향 없음
    _prefs.setString(key, value).ignore();
  }

  @override
  void remove(String key) {
    _prefs.remove(key).ignore();
  }
}
