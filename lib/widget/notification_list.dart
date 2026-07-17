import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../global.dart';
import '../notification/bloc.dart';
import '../widget/link_widget.dart';
import '../widget/notif_ui.dart';

class NotificationList extends StatefulWidget {
  const NotificationList({super.key});

  @override
  _NotificationListState createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  @override
  void initState() {
    super.initState();
    // Re-subscribe to the CURRENT firestoreIO path. The boot-time
    // LoadNotification (main.dart) bound the pre-login default collection;
    // on warm/auto start it is never re-dispatched (login-success re-fire
    // only happens on a fresh login), so without this the stream watches the
    // wrong path and the inbox shows empty even though the bridge wrote docs.
    BlocProvider.of<NotificationBloc>(context).add(LoadNotification());
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return BlocBuilder<NotificationBloc, NotificationState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: notifBg,
          appBar: AppBar(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                var pgName = routeStack.get(); // get current page
                List<Widget> newElementList = reloadPage(
                  pgName,
                ); // reload current page
                rootThis.setState(() {
                  rootThis.byPass = 0;
                  rootThis.pageName = pgName;
                  rootThis.pageElements = newElementList;
                });
              },
            ),
            title: const Text(
              'Notification',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: <Widget>[
              if (state is NotificationLoaded && state.unReadNumber > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${state.unReadNumber} baru',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Builder(
            builder: (context) {
              if (state is NotificationLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is! NotificationLoaded) {
                return const SizedBox.shrink();
              }
              final theList = state.notifications;
              if (theList.isEmpty) {
                return notifEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Belum ada notifikasi',
                  subtitle: 'Notifikasi yang masuk akan muncul di sini',
                );
              }
              return ListView.separated(
                itemCount: theList.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 82,
                  color: notifBorder,
                ),
                itemBuilder: (context, index) {
                  final note = theList[index];
                  final unread = (note.unRead ?? 0) > 0;
                  final name =
                      (note.name != null && note.name!.trim().isNotEmpty)
                      ? note.name!.trim()
                      : (note.vid ?? 'Pesan');
                  final preview = note.lastMessage ?? '';
                  final time = notifRelTime(note.lastMessageTime);
                  return InkWell(
                    onTap: () {
                      firestoreMsg = firestoreIO + "/" + note.vid + "/msg";
                      firestoreNotif = firestoreIO + "/" + note.vid;
                      BlocProvider.of<MessageBloc>(context).add(LoadMessage());
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
                    child: Container(
                      color: unread ? notifUnreadTint : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          notifAvatar(name, note.profilePicture, 26),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: notifTextStrong,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.2,
                                    color: unread
                                        ? notifTextStrong
                                        : notifTextMuted,
                                    fontWeight: unread
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                time,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: unread ? primary : notifTextMuted,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 7),
                              unread
                                  ? notifCountPill('${note.unRead}')
                                  : const SizedBox(height: 20),
                            ],
                          ),
                        ],
                      ),
                    ),
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
