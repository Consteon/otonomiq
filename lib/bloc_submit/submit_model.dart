import 'package:meta/meta.dart';
import '../bloc_submit/bloc.dart';

@immutable
class Submit {
  final int st;
  final String ss;
  final String c;
  final String id;
  final int appVid;
  final int t;
  final String p;
  final String c2;
  final String? d; // description
  final String? f; // flag
  final String? w; // widget type
  final String? tb; // table definition string

  const Submit({
    required this.st,
    required this.ss,
    required this.c,
    required this.id,
    required this.appVid,
    required this.t,
    required this.p,
    required this.c2,
    this.d = '',
    this.f = '',
    this.w = '',
    this.tb = '',
  });

  Submit copyWith(
      {int? st,
      String? ss,
      String? c,
      String? id,
      int? appVid,
      int? t,
      String? p,
      String? c2,
      String? d,
      String? f,
      String? w,
      String? tb}) {
    return Submit(
      st: st ?? this.st,
      ss: ss ?? this.ss,
      c: c ?? this.c,
      id: id ?? this.id,
      appVid: appVid ?? this.appVid,
      t: t ?? this.t,
      p: p ?? this.p,
      c2: c2 ?? this.c2,
      d: d ?? this.d,
      f: f ?? this.f,
      w: w ?? this.w,
      tb: tb ?? this.tb,
    );
  }

  @override
  int get hashCode => st.hashCode ^ ss.hashCode ^ c.hashCode ^ id.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Submit &&
          runtimeType == other.runtimeType &&
          st == other.st &&
          ss == other.ss &&
          c == other.c &&
          id == other.id;

  @override
  String toString() {
    return 'Submit{st: $st, ss: $ss, c: $c, id: $id, appVid: $appVid, t: $t, p: $p, ce: $c2, d: $d, f: $f, w: $w, tb: $tb}';
  }

  SubmitEntity toEntity() {
    return SubmitEntity(st, ss, c, id, appVid, t, p, c2, d!, f!, w!, tb!);
  } // end of toEntity

  static Submit fromEntity(SubmitEntity entity) {
    return Submit(
      st: entity.st,
      ss: entity.ss,
      c: entity.c,
      id: entity.id,
      appVid: entity.appVid,
      t: entity.t,
      p: entity.p,
      c2: entity.c2,
      d: entity.d,
      f: entity.f,
      w: entity.w,
      tb: entity.tb,
    );
  }
}
