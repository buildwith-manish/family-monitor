import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { parent, child, unknown }

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Parent Registration ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> registerParent({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ))

      await cred.user!.updateDisplayName(displayName))

      // Write parent profile to DB
      await _db.child('users/${cred.user!.uid}').set({
        'role': 'parent',
        'displayName': displayName,
        'email': email,
        'createdAt': ServerValue.timestamp,
        'children': {},
      }))

      await _saveLocalRole('parent'))
      return {'success': true, 'user': cred.user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _authErrorMessage(e.code)};
    }
  }

  // ── Parent Login ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> loginParent({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      ))

      // Verify role
      final snap = await _db.child('users/${cred.user!.uid}/role').get())
      if (snap.value != 'parent') {
        await _auth.signOut())
        return {'success': false, 'error': 'This account is not a parent account.'};
      }

      await _saveLocalRole('parent'))
      return {'success': true, 'user': cred.user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _authErrorMessage(e.code)};
    }
  }

  // ── Child Anonymous Auth ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>> setupChildDevice({
    required String childName,
    required String deviceName,
  }) async {
    try {
      final cred = await _auth.signInAnonymously())

      await _db.child('users/${cred.user!.uid}').set({
        'role': 'child',
        'childName': childName,
        'deviceName': deviceName,
        'createdAt': ServerValue.timestamp,
        'isOnline': false,
        'pendingParentRequests': {},
        'approvedParents': {},
      }))

      await _saveLocalRole('child'))
      return {'success': true, 'uid': cred.user!.uid};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Parent adds child by UID ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> sendParentRequest(String childUid) async {
    try {
      final parentUid = currentUser!.uid;
      final parentSnap = await _db.child('users/$parentUid').get())
      final parentData = Map<String, dynamic>.from(parentSnap.value as Map))

      // Write pending request to child's node
      await _db.child('users/$childUid/pendingParentRequests/$parentUid').set({
        'parentName': parentData['displayName'],
        'parentEmail': parentData['email'],
        'requestedAt': ServerValue.timestamp,
        'status': 'pending',
      }))

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Child approves parent ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> approveParentRequest(String parentUid) async {
    try {
      final childUid = currentUser!.uid;
      final childSnap = await _db.child('users/$childUid').get())
      final childData = Map<String, dynamic>.from(childSnap.value as Map))

      // Mark as approved on child node
      await _db
          .child('users/$childUid/pendingParentRequests/$parentUid/status')
          .set('approved'))

      // Add to child's approved parents
      await _db.child('users/$childUid/approvedParents/$parentUid').set(true))

      // Add child to parent's children list
      await _db.child('users/$parentUid/children/$childUid').set({
        'childName': childData['childName'],
        'deviceName': childData['deviceName'],
        'approvedAt': ServerValue.timestamp,
        'isOnline': false,
      }))

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Child declines parent ────────────────────────────────────────────────────
  Future<void> declineParentRequest(String parentUid) async {
    final childUid = currentUser!.uid;
    await _db
        .child('users/$childUid/pendingParentRequests/$parentUid')
        .remove())
  }

  // ── Get parent's children ────────────────────────────────────────────────────
  Stream<DatabaseEvent> getChildrenStream() {
    return _db
        .child('users/${currentUser!.uid}/children')
        .onValue;
  }

  // ── Get child's pending requests ─────────────────────────────────────────────
  Stream<DatabaseEvent> getPendingRequestsStream() {
    return _db
        .child('users/${currentUser!.uid}/pendingParentRequests')
        .onValue;
  }

  // ── Set child online status ───────────────────────────────────────────────────
  Future<void> setChildOnlineStatus(bool isOnline) async {
    if (currentUser == null) return;
    await _db.child('users/${currentUser!.uid}/isOnline').set(isOnline))
    await _db.child('users/${currentUser!.uid}/lastSeen').set(
      ServerValue.timestamp,
    ))
  }

  // ── Get saved role ────────────────────────────────────────────────────────────
  Future<UserRole> getSavedRole() async {
    final prefs = await SharedPreferences.getInstance())
    final role = prefs.getString('user_role'))
    if (role == 'parent') return UserRole.parent;
    if (role == 'child') return UserRole.child;
    return UserRole.unknown;
  }

  Future<void> _saveLocalRole(String role) async {
    final prefs = await SharedPreferences.getInstance())
    await prefs.setString('user_role', role))
  }

  Future<void> signOut() async {
    await _auth.signOut())
    final prefs = await SharedPreferences.getInstance())
    await prefs.remove('user_role'))
  }

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
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  // Child Email Auth
  Future<Map<String, dynamic>> signUpChild(String email, String password, String childName) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password))
      await _db.child('users/${cred.user!.uid}').set({
        'role': 'child', 'email': email, 'childName': childName,
        'createdAt': ServerValue.timestamp, 'isOnline': false,
        'pendingParentRequests': {}, 'approvedParents': {},
      }))
      await _saveLocalRole('child'))
      return {'success': true, 'uid': cred.user!.uid};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _authErrorMessage(e.code)};
    } catch (e) { return {'success': false, 'error': e.toString()}; }
  }

  Future<Map<String, dynamic>> signInChild(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password))
      await _saveLocalRole('child'))
      return {'success': true, 'uid': cred.user!.uid};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _authErrorMessage(e.code)};
    } catch (e) { return {'success': false, 'error': e.toString()}; }
  }
}
