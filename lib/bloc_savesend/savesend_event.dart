import 'package:meta/meta.dart';
import 'package:equatable/equatable.dart';

@immutable
abstract class SavesendEvent extends Equatable {
  const SavesendEvent();
  @override
  List<Object> get props => [];
}
//abstract class SavesendEvent extends Equatable {
//  SavesendEvent([List props = const []]) : super(props);
//}

class Update extends SavesendEvent {
  final String rebuildPage;

  const Update({required this.rebuildPage});// : super([rebuildPage]);

  @override
  String toString() => "Update(rebuildPage: $rebuildPage)";
}
