# Fix 1: background_monitoring_service.dart
with open('lib/services/background_monitoring_service.dart', 'r') as f:
    content = f.read()

content = content.replace(
    'DartPluginRegistrant.ensureInitialized();\n  await Firebase.initializeApp();',
    '''DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4",
        authDomain: "family-monitor-7aab3.firebaseapp.com",
        databaseURL: "https://family-monitor-7aab3-default-rtdb.firebaseio.com",
        projectId: "family-monitor-7aab3",
        storageBucket: "family-monitor-7aab3.firebasestorage.app",
        messagingSenderId: "758644747673",
        appId: "1:758644747673:android:69ef23a2fa4b508122f708",
      ),
    );
  }'''
)

with open('lib/services/background_monitoring_service.dart', 'w') as f:
    f.write(content)
print("✅ Fixed background_monitoring_service.dart")

# Fix 2: main_child.dart
with open('lib/main_child.dart', 'r') as f:
    content = f.read()

content = content.replace(
    'Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {\n  await Firebase.initializeApp(options: const FirebaseOptions(\n    apiKey: "AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4",\n    authDomain: "family-monitor-7aab3.firebaseapp.com",\n    databaseURL: "https://family-monitor-7aab3-default-rtdb.firebaseio.com",\n    projectId: "family-monitor-7aab3",\n    storageBucket: "family-monitor-7aab3.firebasestorage.app",\n    messagingSenderId: "758644747673",\n    appId: "1:758644747673:android:69ef23a2fa4b508122f708",\n  ));',
    '''Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: const FirebaseOptions(
      apiKey: "AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4",
      authDomain: "family-monitor-7aab3.firebaseapp.com",
      databaseURL: "https://family-monitor-7aab3-default-rtdb.firebaseio.com",
      projectId: "family-monitor-7aab3",
      storageBucket: "family-monitor-7aab3.firebasestorage.app",
      messagingSenderId: "758644747673",
      appId: "1:758644747673:android:69ef23a2fa4b508122f708",
    ));
  }'''
)

with open('lib/main_child.dart', 'w') as f:
    f.write(content)
print("✅ Fixed main_child.dart")

# Fix 3: auth_service.dart
with open('lib/services/auth_service.dart', 'r') as f:
    content = f.read()

content = content.replace(
    "case 'wrong-password':\n        return 'Incorrect password.';",
    "case 'wrong-password':\n        return 'Incorrect password.';\n      case 'invalid-credential':\n        return 'Incorrect email or password.';"
)

content = content.replace(
    "    } catch (e) { return {'success': false, 'error': e.toString()}; }\n  }\n\n  Future<Map<String, dynamic>> signInChild",
    "    } on FirebaseAuthException catch (e) {\n      return {'success': false, 'error': _authErrorMessage(e.code)};\n    } catch (e) { return {'success': false, 'error': e.toString()}; }\n  }\n\n  Future<Map<String, dynamic>> signInChild"
)

content = content.replace(
    "    } catch (e) { return {'success': false, 'error': e.toString()}; }\n  }\n}",
    "    } on FirebaseAuthException catch (e) {\n      return {'success': false, 'error': _authErrorMessage(e.code)};\n    } catch (e) { return {'success': false, 'error': e.toString()}; }\n  }\n}"
)

with open('lib/services/auth_service.dart', 'w') as f:
    f.write(content)
print("✅ Fixed auth_service.dart")

print("\n🎉 All 3 files fixed! Now run: flutter clean && flutter pub get && flutter build apk --target lib/main_child.dart --release")
