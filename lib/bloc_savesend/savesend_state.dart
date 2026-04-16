import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
abstract class SavesendState extends Equatable {
  const SavesendState();
  @override
  List<Object> get props => [];
}
//abstract class SavesendState extends Equatable {
//  final String rebuildPage;
//
//  SavesendState(this.rebuildPage, [List props = const[]])
//  : super([rebuildPage]..addAll(props));
//}

class RebuildPage extends SavesendState {
  const RebuildPage(String rebuildPage);// : super(rebuildPage);

  @override
  String toString() => 'Rebuild($RebuildPage)';
//  String toString() => 'Rebuild($rebuildPage)';

}
