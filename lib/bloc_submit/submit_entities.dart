// Collanium 2020
//   Oct 28, 2020 HH

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class SubmitEntity extends Equatable {
  final int
      st; // status 0=generated; 101=finish submitted; 800=uploaded, can be deleted
  final String ss; // ssid
  final String c; // content as json.stringify 1 dimension array
  final String id; // submit id = ss=+timestamp

  final int appVid; // app Vid for field in firestore
  final int t; // transaction time stamp, Event!A
  final String p; // page name, Event!B
  final String c2; // content in Event!C
  final String d; // description
  final String f; // flag
  final String w; // widget type
  final String tb;

  @override
  List<Object> get props => [];
  const SubmitEntity(this.st, this.ss, this.c, this.id, this.appVid, this.t,
      this.p, this.c2, this.d, this.f, this.w, this.tb);

  Map<String, Object> toJson() {
    return {
      "st": st,
      "ss": ss,
      "c": c,
      "id": id,
      "appVid": appVid,
      "t": t,
      "p": p,
      "c2": c2,
      "d": d,
      "f": f,
      "w": w,
      "tb": tb,
    };
  }

  @override
  String toString() {
    return 'Submit Entity{st: $st, ss: $ss, c: $c, id: $id, appVid: $appVid, t: $t, p: $p, c2: $c2, d: $d, f: $f, w: $w, tb: $tb}';
  }

  static SubmitEntity fromJson(Map<String, Object> json) {
    return SubmitEntity(
      json["st"] as int,
      json["ss"] as String,
      json["c"] as String,
      json["id"] as String,
      json["appVid"] as int,
      json["t"] as int,
      json["p"] as String,
      json["c2"] as String,
      json["d"] as String,
      json["f"] as String,
      json["w"] as String,
      json["tb"] as String,
    );
  }

  static SubmitEntity fromSnapshot(DocumentSnapshot snap) {
    return SubmitEntity(
      snap.get('st'),
      snap.get('ss'),
      snap.get('c'),
      snap.get('id'),
      snap.get('appVid'),
      snap.get('t'),
      snap.get('p'),
      snap.get("c2"),
      snap.get("d"),
      snap.get("f"),
      snap.get("w"),
      snap.get("tb"),
    );
  }

  Map<String, Object> toDocument() {
    return {
      "st": st,
      "ss": ss,
      "c": c,
      "id": id,
      "appVid": appVid,
      "t": t,
      "p": p,
      "c2": c2,
      "d": d,
      "f": f,
      "w": w,
      "tb": tb,
    };
  } // end of toDocument

  Map<String, Object> toDocument2() {
    return {
      "t": t,
      "p": p,
      "c": c2,
      "s": 10,
    };
  } // end of toDocument
}
