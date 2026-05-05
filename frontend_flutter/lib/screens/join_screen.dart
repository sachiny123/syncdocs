import 'package:flutter/material.dart';
import '../services/auth_session.dart';
import '../services/api_service.dart';
import 'document_screen.dart';
import 'login_screen.dart';

/// JoinScreen is shown when a user navigates to a shared document link.
/// It verifies the document exists and opens it directly in the editor.
class JoinScreen extends StatefulWidget {
  final String documentId;

  const JoinScreen({super.key, required this.documentId});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tryJoin();
  }

  Future<void> _tryJoin() async {
    if (!AuthSession.isLoggedIn) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final api = ApiService(token: AuthSession.token);
    final doc = await api.getDocument(widget.documentId);
    if (!mounted) return;

    if (doc == null) {
      setState(() {
        _loading = false;
        _error = 'Document not found or you do not have access.';
      });
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentScreen(
          documentId: widget.documentId,
          documentTitle: doc['title'] as String? ?? 'Untitled Document',
          username: AuthSession.username ?? 'Anonymous',
          token: AuthSession.token ?? '',
          isOwner: doc['owner'] == AuthSession.username,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Center(
        child: _loading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF6C63FF)),
                  const SizedBox(height: 20),
                  Text(
                    'Joining document…',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6), fontSize: 15),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _error ?? 'Something went wrong',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
      ),
    );
  }
}
