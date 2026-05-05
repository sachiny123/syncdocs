import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
import 'document_screen.dart';
import 'login_screen.dart';
import '../widgets/collaborators_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  late ApiService _api;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _api = ApiService(token: AuthSession.token);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadDocs();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocs() async {
    setState(() => _loading = true);
    try {
      final docs = await _api.listDocuments();
      setState(() => _docs = docs);
      _fadeCtrl.forward(from: 0);
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _createDoc() async {
    try {
      final doc = await _api.createDocument();
      if (!mounted) return;
      _openDoc(doc);
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  void _openDoc(Map<String, dynamic> doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentScreen(
          documentId: doc['document_id'] as String,
          documentTitle: doc['title'] as String? ?? 'Untitled Document',
          username: AuthSession.username ?? 'Anonymous',
          token: AuthSession.token ?? '',
          isOwner: doc['owner'] == AuthSession.username,
        ),
      ),
    ).then((_) => _loadDocs());
  }

  Future<void> _renameDoc(Map<String, dynamic> doc) async {
    final ctrl = TextEditingController(
        text: doc['title'] as String? ?? 'Untitled Document');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(controller: ctrl),
    );
    if (result == null || result.isEmpty) return;
    final ok = await _api.renameDocument(doc['document_id'] as String, result);
    if (ok) {
      _loadDocs();
    } else {
      _showSnack('Rename failed', isError: true);
    }
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Document',
            style: TextStyle(color: Colors.white)),
        content: Text(
            'Are you sure you want to delete "${doc['title']}"? This cannot be undone.',
            style: TextStyle(color: Colors.white.withOpacity(0.6))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6C63FF))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok =
        await _api.deleteDocument(doc['document_id'] as String);
    if (ok) {
      _loadDocs();
    } else {
      _showSnack('Delete failed', isError: true);
    }
  }

  void _manageCollaborators(Map<String, dynamic> doc) {
    showDialog(
      context: context,
      builder: (ctx) => CollaboratorsDialog(doc: doc, api: _api),
    ).then((_) => _loadDocs());
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.redAccent : const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _logout() {
    AuthSession.clear();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF48C6EF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.edit_document,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'Colab Docs',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF6C63FF).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline,
                          color: Color(0xFF6C63FF), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        AuthSession.username ?? '',
                        style: const TextStyle(
                            color: Color(0xFF6C63FF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.logout_outlined,
                      color: Colors.white54, size: 20),
                  tooltip: 'Sign out',
                  onPressed: _logout,
                ),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Documents',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_docs.length} document${_docs.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _createDoc,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Document',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    elevation: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // Docs grid / list
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF6C63FF)))
                  : _docs.isEmpty
                      ? _buildEmpty()
                      : FadeTransition(
                          opacity: _fadeAnim,
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 320,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1.4,
                            ),
                            itemCount: _docs.length,
                            itemBuilder: (_, i) => _DocCard(
                              doc: _docs[i],
                              onOpen: () => _openDoc(_docs[i]),
                              onRename: () => _renameDoc(_docs[i]),
                              onDelete: () => _deleteDoc(_docs[i]),
                              onManageCollaborators: () =>
                                  _manageCollaborators(_docs[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.description_outlined,
                color: Color(0xFF6C63FF), size: 36),
          ),
          const SizedBox(height: 20),
          const Text('No documents yet',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Create your first document to get started',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 14)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _createDoc,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create Document',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Doc Card ──────────────────────────────────────────────────────────────────

class _DocCard extends StatefulWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onManageCollaborators;

  const _DocCard({
    required this.doc,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onManageCollaborators,
  });

  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard> {
  bool _hovered = false;

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.doc['title'] as String?)?.isNotEmpty == true
        ? widget.doc['title'] as String
        : 'Untitled Document';
    final lastUpdated = _formatDate(widget.doc['last_updated']);
    final isOwner = widget.doc['owner'] == AuthSession.username;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF21253A) : const Color(0xFF1A1D2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? const Color(0xFF6C63FF).withOpacity(0.5)
                : Colors.white.withOpacity(0.07),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ]
              : [],
        ),
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF48C6EF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.description,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 8),
                    if (!isOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'SHARED',
                          style: TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          color: Colors.white.withOpacity(0.4), size: 20),
                      color: const Color(0xFF21253A),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            widget.onOpen();
                            break;
                          case 'rename':
                            widget.onRename();
                            break;
                          case 'collaborators':
                            widget.onManageCollaborators();
                            break;
                          case 'delete':
                            widget.onDelete();
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        _menuItem('edit', Icons.edit_outlined, 'Edit'),
                        if (isOwner)
                          _menuItem('rename', Icons.drive_file_rename_outline,
                              'Rename'),
                        if (isOwner)
                          _menuItem('collaborators', Icons.people_outline,
                              'Manage Collaborators'),
                        if (isOwner) const PopupMenuDivider(),
                        if (isOwner)
                          _menuItem('delete', Icons.delete_outline, 'Delete',
                              color: Colors.redAccent),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time_outlined,
                        size: 12, color: Colors.white.withOpacity(0.3)),
                    const SizedBox(width: 4),
                    Text(
                      lastUpdated,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.35), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color? color}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? Colors.white.withOpacity(0.7)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: color ?? Colors.white.withOpacity(0.85),
                  fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Rename Dialog ──────────────────────────────────────────────────────────────

class _RenameDialog extends StatelessWidget {
  final TextEditingController controller;

  const _RenameDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1D2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Rename Document',
          style: TextStyle(color: Colors.white, fontSize: 18)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: InputDecoration(
          hintText: 'Document title',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF6C63FF)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
