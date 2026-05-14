import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
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

      return {
        'success': false,
        'error': _authErrorMessage(e.code),
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

      return {
        'success': false,
        'error': _authErrorMessage(e.code),
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

    } catch (e) {

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

    } catch (e) {

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

      // Single atomic multi-path update — if the app is killed between
      // any of these writes, the partial state is avoided. Firebase RTDB
      // applies all keys in one operation or rolls back on network failure.
      await _db.update({
        'users/$childUid/pendingParentRequests/$parentUid/status': 'approved',
        'users/$childUid/approvedParents/$parentUid': true,
        'users/$parentUid/children/$childUid': {
          'childName':  childData['childName'],
          'deviceName': childData['deviceName'],
          'approvedAt': ServerValue.timestamp,
          'isOnline':   false,
        },
      });

      return {'success': true};

    } catch (e) {

      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ─────────────────────────────
  // Remove Connected Child
  // ─────────────────────────────

  /// Disconnects [childUid] from the current parent account.
  /// Removes the child from the parent's children list and revokes the
  /// parent's approval entry on the child's profile.
  Future<void> removeChild(String childUid) async {
    final String? parentUid = currentUser?.uid;
    if (parentUid == null) return;

    await Future.wait([
      // Remove child from parent's list
      _db.child('users/$parentUid/children/$childUid').remove(),
      // Revoke approval so the child device no longer reports to this parent
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
      // Return a stream that immediately errors rather than crashing.
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

      return {
        'success': false,
        'error': _authErrorMessage(e.code),
      };

    } catch (e) {

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

      return {
        'success': false,
        'error': _authErrorMessage(e.code),
      };

    } catch (e) {

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
      return {
        'success': false,
        'error': _authErrorMessage(e.code),
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
      return {
        'success': false,
        'error': _authErrorMessage(e.code),
      };
    }
  }

  // ─────────────────────────────
  // Error Messages
  // ─────────────────────────────

  String _authErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'requires-recent-login':
        return 'Session expired. Please sign out and sign in again.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
