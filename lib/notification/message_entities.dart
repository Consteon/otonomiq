// Collanium 2019
//   Oct 27, 2019 HS

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class MessageEntity extends Equatable {
  final String dp; // message to human, should be displayed
  final String dt; // data to be processed by app. Json formatted
  final int tr; // received in vid inbox. seconds from unix time
  final bool im; // true = incoming message; false = out coming message
  final String id; // firebase message id. Searchable in collectionGroup('msg')
  final int
      st; // (in=True, 0=received,1=read but not processed, 101 = display & data processed),
  final String rt; // route to display when tapped
  // (in=False,0=not processed, 51=sent to server, 52=received in other vid,
  // 53=read but not processed, 102 = read & processed)

  // MessageEntity();
  @override
  List<Object> get props => [];
  const MessageEntity(this.dp, this.dt, this.tr, this.im, this.id, this.st, this.rt);

  Map<String, Object> toJson() {
    return {
      "dp": dp,
      "dt": dt,
      "tr": tr,
      "im": im,
      "id": id,
      "st": st,
      "rt": rt,
    };
  }

  @override
  String toString() {
    return 'Message Entity{dp: $dp, dt: $dt, tr: $tr, im: $im, id: $id, st: $st, rt: $rt}';
  }

  static MessageEntity fromJson(Map<String, Object> json) {
    return MessageEntity(
      json["dp"] as String,
      json["dt"] as String,
      json["tr"] as int,
      json["im"] as bool,
      json["id"] as String,
      json["st"] as int,
      json["rt"] as String,
    );
  }

  static MessageEntity fromSnapshot(DocumentSnapshot snap) {
    return MessageEntity(
      snap.get('dp'),
      snap.get('dt'),
      snap.get('tr'),
      snap.get('im'),
      snap.get('id'),
      snap.get('st'),
      snap.get('rt'),
    );
  }

  Map<String, Object> toDocument() {
    return {
      "dp": dp,
      "dt": dt,
      "tr": tr,
      "im": im,
      "id": id,
      "st": st,
      "rt": rt,
    };
  }
}
