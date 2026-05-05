import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import '../services/document_service.dart';
import '../services/api_service.dart';
import '../widgets/collaborators_dialog.dart';

// ─── Dotted Grid Background ────────────────────────────────────────────────────

class _DottedGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1.0;
    const spacing = 24.0;
    for (double i = 0; i < size.width; i += spacing) {
      for (double j = 0; j < size.height; j += spacing) {
        canvas.drawCircle(Offset(i, j), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Colored Text Controller ───────────────────────────────────────────────────

class _ColoredTextController extends TextEditingController {
  List<Color> charColors = [];
  Color defaultColor = const Color(0xFFE8E8F0);
  final _dmp = DiffMatchPatch();
  String _lastText = '';

  void updateTextWithAuthor(String newText, Color authorColor) {
    if (newText == _lastText) return;
    final diffs = _dmp.diff(_lastText, newText);
    _dmp.diffCleanupSemantic(diffs);

    final List<Color> newColors = [];
    int oldIndex = 0;

    for (final diff in diffs) {
      final len = diff.text.length;
      if (diff.operation == DIFF_EQUAL) {
        for (int i = 0; i < len; i++) {
          newColors.add(oldIndex < charColors.length
              ? charColors[oldIndex]
              : const Color(0xFFE8E8F0));
          oldIndex++;
        }
      } else if (diff.operation == DIFF_DELETE) {
        oldIndex += len;
      } else if (diff.operation == DIFF_INSERT) {
        for (int i = 0; i < len; i++) {
          newColors.add(authorColor);
        }
      }
    }
    charColors = newColors;
    _lastText = newText;
  }

  void setRemoteText(String newText, Color authorColor) {
    updateTextWithAuthor(newText, authorColor);
    text = newText;
  }

  @override
  set value(TextEditingValue newValue) {
    if (newValue.text != _lastText) {
      updateTextWithAuthor(newValue.text, defaultColor);
    }
    super.value = newValue;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    if (text.isEmpty || charColors.length != text.length) {
      return TextSpan(style: style, text: text);
    }

    final List<TextSpan> spans = [];
    Color cur = charColors[0];
    int start = 0;

    for (int i = 1; i <= text.length; i++) {
      if (i == text.length || charColors[i] != cur) {
        spans.add(TextSpan(
          text: text.substring(start, i),
          style: (style ?? const TextStyle()).copyWith(color: cur),
        ));
        if (i < text.length) {
          cur = charColors[i];
          start = i;
        }
      }
    }
    return TextSpan(style: style, children: spans);
  }
}

// ─── Document Screen ───────────────────────────────────────────────────────────

class DocumentScreen extends StatefulWidget {
  final String documentId;
  final String documentTitle;
  final String username;
  final String token;
  final bool isOwner;

  const DocumentScreen({
    super.key,
    required this.documentId,
    required this.documentTitle,
    required this.username,
    required this.token,
    this.isOwner = false,
  });

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late DocumentService _documentService;
  late _ColoredTextController _textCtrl;
  late ApiService _api;

  List<Map<String, dynamic>> _activeUsers = [];
  Map<String, Map<String, dynamic>> _remoteCursors = {};
  String _docTitle = '';
  bool _isUpdatingFromRemote = false;
  bool _isSaving = false;
  Timer? _debounce;
  Timer? _titleDebounce;
  late TextEditingController _titleCtrl;

  // Assign a distinct color to this user based on their name hash
  late Color _myColor;

  static const List<Color> _palette = [
    Color(0xFF6C63FF),
    Color(0xFFFF6B6B),
    Color(0xFF48C6EF),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF00BCD4),
    Color(0xFF8BC34A),
  ];

  @override
  void initState() {
    super.initState();
    _docTitle = widget.documentTitle;
    _titleCtrl = TextEditingController(text: _docTitle);
    _api = ApiService(token: widget.token);

    // Pick a color from palette based on username hash
    final colorIndex = widget.username.hashCode.abs() % _palette.length;
    _myColor = _palette[colorIndex];

    _textCtrl = _ColoredTextController();
    _textCtrl.defaultColor = _myColor;
    _textCtrl.addListener(_onLocalCursorChange);

    final colorHex =
        '0x${_myColor.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

    _documentService = DocumentService(
      docId: widget.documentId,
      username: widget.username,
      color: colorHex,
      onContentUpdate: (content, {color}) {
        if (!mounted) return;
        setState(() {
          _isUpdatingFromRemote = true;
          Color authorColor = const Color(0xFFE8E8F0);
          if (color != null) {
            final parsed = int.tryParse(
                color.replaceFirst('0x', '').replaceFirst('0X', ''),
                radix: 16);
            if (parsed != null) authorColor = Color(parsed);
          }
          final sel = _textCtrl.selection;
          _textCtrl.setRemoteText(content, authorColor);
          if (sel.baseOffset >= 0 && sel.baseOffset <= content.length) {
            _textCtrl.selection = sel;
          } else {
            _textCtrl.selection =
                TextSelection.collapsed(offset: content.length);
          }
          _isUpdatingFromRemote = false;
        });
      },
      onPresenceUpdate: (users) {
        if (!mounted) return;
        setState(() {
          _activeUsers = users;
          final ids = users.map((u) => u['client_id']).toSet();
          _remoteCursors.removeWhere((id, _) => !ids.contains(id));
        });
      },
      onCursorUpdate: (data) {
        if (!mounted) return;
        setState(() => _remoteCursors[data['client_id']] = data);
      },
    );

    _documentService.connect();
  }

  void _onLocalCursorChange() {
    final pos = _textCtrl.selection.baseOffset;
    if (pos >= 0) _documentService.sendCursorUpdate(pos);
  }

  void _onTextChanged(String text) {
    if (_isUpdatingFromRemote) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), () {
      _documentService.sendUpdate(text);
    });
  }

  void _onTitleChanged(String title) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (title.trim().isEmpty) return;
      setState(() => _isSaving = true);
      await _api.renameDocument(widget.documentId, title.trim());
      if (mounted) setState(() => _isSaving = false);
    });
  }

  void _copyShareLink() {
    final link = 'colabdocs://join/${widget.documentId}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Share link copied: $link'),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleDebounce?.cancel();
    _textCtrl.removeListener(_onLocalCursorChange);
    _documentService.disconnect();
    _textCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Color _parseColor(dynamic raw) {
    if (raw == null) return const Color(0xFF6C63FF);
    final s = raw.toString().replaceAll('0x', '').replaceAll('0X', '');
    return Color(int.tryParse(s, radix: 16) ?? 0xFF6C63FF);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Dotted grid background
          Positioned.fill(
            child: CustomPaint(painter: _DottedGridPainter()),
          ),
          // Main content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Active users
                if (_activeUsers.isNotEmpty) _buildPresenceBar(),
                const SizedBox(height: 16),
                // Document editor
                Expanded(child: _buildEditor()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1D2E),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new,
            color: Colors.white70, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) {
                _docTitle = v;
                _onTitleChanged(v);
              },
              controller: _titleCtrl,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Untitled Document',
                hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.3)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_isSaving)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('Saving…',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 12)),
            ),
        ],
      ),
      actions: [
        // Collaborator count
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: Colors.greenAccent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                '${_activeUsers.length} online',
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        // Manage Collaborators button (only for owner)
        if (widget.isOwner)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.people_outline, color: Colors.white70),
              tooltip: 'Manage Collaborators',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => CollaboratorsDialog(
                    doc: {
                      'document_id': widget.documentId,
                      'title': widget.documentTitle,
                    },
                    api: _api,
                  ),
                );
              },
            ),
          ),
        // Share button (fallback)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ElevatedButton.icon(
            onPressed: _copyShareLink,
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Share',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF).withOpacity(0.2),
              foregroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: const Color(0xFF6C63FF).withOpacity(0.5))),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildPresenceBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _activeUsers.map((user) {
        final c = _parseColor(user['color']);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                user['username'] ?? 'User',
                style: TextStyle(
                    color: c,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEditor() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            TextField(
              controller: _textCtrl,
              maxLines: null,
              expands: true,
              cursorColor: _myColor,
              cursorWidth: 2,
              style: const TextStyle(
                fontSize: 16,
                height: 1.7,
                color: Color(0xFFE8E8F0),
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(28),
                hintText: 'Start typing to collaborate in real time…',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 15,
                    height: 1.7),
              ),
              onChanged: _onTextChanged,
            ),
            // Remote cursors overlay
            IgnorePointer(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  return Stack(
                    children: _remoteCursors.values
                        .map((c) => _buildRemoteCursor(c, constraints))
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteCursor(
      Map<String, dynamic> data, BoxConstraints constraints) {
    final int index = (data['cursor'] as num?)?.toInt() ?? 0;
    if (index > _textCtrl.text.length) return const SizedBox.shrink();

    final c = _parseColor(data['color']);

    final painter = TextPainter(
      text: TextSpan(
        text: _textCtrl.text,
        style: const TextStyle(
            fontSize: 16, height: 1.7, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: constraints.maxWidth - 56);

    final offset = painter.getOffsetForCaret(
      TextPosition(offset: index),
      Rect.zero,
    );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 120),
      left: offset.dx + 28,
      top: offset.dy + 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 2, height: 22, color: c),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: c,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(4),
                bottomRight: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Text(
              data['username'] ?? 'User',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
