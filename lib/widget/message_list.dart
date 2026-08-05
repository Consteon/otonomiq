import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api.dart';
import '../global.dart';
import '../notification/bloc.dart';
import '../widget/link_widget.dart';
import '../widget/notif_ui.dart';

class MessageList extends StatefulWidget {
  final String? title;
  final String? profilePic;

  const MessageList({required Key key, this.title, this.profilePic})
    : super(key: key);

  @override
  _MessageListState createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  @override
  void initState() {
    super.initState();
    //    BlocProvider.of<MessageBloc>(context).dispatch(LoadMessage());
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final title = (widget.title != null && widget.title!.trim().isNotEmpty)
        ? widget.title!.trim()
        : 'Message';
    return BlocBuilder<MessageBloc, MessageState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: notifBg,
          appBar: AppBar(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                rootThis.setState(() {
                  rootThis.byPass = 1;
                  rootThis.byPassWidget = const NotificationList();
                });
              },
            ),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                notifAvatar(title, widget.profilePic, 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: Builder(
            builder: (context) {
              if (state is MessageLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is! MessageLoaded) {
                return const SizedBox.shrink();
              }
              final theList = state.messages;
              if (theList.isEmpty) {
                return notifEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Belum ada pesan',
                  subtitle: 'Pesan pada percakapan ini akan muncul di sini',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                itemCount: theList.length,
                itemBuilder: (context, index) {
                  final msg = theList[index];
                  final incoming = msg.inbox == true;
                  final needAction =
                      msg.inbox == true &&
                      msg.dataPayload != null &&
                      msg.status != 101;
                  final ms = notifNormalizeMs(msg.receivedTime);
                  final time = notifClockTime(ms);

                  // Day-separator chip above the first message of each calendar
                  // day (label is absolute, so it's correct in either sort order).
                  Widget? daySep;
                  if (ms != null) {
                    final label = notifDayLabel(ms);
                    final prevMs = index > 0
                        ? notifNormalizeMs(theList[index - 1].receivedTime)
                        : null;
                    if (prevMs == null || notifDayLabel(prevMs) != label) {
                      daySep = notifDaySeparator(label);
                    }
                  }

                  final bubble = InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setStatus(msg.messageId, 101);
                      // if msg.route is not null then display
                      if (msg.route != null && msg.route != '') {
                        if (linkElement[msg.route] == null) {
                          // put page not found error in message_list if route is not present
                        } else {
                          var myRoute = msg.route;
                          //myRoute = home; // delete this line when page is available
                          routeStack.push(myRoute!); // push new page
                          List<Widget> newElementList = reloadPage(
                            myRoute,
                          ); // reload current page
                          rootThis.setState(() {
                            rootThis.byPass = 0;
                            rootThis.pageName = myRoute;
                            rootThis.pageElements = newElementList;
                          });
                        }
                      }
                    }, // end onTap()
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.76,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: incoming ? Colors.white : primary,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(incoming ? 4 : 16),
                          bottomRight: Radius.circular(incoming ? 16 : 4),
                        ),
                        border: incoming
                            ? Border.all(color: notifBorder)
                            : null,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            msg.displayMessage ?? '-',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.3,
                              color: incoming ? notifTextStrong : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (time.isNotEmpty)
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: incoming
                                        ? notifTextMuted
                                        : Colors.white70,
                                  ),
                                ),
                              if (needAction) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.fiber_manual_record,
                                  size: 10,
                                  color: msg.status! > 0
                                      ? Colors.green
                                      : Colors.redAccent,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );

                  final row = Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: incoming
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.end,
                      children: <Widget>[Flexible(child: bubble)],
                    ),
                  );
                  if (daySep == null) return row;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[daySep, row],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
