import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinService {
  static const String _prefKey = 'uninstall_pin';

  static Future<void> savePin(String uid, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, pin);
    try {
      await FirebaseDatabase.instance
          .ref('users/$uid/uninstallPin')
          .set(pin);
    } catch (_) {}
  }

  static Future<String?> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await getPin();
    return stored != null && stored == pin;
  }

  static Future<bool> hasPin() async {
    final pin = await getPin();
    return pin != null && pin.length == 4;
  }

  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
