import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api.dart';
import '../global.dart';
import '../notification/bloc.dart';
import '../widget/notif_ui.dart';

// One flattened notification row: a single message plus the channel it
// belongs to. The old design forced a chat-style drill-down per channel;
// this screen merges every channel's messages into one filterable feed.
class _NotifRow {
  final String vid; // owning channel id (filter key)
  final String channel; // channel display name (eyebrow + chip label)
  final String? pic; // channel avatar url
  final String text; // message body (dp)
  final int? ms; // normalized received time
  final String? route; // rt — page to open on tap, if any
  final String msgId; // firestore doc id, for mark-read
  bool unread; // mutable: cleared optimistically on tap
  bool expanded = false; // inline expand toggle for long text
  _NotifRow(
    this.vid,
    this.channel,
    this.pic,
    this.text,
    this.ms,
    this.route,
    this.msgId,
    this.unread,
  );
}

class NotificationList extends StatefulWidget {
  const NotificationList({super.key});

  @override
  State<NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  String _filterVid = ''; // '' = "All"
  bool _loading = false;
  List<_NotifRow> _rows = <_NotifRow>[];
  List<String> _loadedVids = <String>[]; // guards duplicate fan-out fetches

  @override
  void initState() {
    super.initState();
    // Re-subscribe to the CURRENT firestoreIO path (see git history: warm/auto
    // start never re-fires LoadNotification, so the inbox would show empty).
    BlocProvider.of<NotificationBloc>(context).add(LoadNotification());
  }

  static int? _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);

  // Fan out one bounded read per channel and merge into a single feed. Cheap
  // for a handful of broadcast channels; ponytail: 50/channel cap — raise or
  // paginate if a channel ever holds more history than that.
  Future<void> _loadAll(List<Notification> channels) async {
    setState(() => _loading = true);
    final List<_NotifRow> rows = <_NotifRow>[];
    for (final c in channels) {
      final vid = c.vid ?? '';
      if (vid.isEmpty) continue;
      final name = (c.name != null && c.name!.trim().isNotEmpty)
          ? c.name!.trim()
          : vid;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('$firestoreIO/$vid/msg')
            .orderBy('tr', descending: true)
            .limit(50)
            .get();
        for (final d in snap.docs) {
          final m = d.data();
          final incoming = m['im'] == true;
          final st = _asInt(m['st']);
          final rt = (m['rt'] ?? '').toString();
          rows.add(
            _NotifRow(
              vid,
              name,
              c.profilePicture,
              (m['dp'] ?? '').toString(),
              notifNormalizeMs(_asInt(m['tr'])),
              rt.isEmpty ? null : rt,
              d.id,
              incoming && st != 101,
            ),
          );
        }
      } catch (_) {
        // Skip a channel we can't read rather than failing the whole feed.
      }
    }
    rows.sort((a, b) => (b.ms ?? 0).compareTo(a.ms ?? 0));
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      _loadedVids = channels.map((e) => e.vid ?? '').toList();
    });
  }

  void _onTapRow(_NotifRow r) {
    if (r.unread) {
      // setStatus reads these globals synchronously at entry — aim them at
      // this row's channel so st=101 + the urd decrement hit the right docs.
      firestoreNotif = '$firestoreIO/${r.vid}';
      firestoreMsg = '$firestoreNotif/msg';
      setStatus(r.msgId, 101).catchError((_) {}); // offline tx may throw
    }
    // Clear the dot unconditionally — a route row used to `return` before this
    // ran, so its dot only cleared on the next refetch (leave+return).
    final hasRoute = r.route != null && r.route!.isNotEmpty;
    setState(() {
      r.unread = false; // clear the red dot on tap/read
      if (!hasRoute)
        r.expanded = !r.expanded; // expand only when not navigating
    });
    if (hasRoute) _openRoute(r.route);
  }

  // Keep the message→route action from the old detail view.
  void _openRoute(String? route) {
    if (route == null || route.isEmpty) return;
    if (linkElement[route] == null) return; // page not built → no-op
    routeStack.push(route);
    final newElementList = reloadPage(route);
    rootThis.setState(() {
      rootThis.byPass = 0;
      rootThis.pageName = route;
      rootThis.pageElements = newElementList;
    });
  }

  void _back() {
    final pgName = routeStack.get();
    final newElementList = reloadPage(pgName);
    rootThis.setState(() {
      rootThis.byPass = 0;
      rootThis.pageName = pgName;
      rootThis.pageElements = newElementList;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return BlocConsumer<NotificationBloc, NotificationState>(
      listener: (context, state) {
        if (state is NotificationLoaded) {
          final vids = state.notifications.map((e) => e.vid ?? '').toList();
          if (!listEquals(vids, _loadedVids)) {
            _loadAll(state.notifications);
          }
        }
      },
      builder: (context, state) {
        final channels = state is NotificationLoaded
            ? state.notifications
            : <Notification>[];
        // Hide chips for channels with no messages — an empty category filter
        // only ever shows the empty state. Derived from _rows, so a chip also
        // disappears the moment its last row is swiped away, and comes back
        // when a new message lands. activeVid self-heals if the selected
        // channel emptied out (no setState during build).
        final liveVids = _rows.map((r) => r.vid).toSet();
        final live = channels
            .where((c) => liveVids.contains(c.vid ?? ''))
            .toList();
        final activeVid = liveVids.contains(_filterVid) ? _filterVid : '';
        final filtered = activeVid.isEmpty
            ? _rows
            : _rows.where((r) => r.vid == activeVid).toList();
        return Scaffold(
          backgroundColor: notifBg,
          appBar: AppBar(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _back,
            ),
            title: const Text(
              'Notification',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          body: Column(
            children: <Widget>[
              _chipBar(live, activeVid, primary),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _loadAll(channels),
                  child: _feed(filtered),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chipBar(
    List<Notification> channels,
    String activeVid,
    Color primary,
  ) {
    if (channels.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: <Widget>[
            _chip(
              'Semua',
              activeVid.isEmpty,
              0,
              primary,
              () => setState(() => _filterVid = ''),
            ),
            for (final c in channels)
              _chip(
                (c.name != null && c.name!.trim().isNotEmpty)
                    ? c.name!.trim()
                    : (c.vid ?? 'Pesan'),
                activeVid == c.vid,
                c.unRead ?? 0,
                primary,
                () => setState(() => _filterVid = c.vid ?? ''),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    String label,
    bool active,
    int unread,
    Color primary,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? primary.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? primary : notifBorder,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? primary : notifTextStrong,
                ),
              ),
              if (unread > 0) ...<Widget>[
                const SizedBox(width: 6),
                notifCountPill('$unread'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _feed(List<_NotifRow> rows) {
    if (_loading && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return ListView(
        // ListView (not Center) so pull-to-refresh still works when empty.
        children: <Widget>[
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          notifEmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Belum ada notifikasi',
            subtitle: 'Notifikasi yang masuk akan muncul di sini',
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        thickness: 1,
        indent: 78,
        color: notifBorder,
      ),
      itemBuilder: (context, index) => _tile(rows[index]),
    );
  }

  Widget _tile(_NotifRow r) {
    final tile = InkWell(
      onTap: () => _onTapRow(r),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            notifAvatarDot(r.channel, r.pic, 22, r.unread),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          r.channel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: notifTextMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        notifDateTime(r.ms),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: notifTextMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.text.isEmpty ? '-' : r.text,
                    maxLines: r.expanded ? null : 2,
                    overflow: r.expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: notifTextStrong,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Dismissible(
      key: ValueKey('${r.vid}/${r.msgId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) => _deleteRow(r),
      child: tile,
    );
  }

  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus notifikasi?'),
        content: const Text('Notifikasi ini akan dihapus permanen.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Hapus',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _deleteRow(_NotifRow r) {
    setState(() => _rows.remove(r));
    FirebaseFirestore.instance
        .collection('$firestoreIO/${r.vid}/msg')
        .doc(r.msgId)
        .delete()
        .catchError((_) {}); // offline: delete queues, syncs when online
    if (r.unread) {
      // keep the chip's unread count honest after removing an unread item
      final ioRef = FirebaseFirestore.instance.doc('$firestoreIO/${r.vid}');
      FirebaseFirestore.instance
          .runTransaction<void>((tx) async {
            final snap = await tx.get(ioRef);
            final cur = snap.data()?['urd'];
            final next = (cur is int && cur > 0) ? cur - 1 : 0;
            tx.update(ioRef, {'urd': next});
          })
          .catchError((_) {});
    }
  }
}
