import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart' show internetConnectionFlag;
import 'package:otonomiq/widget/offline_banner.dart';

void main() {
  const String bannerText =
      'Offline — perubahan disimpan & dikirim otomatis';

  Widget host() => const MaterialApp(
        home: Scaffold(
          body: OfflineBannerHost(child: Text('CONTENT')),
        ),
      );

  testWidgets('banner hidden when online', (tester) async {
    internetConnectionFlag.value = true;
    await tester.pumpWidget(host());
    expect(find.text('CONTENT'), findsOneWidget);
    expect(find.text(bannerText), findsNothing);
  });

  testWidgets('banner visible when offline', (tester) async {
    internetConnectionFlag.value = false;
    await tester.pumpWidget(host());
    expect(find.text('CONTENT'), findsOneWidget);
    expect(find.text(bannerText), findsOneWidget);
  });

  testWidgets('banner reacts to flag flips (Obx)', (tester) async {
    internetConnectionFlag.value = true;
    await tester.pumpWidget(host());
    expect(find.text(bannerText), findsNothing);

    internetConnectionFlag.value = false;
    await tester.pump(); // Obx rebuild
    expect(find.text(bannerText), findsOneWidget);

    internetConnectionFlag.value = true;
    await tester.pump();
    expect(find.text(bannerText), findsNothing);
  });
}
