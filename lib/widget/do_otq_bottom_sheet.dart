import 'package:flutter/material.dart';
import '../widget/ui_component.dart';
import 'package:get/get.dart';

Future doOtqBottomSheet(
    BuildContext context, String scrName, var bsComponent) async {
  double heightFactor =
      double.tryParse((bsComponent['height'] ?? '0.7').toString()) ?? 0.7;
  List<Widget> sheetWidgets =
  buildPage(bsComponent['children'], scrName, dialog: true, clear: false);

  double maxHeight = MediaQuery.of(context).size.height * heightFactor;

  return Get.bottomSheet(
    ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if ((bsComponent['title'] ?? '').toString().isNotEmpty) ...[
              Text(
                bsComponent['title'],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sheetWidgets.length,
                itemBuilder: (context, position) {
                  return sheetWidgets[position];
                },
              ),
            ),
          ],
        ),
      ),
    ),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
  );
}
