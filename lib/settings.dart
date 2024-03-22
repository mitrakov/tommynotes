// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  Settings._();
  static final Settings instance = Settings._();
  static SharedPreferences? _preferences;

  SharedPreferences get settings {
    if (_preferences != null) return _preferences!;
    else throw Exception("Settings are not initialized. Call Settings.instance.init() first.");
  }

  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
  }
}
