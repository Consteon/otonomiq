import 'package:flutter/material.dart';
import '../api.dart';
import '../global.dart';

/// Shared shell for the home-menu icon buttons — `horizontal_icon` children
/// (Goto, GpsSend, AttendQrGpsSelfie, FtzChecker, disabledIcon), their single
/// modes, and `buildGridList` (`vgr`/`hgr`). One place owns the card look;
/// callers keep their own onTap.
///
/// Grid cells are screen-derived (4 fixed columns, see the `horizontal_icon`
/// and `hgr` branches), so the card fills its tight cell and centers its
/// content; in single mode (unbounded height) the column hugs content.
Widget menuIconCard({
  required String imageUrl,
  required String label,
  required double fontSize,
  void Function()? onTap,
}) {
  final BorderRadius radius = BorderRadius.circular(16);
  // Sheet-config fontSize varies per section (14–16); a menu-card label is a
  // caption, so normalize into the 11–12 band for a uniform type scale
  // across ABSEN / Laporan / Formulir.
  final double labelSize = fontSize.clamp(11.0, 12.0);
  return Container(
    margin: const EdgeInsets.all(5),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        // same hairline as the time_presence stat chips
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                height: 36,
                child: displayImage(
                  imageUrl: imageUrl.isEmpty ? defaultImage : imageUrl,
                  cached: true,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              // Flexible: on very narrow screens the 2-line label shrinks
              // instead of overflowing the fixed grid cell
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: labelSize,
                    height: 1.15,
                    letterSpacing: 0.1,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF2A3240),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
