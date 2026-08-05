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

// Per-channel fetch window. Both the chip count and the `urd` heal depend on
// it: a FULL window means older messages exist that this screen cannot see.
const int notifFetchLimit = 50;

// `urd` (the stored per-thread unread counter shown on the chip pill and the
// home bell) is hand-maintained: +1 per push (firebase_notification_handler),
// -1 per tap through a TRANSACTION that fails offline while the `st:101` update
// queues and lands anyway (api.dart setStatus). Every missed decrement is
// permanent — a badge with no unread row to match it, which is exactly the
// "badge 5 / zero unread rows" report. So rewrite the counter from what the
// messages actually say, but only when this fetch can see the whole truth:
//   - fromCache: the local copy may be stale; pushing it would clobber a
//     fresher server value once the write flushes.
//   - fetched == limit: unread messages may exist beyond the window, so the
//     count would then be wrong in the other direction.
// Refetch key for the message fan-out below. The channel STREAM is live, but
// the messages are not: they live in `$firestoreIO/<vid>/msg` and are pulled
// with a one-shot .get() per channel, so something has to decide when that
// pull is stale.
//
// vid alone is NOT that signal. A new message in an EXISTING channel leaves the
// vid list byte-identical, and with a single channel it cannot even reorder, so
// the feed only refreshed on leave+return — the reported bug. `lt` is written
// fresh on every push (parseFcmPayload -> threadUpdate) and the thread doc is
// updated AFTER the message doc, so `lt` flips exactly once per new message and
// only once that message is already readable.
//
// Deliberately NOT keyed on `urd`: that also moves on tap-to-read (decUnread)
// and on shouldHealUnread's own write, which would re-fan-out every channel for
// content that did not change — and heal -> emit -> refetch -> heal is a loop
// waiting to happen.
List<String> notifReloadKeys(List<Notification> channels) =>
    channels.map((c) => '${c.vid ?? ''}|${c.lastMessageTime ?? 0}').toList();

bool shouldHealUnread({
  required int stored,
  required int actual,
  required int fetched,
  required bool fromCache,
  int limit = notifFetchLimit,
}) => !fromCache && fetched < limit && stored != actual;

class NotificationList extends StatefulWidget {
  const NotificationList({super.key});

  @override
  State<NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  String _filterVid = ''; // '' = "All"
  bool _loading = false;
  List<_NotifRow> _rows = <_NotifRow>[];
  List<String> _loadedKeys = <String>[]; // guards duplicate fan-out fetches

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
    // Claim the keys BEFORE the awaits, not after. Claiming at the end let a
    // second emit landing mid-fan-out compare against the pre-fetch keys and
    // start a duplicate concurrent load whose setState races this one.
    _loadedKeys = notifReloadKeys(channels);
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
            .limit(notifFetchLimit)
            .get();
        int unread = 0;
        for (final d in snap.docs) {
          final m = d.data();
          final incoming = m['im'] == true;
          final st = _asInt(m['st']);
          final rt = (m['rt'] ?? '').toString();
          final isUnread = incoming && st != 101;
          if (isUnread) unread++;
          rows.add(
            _NotifRow(
              vid,
              name,
              c.profilePicture,
              (m['dp'] ?? '').toString(),
              notifNormalizeMs(_asInt(m['tr'])),
              rt.isEmpty ? null : rt,
              d.id,
              isUnread,
            ),
          );
        }
        // Reconcile the stored counter with the messages themselves — see
        // shouldHealUnread. Repairs the home bell too, since it sums `urd`.
        if (shouldHealUnread(
          stored: c.unRead ?? 0,
          actual: unread,
          fetched: snap.docs.length,
          fromCache: snap.metadata.isFromCache,
        )) {
          devPrint('[inbox] heal urd $vid ${c.unRead} -> $unread');
          safeFsUpdate(
            FirebaseFirestore.instance.doc('$firestoreIO/$vid'),
            <String, dynamic>{'urd': unread},
            'healUnread',
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
          final keys = notifReloadKeys(state.notifications);
          final stale = !listEquals(keys, _loadedKeys);
          // The one line that settles "did a push reach this screen, and did
          // the guard fire?" — a live navbar badge with a stale list looks
          // identical whether the emit never arrived or the key never moved.
          devPrint(
            '[inbox] emit ${stale ? 'REFETCH' : 'skip'} '
            'keys=$keys loaded=$_loadedKeys',
          );
          if (stale) _loadAll(state.notifications);
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

  // Count the rows on screen, NOT the stored `urd`: the counter drifts (see
  // shouldHealUnread) and a chip that disagrees with its own list is the bug
  // being reported. Derived from _rows, so it also drops the moment a row is
  // tapped or swiped away, instead of waiting for the Firestore round-trip.
  int _unreadCount(String vid) =>
      _rows.where((r) => r.vid == vid && r.unread).length;

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
                _unreadCount(c.vid ?? ''),
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
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      // bold marks unread only; read rows sit at normal weight
                      fontWeight: r.unread ? FontWeight.w700 : FontWeight.w400,
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
            if (!snap.exists) return; // tx.update on a missing doc throws
            tx.update(ioRef, {'urd': decUnread(snap.data()?['urd'])});
          })
          .catchError((_) {}); // offline: tx fails, next _loadAll heals it
    }
  }
}
