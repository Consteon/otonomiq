import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart' show decUnread;
// Prefixed: `Notification` also exists in flutter/widgets.
import 'package:otonomiq/notification/bloc.dart' as inbox;
import 'package:otonomiq/widget/notification_list.dart'
    show notifFetchLimit, notifReloadKeys, shouldHealUnread;

// The badge-vs-list bug: chip showed 5 unread while every row rendered as read.
// `urd` is a stored counter (+1 per push, -1 per tap through a transaction that
// fails offline while the st:101 write still lands), so it drifts above the
// truth and never comes back down. These two pure helpers are the repair.

void main() {
  group('decUnread', () {
    test('decrements a normal counter', () {
      expect(decUnread(5), 4);
      expect(decUnread(1), 0);
    });

    test('never goes negative', () {
      expect(decUnread(0), 0);
      expect(decUnread(-3), 0);
    });

    test('survives a missing or garbage counter (used to throw in the tx)', () {
      expect(decUnread(null), 0);
      expect(decUnread('7'), 0);
      expect(decUnread(3.0), 2); // Firestore can hand back a double
    });
  });

  group('shouldHealUnread', () {
    test('heals when the stored counter disagrees with the messages', () {
      expect(
        shouldHealUnread(stored: 5, actual: 0, fetched: 11, fromCache: false),
        isTrue,
      );
    });

    test('no write when the counter is already right', () {
      expect(
        shouldHealUnread(stored: 2, actual: 2, fetched: 11, fromCache: false),
        isFalse,
      );
    });

    test('skips a cache-served fetch — it may be stale', () {
      expect(
        shouldHealUnread(stored: 5, actual: 0, fetched: 11, fromCache: true),
        isFalse,
      );
    });

    test('skips a full window — unread may exist beyond it', () {
      expect(
        shouldHealUnread(
            stored: 60, actual: 0, fetched: notifFetchLimit, fromCache: false),
        isFalse,
      );
      // one short of the cap is still the whole history
      expect(
        shouldHealUnread(
            stored: 60,
            actual: 0,
            fetched: notifFetchLimit - 1,
            fromCache: false),
        isTrue,
      );
    });

    test('heals upward too, not just down', () {
      expect(
        shouldHealUnread(stored: 0, actual: 3, fetched: 12, fromCache: false),
        isTrue,
      );
    });
  });

  // The "new notification does not appear until you leave and come back" bug.
  // The channel collection streams live, but the MESSAGES are a one-shot .get()
  // per channel, gated by this key. Keyed on vid alone, a new message in an
  // existing channel produced an identical key list and the fan-out never
  // re-ran. `same` below is exactly the comparison the widget does.
  group('notifReloadKeys', () {
    bool same(List<inbox.Notification> a, List<inbox.Notification> b) =>
        listEquals(notifReloadKeys(a), notifReloadKeys(b));

    test('new message in an EXISTING channel is detected (the bug)', () {
      expect(
        same(
          const [inbox.Notification(vid: 'v1', lastMessageTime: 100)],
          const [inbox.Notification(vid: 'v1', lastMessageTime: 200)],
        ),
        isFalse,
      );
    });

    test('a single unchanged channel does not refetch', () {
      expect(
        same(
          const [inbox.Notification(vid: 'v1', lastMessageTime: 100)],
          const [inbox.Notification(vid: 'v1', lastMessageTime: 100)],
        ),
        isTrue,
      );
    });

    test('urd-only movement does NOT refetch (tap-to-read, heal write)', () {
      // decUnread on tap and shouldHealUnread's own write both change `urd`.
      // Keying on it would re-fan-out every channel for unchanged content and
      // risk a heal -> emit -> refetch -> heal loop.
      expect(
        same(
          const [
            inbox.Notification(vid: 'v1', lastMessageTime: 100, unRead: 5)
          ],
          const [
            inbox.Notification(vid: 'v1', lastMessageTime: 100, unRead: 0)
          ],
        ),
        isTrue,
      );
    });

    test('a brand-new channel is detected', () {
      expect(
        same(
          const [inbox.Notification(vid: 'v1', lastMessageTime: 100)],
          const [
            inbox.Notification(vid: 'v2', lastMessageTime: 300),
            inbox.Notification(vid: 'v1', lastMessageTime: 100),
          ],
        ),
        isFalse,
      );
    });

    test('reorder by lt is detected (stream sorts lt descending)', () {
      expect(
        same(
          const [
            inbox.Notification(vid: 'v1', lastMessageTime: 300),
            inbox.Notification(vid: 'v2', lastMessageTime: 100),
          ],
          const [
            inbox.Notification(vid: 'v2', lastMessageTime: 400),
            inbox.Notification(vid: 'v1', lastMessageTime: 300),
          ],
        ),
        isFalse,
      );
    });

    test('missing vid / lt degrade to a stable key instead of throwing', () {
      expect(notifReloadKeys(const [inbox.Notification()]), ['|0']);
      expect(
        same(const [inbox.Notification()], const [inbox.Notification()]),
        isTrue,
      );
    });

    test('empty channel list yields an empty key list', () {
      expect(notifReloadKeys(const []), isEmpty);
    });
  });
}
