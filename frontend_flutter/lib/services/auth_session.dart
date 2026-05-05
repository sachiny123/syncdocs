/// Simple in-memory session store (no persistence needed for this demo).
/// In production, use shared_preferences or secure_storage.
class AuthSession {
  static String? username;
  static String? token;

  static bool get isLoggedIn => token != null && token!.isNotEmpty;

  static void setUser({required String u, required String t}) {
    username = u;
    token = t;
  }

  static void clear() {
    username = null;
    token = null;
  }
}
