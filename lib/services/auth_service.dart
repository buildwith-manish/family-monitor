import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole {
  parent,
  child,
  unknown,
}

class AuthService {

  static final AuthService
      _instance =
      AuthService._internal();

  factory AuthService() =>
      _instance;

  AuthService._internal();

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  final DatabaseReference _db =
      FirebaseDatabase.instance.ref();

  User? get currentUser =>
      _auth.currentUser;

  bool get isLoggedIn =>
      _auth.currentUser != null;

  Stream<User?> get
      authStateChanges =>
          _auth.authStateChanges();

  // ─────────────────────────────
  // Parent Register
  // ─────────────────────────────

  Future<Map<String, dynamic>>
      registerParent({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {

      final UserCredential cred =
          await _auth
              .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        return {
          'success': false,
          'error': 'Registration failed. Please try again.',
        };
      }

      await user.updateDisplayName(displayName);

      await _db
          .child('users/${user.uid}')
          .set({
        'role': 'parent',
        'displayName': displayName,
        'email': email,
        'createdAt': ServerValue.timestamp,
        'children': {},
      });

      await _saveLocalRole('parent');

      return {
        'success': true,
        'user': user,
      };

    } on FirebaseAuthException
    catch (e) {
      debugPrint('[AuthService] registerParent FirebaseAuthException — '
          'code: ${e.code}, message: ${e.message}');
      return {
        'success': false,
        'error': _authErrorMessage(e.code, e.message),
      };
    } catch (e, st) {
      debugPrint('[AuthService] registerParent unexpected error: $e');
      debugPrintStack(stackTrace: st);
      return {
        'success': false,
        'error': 'Registration failed: ${e.toString()}',
      };
    }
  }

  // ─────────────────────────────
  // Parent Login
  // ─────────────────────────────

  Future<Map<String, dynamic>>
      loginParent({
    required String email,
    required String password,
  }) async {
    try {

      final UserCredential cred =
          await _auth
              .signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        return {
          'success': false,
          'error': 'Login failed. Please try again.',
        };
      }

      final DatabaseEvent snap =
          await _db
              .child('users/${user.uid}/role')
              .once();

      if (snap.snapshot.value != 'parent') {
        await _auth.signOut();
        return {
          'success': false,
          'error': 'This account is not a parent account.',
        };
      }

      await _saveLocalRole('parent');

      return {
        'success': true,
        'user': user,
      };

    } on FirebaseAuthException
    catch (e) {
      debugPrint('[AuthService] loginParent FirebaseAuthException — '
          'code: ${e.code}, message: ${e.message}');
      return {
        'success': false,
        'error': _authErrorMessage(e.code, e.message),
      };
    } catch (e, st) {
      debugPrint('[AuthService] loginParent unexpected error: $e');
      debugPrintStack(stackTrace: st);
      return {
        'success': false,
        'error': 'Login failed: ${e.toString()}',
      };
    }
  }

  // ─────────────────────────────
  // Child Setup
  // ─────────────────────────────

  Future<Map<String, dynamic>>
      setupChildDevice({
    required String childName,
    required String deviceName,
  }) async {
    try {

      final UserCredential cred =
          await _auth.signInAnonymously();

      final user = cred.user;
      if (user == null) {
        return {
          'success': false,
          'error': 'Setup failed. Please try again.',
        };
      }

      await _db
          .child('users/${user.uid}')
          .set({
        'role': 'child',
        'childName': childName,
        'deviceName': deviceName,
        'createdAt': ServerValue.timestamp,
        'isOnline': false,
        'pendingParentRequests': {},
        'approvedParents': {},
      });

      await _saveLocalRole('child');

      return {
        'success': true,
        'uid': user.uid,
      };

    } catch (e, st) {
      debugPrint('[AuthService] setupChildDevice error: $e');
      debugPrintStack(stackTrace: st);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ─────────────────────────────
  // Parent Request
  // ─────────────────────────────

  Future<Map<String, dynamic>>
      sendParentRequest(
    String childUid,
  ) async {
    try {

      final String? parentUid = currentUser?.uid;
      if (parentUid == null) {
        return {
          'success': false,
          'error': 'Not authenticated.',
        };
      }

      final DatabaseEvent parentSnap =
          await _db.child('users/$parentUid').once();

      final Object? rawParent = parentSnap.snapshot.value;
      if (rawParent == null || rawParent is! Map) {
        return {
          'success': false,
          'error': 'Parent profile not found.',
        };
      }

      final Map<String, dynamic> parentData =
          Map<String, dynamic>.from(rawParent);

      await _db
          .child('users/$childUid/pendingParentRequests/$parentUid')
          .set({
        'parentName':  parentData['displayName'],
        'parentEmail': parentData['email'],
        'requestedAt': ServerValue.timestamp,
        'status':      'pending',
      });

      return {'success': true};

    } catch (e, st) {
      debugPrint('[AuthService] sendParentRequest error: $e');
      debugPrintStack(stackTrace: st);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ─────────────────────────────
  // Approve Parent
  // ─────────────────────────────

  Future<Map<String, dynamic>>
      approveParentRequest(
    String parentUid,
  ) async {
    try {

      final String? childUid = currentUser?.uid;
      if (childUid == null) {
        return {
          'success': false,
          'error': 'Not authenticated.',
        };
      }

      final DatabaseEvent childSnap =
          await _db.child('users/$childUid').once();

      final Object? rawChild = childSnap.snapshot.value;
      if (rawChild == null || rawChild is! Map) {
        return {
          'success': false,
          'error': 'Child profile not found.',
        };
      }

      final Map<String, dynamic> childData =
          Map<String, dynamic>.from(rawChild);

      final pendingRequests = childData['pendingParentRequests'];
      final pendingEntry = (pendingRequests is Map && pendingRequests[parentUid] is Map)
          ? Map<String, dynamic>.from(pendingRequests[parentUid] as Map)
          : <String, dynamic>{};
      final parentName  = pendingEntry['parentName']  as String? ?? '';
      final parentEmail = pendingEntry['parentEmail'] as String? ?? '';

      await _db.update({
        'users/$childUid/pendingParentRequests/$parentUid/status': 'approved',
        'users/$childUid/approvedParents/$parentUid': true,
        'users/$childUid/connectedParent': {
          'uid':         parentUid,
          'parentName':  parentName,
          'parentEmail': parentEmail,
        },
        'users/$parentUid/children/$childUid': {
          'childName':  childData['childName'],
          'deviceName': childData['deviceName'],
          'approvedAt': ServerValue.timestamp,
          'isOnline':   false,
        },
      });

      return {'success': true};

    } catch (e, st) {
      debugPrint('[AuthService] approveParentRequest error: $e');
      debugPrintStack(stackTrace: st);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ─────────────────────────────
  // Remove Connected Child
  // ─────────────────────────────

  Future<void> removeChild(String childUid) async {
    final String? parentUid = currentUser?.uid;
    if (parentUid == null) return;

    await Future.wait([
      _db.child('users/$parentUid/children/$childUid').remove(),
      _db.child('users/$childUid/approvedParents/$parentUid').remove(),
    ]);
  }

  // ─────────────────────────────
  // Decline Parent
  // ─────────────────────────────

  Future<void> declineParentRequest(
    String parentUid,
  ) async {
    final String? childUid = currentUser?.uid;
    if (childUid == null) return;

    await _db
        .child('users/$childUid/pendingParentRequests/$parentUid')
        .remove();
  }

  // ─────────────────────────────
  // Streams
  // ─────────────────────────────

  Stream<DatabaseEvent> getChildrenStream() {
    final uid = currentUser?.uid;
    if (uid == null) {
      return Stream.error(Exception('Not authenticated'));
    }
    return _db.child('users/$uid/children').onValue;
  }

  Stream<DatabaseEvent> getPendingRequestsStream() {
    final uid = currentUser?.uid;
    if (uid == null) {
      return Stream.error(Exception('Not authenticated'));
    }
    return _db.child('users/$uid/pendingParentRequests').onValue;
  }

  // ─────────────────────────────
  // Online Status
  // ─────────────────────────────

  Future<void> setChildOnlineStatus(
    bool isOnline,
  ) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    await _db.child('users/$uid/isOnline').set(isOnline);
    await _db.child('users/$uid/lastSeen').set(ServerValue.timestamp);
  }

  // ─────────────────────────────
  // Saved Role
  // ─────────────────────────────

  Future<UserRole> getSavedRole() async {

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? role = prefs.getString('user_role');

    if (role == 'parent') return UserRole.parent;
    if (role == 'child')  return UserRole.child;
    return UserRole.unknown;
  }

  Future<void> _saveLocalRole(String role) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    await prefs.remove('user_role');
  }

  /// Re-authenticates the current user with email + password.
  /// Throws FirebaseAuthException if the password is wrong.
  Future<void> reauthenticate(String email, String password) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
  }

  // ─────────────────────────────
  // Child Auth
  // ─────────────────────────────

  Future<Map<String, dynamic>> signUpChild(
    String email,
    String password,
    String childName,
  ) async {
    try {

      final UserCredential cred =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        return {
          'success': false,
          'error': 'Registration failed. Please try again.',
        };
      }

      await _db.child('users/${user.uid}').set({
        'role':     'child',
        'email':    email,
        'childName': childName,
        'createdAt': ServerValue.timestamp,
        'isOnline':  false,
        'pendingParentRequests': {},
        'approvedParents': {},
      });

      await _saveLocalRole('child');

      return {
        'success': true,
        'uid': user.uid,
      };

    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] signUpChild FirebaseAuthException — '
          'code: ${e.code}, message: ${e.message}');
      return {
        'success': false,
        'error': _authErrorMessage(e.code, e.message),
      };

    } catch (e, st) {
      debugPrint('[AuthService] signUpChild unexpected error: $e');
      debugPrintStack(stackTrace: st);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> signInChild(
    String email,
    String password,
  ) async {
    try {

      final UserCredential cred =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        return {
          'success': false,
          'error': 'Login failed. Please try again.',
        };
      }

      await _saveLocalRole('child');

      return {
        'success': true,
        'uid': user.uid,
      };

    } on FirebaseAuthException catch (e) {
      // Always log the real Firebase error code so production auth failures
      // are diagnosable from device logs / Crashlytics without reproducing.
      debugPrint('[AuthService] signInChild FirebaseAuthException — '
          'code: ${e.code}, message: ${e.message}');
      return {
        'success': false,
        'error': _authErrorMessage(e.code, e.message),
      };

    } catch (e, st) {
      debugPrint('[AuthService] signInChild unexpected error: $e');
      debugPrintStack(stackTrace: st);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ─────────────────────────────
  // Password Reset
  // ─────────────────────────────

  Future<Map<String, dynamic>> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return {'success': true};
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] sendPasswordResetEmail FirebaseAuthException — '
          'code: ${e.code}, message: ${e.message}');
      return {
        'success': false,
        'error': _authErrorMessage(e.code, e.message),
      };
    }
  }

  // ─────────────────────────────
  // Change Password
  // ─────────────────────────────

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        return {
          'success': false,
          'error': 'You must be signed in to change your password.',
        };
      }

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      return {'success': true};
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] changePassword FirebaseAuthException — '
          'code: ${e.code}, message: ${e.message}');
      return {
        'success': false,
        'error': _authErrorMessage(e.code, e.message),
      };
    }
  }

  // ─────────────────────────────
  // Error Messages
  // ─────────────────────────────

  /// Maps a [FirebaseAuthException] code to a human-readable message.
  ///
  /// [message] is the raw Firebase message — used as a fallback for unknown
  /// codes so the UI always shows something meaningful instead of the generic
  /// "Authentication failed" when a new error code is introduced by Firebase.
  String _authErrorMessage(String code, [String? message]) {
    switch (code) {
      // ── Registration errors ─────────────────────────────────────────────
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';

      // ── Login errors ────────────────────────────────────────────────────
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      // Firebase Auth v2 consolidates user-not-found + wrong-password into
      // invalid-credential when Email Enumeration Protection is enabled.
      case 'invalid-credential':
        return 'Incorrect email or password.';

      // ── Account state errors ────────────────────────────────────────────
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'requires-recent-login':
        return 'Session expired. Please sign out and sign in again.';

      // ── Configuration / network errors ─────────────────────────────────
      // These fire when Firebase is misconfigured or the device has no network.
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';
      case 'app-not-authorized':
        // SHA fingerprint not registered in Firebase Console for this package.
        return 'App configuration error. Please contact support. (app-not-authorized)';
      case 'invalid-api-key':
      case 'api-key-not-valid':
        return 'App configuration error. Please contact support. (invalid-api-key)';
      case 'operation-not-allowed':
        // Email/password provider not enabled in Firebase Console.
        return 'Email sign-in is not enabled for this app. Please contact support.';
      case 'project-not-found':
        return 'Firebase project not found. Please contact support.';
      case 'channel-error':
        // Native platform channel failure — usually indicates Firebase SDK
        // was not initialised before the auth call.
        return 'App startup error. Please restart the app. (channel-error)';

      // ── Fallback: show the raw Firebase message if available ────────────
      default:
        if (message != null && message.isNotEmpty) {
          // Include the code in debug builds so support teams can identify
          // new unhandled codes from crash reports / user screenshots.
          assert(() {
            debugPrint(
                '[AuthService] Unhandled FirebaseAuthException code: $code');
            return true;
          }());
          return message;
        }
        return 'Authentication error ($code). Please try again.';
    }
  }
}
