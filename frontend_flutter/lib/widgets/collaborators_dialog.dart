import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CollaboratorsDialog extends StatefulWidget {
  final Map<String, dynamic> doc;
  final ApiService api;

  const CollaboratorsDialog({super.key, required this.doc, required this.api});

  @override
  State<CollaboratorsDialog> createState() => _CollaboratorsDialogState();
}

class _CollaboratorsDialogState extends State<CollaboratorsDialog> {
  final _searchCtrl = TextEditingController();
  List<String> _collaborators = [];
  List<String> _searchResults = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCollaborators();
  }

  Future<void> _loadCollaborators() async {
    try {
      final data =
          await widget.api.listCollaborators(widget.doc['document_id']);
      setState(() {
        _collaborators = List<String>.from(data['collaborators'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    try {
      final results = await widget.api.searchUsers(q);
      setState(() {
        _searchResults = results.map((u) => u['username'] as String).toList();
      });
    } catch (_) {}
  }

  Future<void> _add(String username) async {
    try {
      await widget.api.addCollaborator(widget.doc['document_id'], username);
      _searchCtrl.clear();
      _searchResults = [];
      _loadCollaborators();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _remove(String username) async {
    try {
      final ok = await widget.api
          .removeCollaborator(widget.doc['document_id'], username);
      if (ok) _loadCollaborators();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1D2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Manage Collaborators',
          style: TextStyle(color: Colors.white, fontSize: 18)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Search username...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: const Color(0xFF21253A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, i) {
                    final u = _searchResults[i];
                    if (_collaborators.contains(u)) return const SizedBox();
                    return ListTile(
                      title: Text(u,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      trailing: const Icon(Icons.add,
                          color: Color(0xFF6C63FF), size: 20),
                      onTap: () => _add(u),
                    );
                  },
                ),
              ),
            const SizedBox(height: 20),
            const Text('Current Collaborators',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
            else if (_collaborators.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No collaborators added yet.',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 13)),
              )
            else
              ..._collaborators.map((u) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(0xFF6C63FF),
                        child: Icon(Icons.person, color: Colors.white, size: 16)),
                    title: Text(u,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.redAccent, size: 18),
                      onPressed: () => _remove(u),
                    ),
                  )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Color(0xFF6C63FF))),
        ),
      ],
    );
  }
}
