import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../global.dart';
import '../notification/bloc.dart';
import '../widget/link_widget.dart';

import '../api.dart';

class MessageList extends StatefulWidget {
  final String? title;
  final String? profilePic;

  const MessageList(
      {required Key key, this.title, this.profilePic})
      : super(key: key);

  @override
  _MessageListState createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  late MessageBloc _messageBloc;

  @override
  void initState() {
    super.initState();
//    BlocProvider.of<MessageBloc>(context).dispatch(LoadMessage());
  }

  @override
  Widget build(BuildContext context) {
    const dotDiameter = 24.0;
    return BlocBuilder<MessageBloc, MessageState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                rootThis.setState(() {
                  rootThis.byPass = 1;
                  rootThis.byPassWidget = const NotificationList();
                });
              },
            ),

//            actions: <Widget>[
//              (state is NotificationLoaded && state.unReadNumber > 0)
//                  ? TxtDot(
//                txt: '${state.unReadNumber}',
//                color: Colors.redAccent,
//                diameter: dotDiameter,
//              )
//                  : Container(),
//              Container(
//                width: 20,
//              ),
//            ],
//            title: Text(widget.title ?? 'Message'),
            title: Row(
//              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                CircleAvatar(
                  backgroundImage: NetworkImage(widget.profilePic
                      ?? 'https://firebasestorage.googleapis.com/v0/b/collanium1-4babc.appspot.com/o/link_app%2Fdefaultpp.PNG?alt=media&token=a5c20f19-a914-4d62-bcaf-585cd92be94d'
                      ),
                ),
                Container(
                  width: 8,
                ),
                Text(
                  widget.title ?? 'Message',
                ),
              ],
            ),
          ),
          body: Container(
            child: Builder(
              builder: (context) {
                Widget nListResult;
                if (state is MessageLoading) {
                  nListResult = const Center(
                    child: CircularProgressIndicator(),
                  );
                } else if (state is MessageLoaded) {
                  final theList = state.messages;
                  nListResult = ListView.builder(
                    itemCount: theList.length,
                    itemBuilder: (context, index) {
                      final msg = theList[index];
                      bool needAction = false;
                      if (msg.inbox == true &&
                          msg.dataPayload != null &&
                          msg.status != 101) {
                        needAction = true;
                      }
                      return SizedBox(
                        width: 250,
                        child: Column(
                          crossAxisAlignment: msg.inbox == true
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.end,
                          children: <Widget>[
                            SizedBox(
                              width: 350,
                              child: Card(
                                color: msg.inbox == true
                                    ? Colors.white
                                    : Colors.amberAccent,
                                child: ListTile(
                                  onTap: () {
                                    setStatus(msg.messageId, 101);
                                    // if msg.route is not null then display
                                    if (msg.route != null && msg.route != '') {
                                      if (linkElement[msg.route] == null) {
                                        // TODO put page not found error in message_list if route is not present
                                      } else {
                                        var myRoute = msg.route;
                                        //myRoute = home; // delete this line when page is available
                                        routeStack
                                            .push(myRoute!); // push new page
                                        List<Widget> newElementList =
                                            reloadPage(
                                                myRoute); // reload current page
                                        rootThis.setState(() {
                                          rootThis.byPass = 0;
                                          rootThis.pageName = myRoute;
                                          rootThis.pageElements =
                                              newElementList;
                                        });
                                      }
                                    }

                                    var a = index;
                                    var c = msg;
                                    var b = a;
                                  }, // end onTap()
//                          leading: CircleAvatar(
//                            radius: 32,
//                            backgroundImage: NetworkImage(note.profilePicture ??
//                                'https://firebasestorage.googleapis.com/v0/b/collanium1-4babc.appspot.com/o/link_app%2Fdefaultpp.PNG?alt=media&token=a5c20f19-a914-4d62-bcaf-585cd92be94d'),
//                          ),
                                  title: Text(msg.displayMessage ?? '-'),
                                  // subtitle: Text(
                                  //     '${displayDateTime(msg.receivedTime)}' ??
                                  //         '-'),
                                  trailing: needAction
                                      ? Icon(
                                          Icons.fiber_manual_record,
                                          color: msg.status! > 0
                                              ? Colors.green
                                              : Colors.red,
                                        )
                                      : const SizedBox(
                                          width: 0,
                                          height: 0,
                                        ),
                                ),
                              ),
                            ),
                          ],
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
