import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../notification/bloc.dart';
import '../global.dart';
import '../widget/link_widget.dart';

class NotificationList extends StatefulWidget {
  const NotificationList({super.key});

  @override
  _NotificationListState createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  @override
  Widget build(BuildContext context) {
    const dotDiameter = 24.0;
    return BlocBuilder<NotificationBloc, NotificationState>(
      // cubit:NotificationBloc,
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).primaryColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                var pgName = routeStack.get(); // get current page
                List<Widget> newElementList =
                    reloadPage(pgName); // reload current page
                rootThis.setState(() {
                  rootThis.byPass = 0;
                  rootThis.pageName = pgName;
                  rootThis.pageElements = newElementList;
                });
              },
            ),
            actions: <Widget>[
              (state is NotificationLoaded && state.unReadNumber > 0)
                  ? TxtDot(
                      key: UniqueKey(),
                      txt: '${state.unReadNumber}',
                      color: Colors.redAccent,
                      diameter: dotDiameter,
                    )
                  : Container(),
              Container(
                width: 20,
              ),
            ],
            title: const Text(
              'Notification',
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: Container(
            child: Builder(
              builder: (context) {
                Widget nListResult;
                if (NotificationState is NotificationLoading) {
                  nListResult = const Center(
                    child: CircularProgressIndicator(),
                  );
                } else if (state is NotificationLoaded) {
                  final theList = state.notifications;
                  nListResult = ListView.builder(
                    itemCount: theList.length,
                    itemBuilder: (context, index) {
                      final note = theList[index];
                      return Card(
                        child: ListTile(
                          onTap: () {
                            firestoreMsg =
                                firestoreIO + "/" + note.vid + "/msg";
                            firestoreNotif = firestoreIO + "/" + note.vid;
                            BlocProvider.of<MessageBloc>(context)
                                .add(LoadMessage());
                            rootThis.setState(() {
                              rootThis.byPass = 2;
                              rootThis.byPassWidget = MessageList(
                                key: UniqueKey(),
                                title: note.name!,
                                profilePic: note.profilePicture!,
                              );
                              rootThis.touch = !rootThis.touch;
                            });
                          },
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundImage: NetworkImage(note.profilePicture ??
                                'https://firebasestorage.googleapis.com/v0/b/collanium1-4babc.appspot.com/o/link_app%2Fdefaultpp.PNG?alt=media&token=a5c20f19-a914-4d62-bcaf-585cd92be94d'),
                          ),
                          // title: Text(note.name ?? note.vid),
                          // subtitle: Text(note.lastMessage ?? '-'),
                          title: Text(note.lastMessage ?? '-'),
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              // Text('${displayDateTime(note.lastMessageTime)}'),
                              // Container(
                              //   height: 8,
                              //   width: 1,
                              // ),
                              note.unRead! <= 0
                                  ? const SizedBox(
                                      height: dotDiameter - 4,
                                      width: 1,
                                    )
                                  : TxtDot(
                                      key: UniqueKey(),
                                      txt: '${note.unRead}',
                                      color: Colors.redAccent,
                                      diameter: dotDiameter - 4,
                                    )
                            ],
                          ),
                        ),
                      );
                    },
                  );
                } else {
                  nListResult = Container();
                }
                return nListResult;
              },
            ),
          ),
        );
      },
    );
  }
}
