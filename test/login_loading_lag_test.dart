import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/login/api/user_repository.dart';

void main() {
  group('LoginPerf flag', () {
    test('loginPerfTrace is a static bool on UserRepository', () {
      // Verify the flag exists and is a bool.
      // When the instrumentation is no longer needed, this test
      // reminds the engineer to remove the flag (set it to false
      // or delete the field entirely).
      expect(UserRepository.loginPerfTrace, isA<bool>());
    });
  });
}
