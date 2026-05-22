import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class TaskProgressStore extends ChangeNotifier {
  TaskProgressStore._();
  static final instance = TaskProgressStore._();

  final Map<String, Map<int, String>> _registry = {};

  void register(String scrName, int position) {
    _registry.putIfAbsent(scrName, () => {})[position] = 'pending';
    notifyListeners();
  }

  void update(String scrName, int position, String status) {
    if (_registry[scrName] == null) return;
    _registry[scrName]![position] = status;
    notifyListeners();
  }

  void unregister(String scrName, int position) {
    _registry[scrName]?.remove(position);
    SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  int totalFor(String scrName, List<int> positions) {
    final map = _registry[scrName];
    if (map == null) return 0;
    return positions.where((p) => map.containsKey(p)).length;
  }

  int doneFor(String scrName, List<int> positions) {
    final map = _registry[scrName];
    if (map == null) return 0;
    return positions.where((p) => map[p] == 'done').length;
  }

  double progressFor(String scrName, List<int> positions) {
    final t = totalFor(scrName, positions);
    return t == 0 ? 0.0 : doneFor(scrName, positions) / t;
  }

  @visibleForTesting
  void clear() {
    _registry.clear();
    notifyListeners();
  }
}
