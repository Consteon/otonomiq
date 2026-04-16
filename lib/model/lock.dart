import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

class Lock {
  /*
    generic lock class

    usage :
     final lock = Lock();
     await lock.lock();
     print('$name acquired the lock');
     await Future.delayed(Duration(seconds: 1));
     print('$name released the lock');
     lock.unlock();
  */
  final int expirationIntervalSeconds;
  Completer<void>? _completer;
  int queueSize = 0;
  final int queueMax;
  Map<String, int> lockedItem = {}; // put here a key that want to be locked,
  // and the time it is locked

  Lock(
      {this.expirationIntervalSeconds = 30,
      this.queueMax = 1}); // Default to 30 seconds

  Future<bool> itemLockWait(String caller, String item) async {
    final int startLocking = DateTime.now().millisecondsSinceEpoch;
    int itemLockTime = lockedItem[item] ?? startLocking;
    int retryCount = 0;
    bool locked = false;

    debugPrint('$caller waiting for itemLockWait');

    while (true) {
      final int currentTime = DateTime.now().millisecondsSinceEpoch;
      final int elapsedTime = currentTime - startLocking;
      final bool lockExpired =
          (currentTime - itemLockTime) > expirationIntervalSeconds * 1000;

      if (lockExpired || elapsedTime >= expirationIntervalSeconds * 1000) {
        break;
      }

      if (lockedItem[item] == null) {
        lockedItem[item] = currentTime;
        debugPrint('$caller get itemLockWait for $item');
        locked = true;
        break;
      }

      await Future.delayed(
          Duration(milliseconds: pow(2, min(retryCount++, 8)).toInt() * 10));
    }

    if (!locked) {
      debugPrint('$caller cannot get itemLockWait, item $item is locked');
    }

    return locked;
  } // end of itemLockWait

  void itemUnlockWait(String caller, String item) {
    if (lockedItem.containsKey(item)) {
      lockedItem.remove(item);
      debugPrint('$caller released itemLockWait for $item');
    } else {
      debugPrint('$caller tried to release itemLockWait for $item, but it was not locked');
    }
  } // end of itemUnlockWait

  bool queueLock(String caller) {
    bool result = false;
    const queueMax = 1;
    if (queueSize >= queueMax) {
      debugPrint(
          '$caller cannot get lock1, queue size $queueSize >= $queueMax');
    } else {
      queueSize++;
      result = true;
      debugPrint('$caller get lock1');
    }
    return result;
  } // end of lock

  void queueUnlock(String caller) {
    queueSize = max(0, queueSize - 1);
    debugPrint('$caller released lock1');
  }

  Future<void> lock(String caller) async {
    debugPrint('$caller waiting for lock');
    int retryCount = 0;
    while (_completer != null) {
      //await _completer!.future;
      await Future.delayed(
          Duration(milliseconds: pow(2, min(retryCount, 8)).toInt() * 10));
      retryCount++;
    }
    _completer = Completer<void>();
    debugPrint('$caller get lock');
  } // end of lock

  void unlock(String caller) {
    _completer?.complete();
    _completer = null;
    debugPrint('$caller released the lock');
  }
}
