import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import '../firestore_repository/firestore_generic_repository.dart';
import '../global.dart';
import 'approver_sticky_bar.dart';
import 'where_eq_type_tolerant.dart';

class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  final dynamic component;
  final String scrName;
  final double lPad, tPad, rPad, bPad;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  String _label = 'CONVERSATION';
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  StreamSubscription? _subscription;
  CollectionReference? _commentCollRef;
  bool _expanded = false;
  String _searchKey = '';
  String _searchValue = '';
  int _nameIdx = 1;
  int _attachIdx = 5;
  int _tsIdx = 4;
  String _variant = 'comment';
  bool _sortAsc = true;

  final ImagePicker _picker = ImagePicker();
  final List<File> _pendingAttachments = [];
  final Set<String> _cameraFiles = {};
  bool _uploading = false;
  int _attachmentMax = 3;
  String _attachmentFolder = '';
  String _attachmentFilename = '';
  List<String> _attachmentSources = const ['camera'];
  OverlayEntry? _inputEntry;
  bool _hasCommentBox = false;

  @override
  void initState() {
    super.initState();
    _initConfig();
    _setupStream();
    if (_hasCommentBox) {
      ApproverStickyBar.ensureRouteListener();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _insertInputOverlay();
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _commentController.dispose();
    _inputEntry?.remove();
    _inputEntry = null;
    super.dispose();
  }

  void _insertInputOverlay() {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final scrName = widget.scrName;
    _inputEntry = OverlayEntry(
      builder: (ctx) {
        return ValueListenableBuilder<String>(
          valueListenable: ApproverStickyBar.activeBarScreen,
          builder: (_, activeScreen, _) {
            if (activeScreen != scrName) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: ApproverStickyBar.overlaysHidden,
              builder: (vctx, hidden, _) {
                if (hidden) return const SizedBox.shrink();
                final bottomInset = MediaQuery.of(vctx).viewInsets.bottom;
                final safeBottom = MediaQuery.of(vctx).padding.bottom;
                final hideNav =
                    screenUIComponent[scrName]?['hideBottomBar'] == true;
                final navBarHeight = hideNav ? 0.0 : 66.0;
                final bottomPadding = hideNav ? 8.0 : 0.0;
                final keyboardUp = bottomInset > 0;
                // With a bottom nav bar, sit the bar on top of it
                // (navBarHeight + safeBottom). With NO nav bar the bar IS the
                // bottom-most element: anchor it at bottom:0 so the white
                // background reaches the screen edge (no floating gap), and let
                // SafeArea pad the content above the home indicator instead of
                // offsetting the whole bar by safeBottom (which left it floating).
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: keyboardUp
                      ? bottomInset
                      : (hideNav ? 0.0 : navBarHeight + safeBottom),
                  child: Material(
                    color: Colors.white,
                    elevation: 8,
                    child: SafeArea(
                      top: false,
                      bottom: hideNav && !keyboardUp,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: bottomPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildInputSection(vctx),
                            ValueListenableBuilder<WidgetBuilder?>(
                              valueListenable: ApproverStickyBar.slot,
                              builder: (innerCtx, builder, _) {
                                if (builder == null || bottomInset > 0) {
                                  return const SizedBox.shrink();
                                }
                                return builder(innerCtx);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
    overlay.insert(_inputEntry!);
  }

  void _initConfig() {
    _variant = (widget.component['variant'] ?? 'comment')
        .toString()
        .trim()
        .toLowerCase();
    _sortAsc =
        (widget.component['sort'] ?? 'asc').toString().trim().toLowerCase() !=
        'desc';
    String textRaw = (widget.component['text'] ?? '').toString().trim();
    String text = autheniumDecode(textRaw) ?? textRaw;
    if (text.isNotEmpty) {
      List<String> textParts = text.split('◆');
      _label = textParts[0];
      if (textParts.length > 1) {
        _nameIdx = _parseFieldIdx(textParts[1], 2) - 1;
      }
      if (textParts.length > 2) {
        _attachIdx = _parseFieldIdx(textParts[2], 6) - 1;
      }
      if (textParts.length > 3) {
        _tsIdx = _parseFieldIdx(textParts[3], 5) - 1;
      }
    }

    if (_variant != 'timeline') {
      try {
        List<dynamic> children = screenUIComponent[widget.scrName]['children'];
        for (var comp in children) {
          if (comp['type']?.toString().toLowerCase() == 'txf' &&
              comp['variant']?.toString().toLowerCase() == 'commentbox') {
            _hasCommentBox = true;
            _attachmentFolder = (comp['attachmentFolder'] ?? '').toString();
            _attachmentFilename = (comp['attachmentFilename'] ?? '').toString();
            _attachmentMax =
                int.tryParse((comp['attachmentMax'] ?? '3').toString()) ?? 3;
            String srcRaw = (comp['source'] ?? '').toString().trim();
            if (srcRaw.isNotEmpty) {
              _attachmentSources = srcRaw
                  .split('◆')
                  .map((s) => s.trim().toLowerCase())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
            break;
          }
        }
      } catch (_) {}
    }
  }

  int _parseFieldIdx(String raw, int fallback) {
    RegExpMatch? m = RegExp(r'<(\d+)>').firstMatch(raw.trim());
    return m != null ? (int.tryParse(m.group(1)!) ?? fallback) : fallback;
  }

  String _resolveNamedMarkers(String text) {
    var screenTx = transactionStore.state.screenTx;
    return text.replaceAllMapped(RegExp(r'<([a-zA-Z_][a-zA-Z0-9_]*)>'), (m) {
      String key = m.group(1)!;
      return screenTx[key]?.toString() ?? m.group(0)!;
    });
  }

  void _setupStream() {
    String rawTable = (widget.component['table'] ?? '').toString().trim();
    String decoded = autheniumDecode(rawTable) ?? rawTable;
    String resolved = _resolveNamedMarkers(decoded);

    int dblSlashIdx = resolved.indexOf('//');
    if (dblSlashIdx < 0) {
      debugPrint('[Timeline] no // separator found');
      return;
    }

    String beforeDblSlash = resolved.substring(0, dblSlashIdx);
    String afterDblSlash = resolved.substring(dblSlashIdx + 2);
    List<String> afterParts = afterDblSlash
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (afterParts.isEmpty) {
      debugPrint('[Timeline] no subcollection after //');
      return;
    }

    String tableCode;
    String subcollection;

    int contentIdx = beforeDblSlash.lastIndexOf('/content/');
    if (contentIdx >= 0) {
      // Format: path/content/{docId}//comment
      tableCode = beforeDblSlash.substring(0, contentIdx);
      subcollection = afterParts.first;
    } else if (afterParts.length >= 2) {
      // Format: prefix//tableDoc/content/{docId}/comment
      tableCode = '$beforeDblSlash/${afterParts[0]}';
      subcollection = afterParts.last;
    } else {
      // Format: basePath//tableName (e.g., $test/request-approval//comment)
      tableCode = '$beforeDblSlash/${afterParts.first}';
      subcollection = '';
    }

    var screenTx = transactionStore.state.screenTx;
    int vid =
        int.tryParse((screenTx['approval_vidtable'] ?? '').toString()) ??
        int.tryParse((widget.component['vidtable'] ?? '').toString()) ??
        appCodeController.applicationTableVid;
    String basePath = '$mobileTable/$vid/$mobileTableCollection';

    String searchRaw = (widget.component['search'] ?? '').toString();
    if (searchRaw.isNotEmpty) {
      String searchDecoded = autheniumDecode(searchRaw) ?? searchRaw;
      String searchResolved = _resolveNamedMarkers(searchDecoded);
      if (searchResolved.contains('◼')) {
        List<String> parts = searchResolved.split('◼');
        _searchKey = parts[0].trim();
        _searchValue = parts.length > 1 ? parts[1].trim() : '';
      }
    }

    debugPrint('[Timeline] === PATH DEBUG ===');
    debugPrint('[Timeline] resolved: $resolved');
    debugPrint('[Timeline] contentIdx: $contentIdx');
    debugPrint('[Timeline] basePath: $basePath');
    debugPrint('[Timeline] tableCode: $tableCode');
    debugPrint('[Timeline] subcollection: $subcollection');
    debugPrint('[Timeline] search: key=$_searchKey value=$_searchValue');
    debugPrint('[Timeline] === END PATH DEBUG ===');

    try {
      DocumentReference tableDocRef = firestoreDb
          .collection(basePath)
          .doc(tableCode);

      if (subcollection.isEmpty) {
        // New format: comments are content docs in the table
        _commentCollRef = tableDocRef.collection(mobileTableContent);
        debugPrint('[Timeline] subscribing directly: ${_commentCollRef!.path}');
        Query query;
        if (_searchKey.isNotEmpty && _searchValue.isNotEmpty) {
          query = whereEqTypeTolerant(
            _commentCollRef!,
            _searchKey,
            _searchValue,
          );
        } else {
          query = _commentCollRef!;
        }
        _subscription = query.snapshots().listen((snap) {
          if (!mounted) return;
          List<Map<String, dynamic>> parsed = [];
          for (var doc in snap.docs) {
            var raw = doc.data() as Map<String, dynamic>;
            int t = (raw['t'] as int?) ?? 0;
            Map<String, dynamic> entry = {'t': t};
            try {
              List<dynamic> fields = jsonDecode(raw['c'] ?? '[]');
              entry['n'] = fields.length > _nameIdx
                  ? fields[_nameIdx].toString()
                  : '';
              entry['a'] = fields.length > _attachIdx
                  ? fields[_attachIdx].toString()
                  : '';
              entry['ts'] = fields.length > _tsIdx
                  ? fields[_tsIdx].toString()
                  : '';
              entry['c'] = fields.length > 3 ? fields[3].toString() : '';
            } catch (_) {
              entry['c'] = raw['c'] ?? '';
            }
            parsed.add(entry);
          }
          parsed.sort((a, b) {
            int tA = a['t'] as int? ?? 0;
            int tB = b['t'] as int? ?? 0;
            return _sortAsc ? tA.compareTo(tB) : tB.compareTo(tA);
          });
          setState(() => _comments = parsed);
        });
      } else {
        // Old format: find content doc by request_doc_t, then subcollection
        var screenTx = transactionStore.state.screenTx;
        String docT = (screenTx['request_doc_t'] ?? '').toString();
        debugPrint('[Timeline] docT: $docT');
        if (docT.isEmpty) {
          debugPrint('[Timeline] request_doc_t not found in transactionStore');
          return;
        }
        CollectionReference contentRef = tableDocRef.collection(
          mobileTableContent,
        );
        int? tValue = int.tryParse(docT);
        debugPrint('[Timeline] querying content where t=${tValue ?? docT}');
        contentRef
            .where('t', isEqualTo: tValue ?? docT)
            .get()
            .then((snapshot) {
              if (!mounted) return;
              if (snapshot.docs.isEmpty) {
                debugPrint('[Timeline] no content doc found with t=$docT');
                return;
              }
              DocumentReference contentDocRef = snapshot.docs.first.reference;
              _commentCollRef = contentDocRef.collection(subcollection);
              debugPrint('[Timeline] content doc: ${contentDocRef.path}');
              debugPrint('[Timeline] subscribing: ${_commentCollRef!.path}');
              _subscription = _commentCollRef!
                  .orderBy('t', descending: !_sortAsc)
                  .snapshots()
                  .listen((snap) {
                    if (!mounted) return;
                    setState(() {
                      _comments = snap.docs
                          .map((d) => d.data() as Map<String, dynamic>)
                          .toList();
                    });
                  });
            })
            .catchError((e) {
              debugPrint('[Timeline] query error: $e');
            });
      }
    } catch (e) {
      debugPrint('[Timeline] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_variant == 'timeline') return _buildTimeline();
    return ValueListenableBuilder<WidgetBuilder?>(
      valueListenable: ApproverStickyBar.slot,
      builder: (ctx, approverBuilder, child) {
        double extraBottom = 0.0;
        if (_hasCommentBox) {
          extraBottom = approverBuilder != null ? 130.0 : 100.0;
          if (_pendingAttachments.isNotEmpty) extraBottom += 82.0;
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad + extraBottom,
          ),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_label.toUpperCase()} (${_comments.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                if (_comments.length > 1)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded
                                ? 'Show less'
                                : 'Show all ${_comments.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: const Color(0xFF2563EB),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No comments yet',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  ),
                ),
              )
            else
              ...() {
                int start = (!_expanded && _comments.length > 1)
                    ? _comments.length - 1
                    : 0;
                return List.generate(_comments.length - start, (idx) {
                  int i = start + idx;
                  var data = _comments[i];
                  String name = (data['n'] ?? '').toString();
                  String message = (data['c'] ?? '').toString();
                  String timestamp = (data['ts'] ?? '').toString();
                  String attachment = (data['a'] ?? '').toString();
                  bool isSystem = name.toLowerCase() == 'system';
                  bool isLast = i == _comments.length - 1;
                  return _buildCommentEntry(
                    name: name,
                    message: message,
                    timestamp: timestamp,
                    attachment: attachment,
                    isSystem: isSystem,
                    showConnector: !isLast,
                  );
                });
              }(),
          ],
        ),
      ),
    );
  }

  static const _timelineDotColors = [
    Color(0xFF3B82F6),
    Color(0xFFA855F7),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFF9CA3AF),
  ];

  Widget _buildTimeline() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                if (_comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Belum ada aktivitas',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(_comments.length, (i) {
                    var data = _comments[i];
                    return _buildTimelineEntry(
                      name: (data['n'] ?? '').toString(),
                      message: (data['a'] ?? '').toString(),
                      timestamp: (data['ts'] ?? '').toString(),
                      index: i,
                      showConnector: i < _comments.length - 1,
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildTimelineEntry({
    required String name,
    required String message,
    required String timestamp,
    required int index,
    required bool showConnector,
  }) {
    Color dotColor = _timelineDotColors[index % _timelineDotColors.length];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (showConnector)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFFD1D5DB),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 20 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (timestamp.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      timestamp,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingAttachments.isNotEmpty) ...[
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingAttachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final file = _pendingAttachments[i];
                  final isImage = _isImageFile(file.path);
                  final ext = _fileExtension(file.path);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (isImage)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            file,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            // cache-dir attachment can be evicted/moved before
                            // the async load lands → PathNotFoundException
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 72,
                              height: 72,
                              child: Icon(Icons.broken_image, size: 24),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: _docColor(ext).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _docColor(ext).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _docIcon(ext),
                                size: 28,
                                color: _docColor(ext),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ext.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _docColor(ext),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => _removeAttachment(i),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Material(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _uploading ? null : _pickAttachment,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.attach_file_rounded,
                      size: 20,
                      color: _pendingAttachments.length >= _attachmentMax
                          ? const Color(0xFFD1D5DB)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commentController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF2563EB)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _uploading ? null : _onSend,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: _uploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, String> _parseAddToTable() {
    String raw = (widget.component['addToTable'] ?? '').toString();

    if (raw.isEmpty) {
      try {
        List<dynamic> children = screenUIComponent[widget.scrName]['children'];
        for (var comp in children) {
          if (comp['type']?.toString().toLowerCase() == 'txf' &&
              comp['variant']?.toString().toLowerCase() == 'commentbox') {
            raw = (comp['addToTable'] ?? '').toString();
            break;
          }
        }
      } catch (_) {}
    }

    String decoded = autheniumDecode(raw) ?? raw;
    decoded = _resolveNamedMarkers(decoded);
    Map<String, String> fields = {};
    if (decoded.isEmpty) return fields;

    List<String> parts = decoded.split('⭘');
    for (var part in parts) {
      if (!part.contains('◼')) continue;
      List<String> kv = part.split('◼');
      String key = kv[0].trim();
      String value = kv.length > 1 ? kv.sublist(1).join('◼') : '';
      if (key.startsWith('<') && key.endsWith('>')) {
        fields[key] = value;
      }
    }
    return fields;
  }

  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'heic',
  };

  bool _isImageFile(String path) {
    String ext = path.split('.').last.toLowerCase();
    return _imageExtensions.contains(ext);
  }

  String _fileExtension(String path) {
    return path.contains('.') ? path.split('.').last.toLowerCase() : '';
  }

  IconData _docIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _docColor(String ext) {
    switch (ext) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'doc':
      case 'docx':
        return const Color(0xFF2563EB);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF16A34A);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFF6B7280);
    }
  }

  void _pickAttachment() async {
    if (_pendingAttachments.length >= _attachmentMax) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $_attachmentMax attachments')),
      );
      return;
    }

    final screenSize = MediaQuery.of(context).size;
    ApproverStickyBar.overlaysHidden.value = true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add attachment',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ),
            if (_attachmentSources.contains('camera'))
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            if (_attachmentSources.contains('gallery'))
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            if (_attachmentSources.contains('document') ||
                _attachmentSources.contains('file'))
              ListTile(
                leading: const Icon(Icons.insert_drive_file_rounded),
                title: const Text('Document'),
                subtitle: const Text('PDF, Word, Excel, etc.'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
          ],
        ),
      ),
    );
    ApproverStickyBar.overlaysHidden.value = false;
    if (choice == null) return;

    try {
      if (choice == 'camera') {
        final List<CameraDescription> cams = await ensureCams();
        if (cams.isEmpty) {
          debugPrint('[Timeline] #CAMS missing, fallback to ImagePicker');
          final XFile? picked = await _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1080,
            maxHeight: 1080,
            imageQuality: 80,
          );
          if (picked == null) return;
          _cameraFiles.add(picked.path);
          setState(() => _pendingAttachments.add(File(picked.path)));
          _inputEntry?.markNeedsBuild();
        } else {
          String folder = _attachmentFolder.isEmpty
              ? 'comment-temp'
              : _resolveNamedMarkers(_attachmentFolder).replaceAll('//', '/');
          String baseName = _attachmentFilename.isEmpty
              ? 'comment'
              : _resolveNamedMarkers(_attachmentFilename);
          String fileName =
              '${baseName}_${DateTime.now().millisecondsSinceEpoch}';
          final imgUrl = await getPhotoCameraImage(
            cams,
            'Camera',
            'back',
            400,
            80,
            folder,
            fileName,
            screenSize.height,
            screenSize.width,
          );
          if (imgUrl == emptyImageUrl) return;
          final localPath = imgUrl
              .replaceAll(localImagePrefix, '')
              .replaceAll(localImagePostfix, '');
          if (localPath.isEmpty) return;
          _cameraFiles.add(localPath);
          setState(() => _pendingAttachments.add(File(localPath)));
          _inputEntry?.markNeedsBuild();
        }
      } else if (choice == 'gallery') {
        final XFile? picked = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1080,
          maxHeight: 1080,
          imageQuality: 80,
        );
        if (picked == null) return;
        setState(() => _pendingAttachments.add(File(picked.path)));
        _inputEntry?.markNeedsBuild();
      } else {
        FilePickerResult? result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'jpg',
            'jpeg',
            'png',
            'gif',
          ],
        );
        if (result == null || result.files.single.path == null) return;
        setState(
          () => _pendingAttachments.add(File(result.files.single.path!)),
        );
        _inputEntry?.markNeedsBuild();
      }
    } catch (e) {
      debugPrint('[Timeline] pick error: $e');
    }
  }

  void _removeAttachment(int index) {
    setState(() => _pendingAttachments.removeAt(index));
    _inputEntry?.markNeedsBuild();
  }

  void _openFullScreenImage(String url) {
    ApproverStickyBar.overlaysHidden.value = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _FullScreenImageViewer(imageUrl: url),
          ),
        )
        .whenComplete(() => ApproverStickyBar.overlaysHidden.value = false);
  }

  void _confirmDownload(String url, String filename) {
    String ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';

    ApproverStickyBar.overlaysHidden.value = true;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _docColor(ext).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_docIcon(ext), size: 24, color: _docColor(ext)),
              ),
              const SizedBox(height: 12),
              Text(
                filename,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                ext.toUpperCase(),
                style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _downloadFile(url, filename);
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => ApproverStickyBar.overlaysHidden.value = false);
  }

  void _downloadFile(String url, String filename) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Downloading...')));
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Download failed')));
        }
        return;
      }

      Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!dir.existsSync()) {
          dir = await getApplicationDocumentsDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(response.bodyBytes);
      debugPrint('[Timeline] file saved: ${file.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Downloads: $filename')),
        );
      }
    } catch (e) {
      debugPrint('[Timeline] download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Download failed')));
      }
    }
  }

  void _onSend() async {
    String text = _commentController.text.trim();
    if (text.isEmpty || _commentCollRef == null) return;

    setState(() => _uploading = true);
    _inputEntry?.markNeedsBuild();

    Map<String, String> addFields = _parseAddToTable();
    String name = addFields['<2>'] ?? currentUser?.displayName ?? '';
    String vid =
        addFields['<3>'] ??
        (transactionStore.state.screenTx['#VID'] ?? '').toString();
    String rating = addFields['<7>'] ?? '';
    int now = DateTime.now().millisecondsSinceEpoch;
    String formattedDate = DateFormat(
      'dd MMM yyyy HH:mm',
    ).format(DateTime.now());

    List<String> uploadedUrls = [];
    if (_pendingAttachments.isNotEmpty) {
      String folder = _resolveNamedMarkers(
        _attachmentFolder,
      ).replaceAll('//', '/');
      String baseFilename = _resolveNamedMarkers(_attachmentFilename);

      debugPrint('[Timeline] === UPLOAD DEBUG ===');
      debugPrint('[Timeline] raw attachmentFolder: $_attachmentFolder');
      debugPrint('[Timeline] resolved folder: $folder');
      debugPrint('[Timeline] raw attachmentFilename: $_attachmentFilename');
      debugPrint('[Timeline] resolved baseFilename: $baseFilename');
      debugPrint('[Timeline] pending count: ${_pendingAttachments.length}');

      for (int i = 0; i < _pendingAttachments.length; i++) {
        String ts = DateTime.now().millisecondsSinceEpoch.toString();
        String localPath = _pendingAttachments[i].path;
        String ext = _fileExtension(localPath);
        if (ext.isEmpty) ext = 'jpg';
        String cloudFilename;
        if (_cameraFiles.contains(localPath)) {
          cloudFilename = '$ts.$ext';
        } else {
          String originalName = localPath.split('/').last;
          String nameWithoutExt = originalName.contains('.')
              ? originalName.substring(0, originalName.lastIndexOf('.'))
              : originalName;
          cloudFilename = '${nameWithoutExt}_$ts.$ext';
        }
        String cloudPath = '$folder/$cloudFilename';
        debugPrint('[Timeline] uploading [$i]: $cloudPath');
        debugPrint('[Timeline] local file: ${_pendingAttachments[i].path}');
        try {
          String url = await uploadToCloudStorage(
            _pendingAttachments[i].path,
            cloudPath,
          );
          debugPrint('[Timeline] upload result [$i]: $url');
          debugPrint('[Timeline] isValidUrl [$i]: ${isValidImageUrl(url)}');
          if (isValidImageUrl(url)) uploadedUrls.add(url);
        } catch (e) {
          debugPrint('[Timeline] upload error [$i]: $e');
        }
      }
      debugPrint('[Timeline] === END UPLOAD DEBUG ===');
    }

    String attachment = uploadedUrls.isNotEmpty
        ? uploadedUrls.join('◇')
        : (addFields['<6>'] ?? '');

    try {
      List<String> content = [
        _searchValue,
        name,
        vid,
        text,
        formattedDate,
        attachment,
        rating,
      ];
      await _commentCollRef!.add({
        'c': jsonEncode(content),
        't': now,
        if (_searchKey.isNotEmpty && _searchValue.isNotEmpty)
          _searchKey: _searchValue,
      });
      _commentController.clear();
      setState(() {
        _pendingAttachments.clear();
        _cameraFiles.clear();
        _uploading = false;
      });
      _inputEntry?.markNeedsBuild();
    } catch (e) {
      debugPrint('[Timeline] _onSend error: $e');
      setState(() => _uploading = false);
      _inputEntry?.markNeedsBuild();
    }
  }

  String _getInitials(String name) {
    List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Widget _buildCommentEntry({
    required String name,
    required String message,
    required String timestamp,
    required String attachment,
    required bool isSystem,
    required bool showConnector,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (isSystem)
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFEDE9FE),
                  child: const Icon(
                    Icons.auto_fix_high_rounded,
                    size: 16,
                    color: Color(0xFF7C3AED),
                  ),
                )
              else
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFE0E7FF),
                  child: Text(
                    _getInitials(name),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
              if (showConnector)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 16 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      if (timestamp.isNotEmpty)
                        Text(
                          timestamp,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (message.isNotEmpty)
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF374151),
                        height: 1.5,
                      ),
                    ),
                  if (attachment.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: attachment
                          .split('◇')
                          .where((u) => u.trim().startsWith('http'))
                          .map((url) {
                            String trimmed = url.trim();
                            String decodedPath = Uri.decodeFull(
                              trimmed.split('?').first.split('/o/').last,
                            );
                            String ext = decodedPath.contains('.')
                                ? decodedPath.split('.').last.toLowerCase()
                                : '';
                            bool isImg = _imageExtensions.contains(ext);

                            String fileName = decodedPath.split('/').last;

                            if (isImg) {
                              return GestureDetector(
                                onTap: () => _openFullScreenImage(trimmed),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    trimmed,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              );
                            }
                            return GestureDetector(
                              onTap: () => _confirmDownload(trimmed, fileName),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _docColor(ext).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _docColor(
                                      ext,
                                    ).withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _docIcon(ext),
                                      size: 20,
                                      color: _docColor(ext),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        fileName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _docColor(ext),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.download_rounded,
                                      size: 16,
                                      color: _docColor(ext),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                        : null,
                    color: Colors.white,
                  ),
                );
              },
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  size: 64,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
