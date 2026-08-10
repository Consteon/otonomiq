// lib/screen_session_entries.dart
//
// Test-callable aggregate. Calls every widget's registerScreenSession() so
// the full matrix is populated without pumping widgets. NOT the primary
// mechanism -- each widget's access path calls ensure() independently.

import 'widget/admin_create_task_support.dart';
import 'widget/approver_sticky_bar.dart';
import 'widget/asset_stock_list.dart';
import 'widget/custody_count_list.dart';
import 'widget/custody_event_submit.dart';
import 'widget/custody_reveal.dart';
import 'widget/customer_outstanding_list.dart';
import 'widget/driver_home_support.dart';
import 'widget/executor_designate_card.dart';
import 'widget/group_picker.dart';
import 'widget/item_card_detail.dart';
import 'widget/item_execution_list.dart';
import 'widget/item_execution_submit.dart';
import 'widget/list_action_card.dart';
import 'widget/nfc_reader.dart';
import 'widget/nota_create_submit.dart';
import 'widget/payout_list.dart';
import 'widget/signature_pad.dart';
import 'widget/table_picker.dart';
import 'widget/task_create_submit.dart';
import 'widget/task_feed_list.dart';
import 'widget/task_item_builder.dart';
import 'widget/task_manifest_list.dart';
import 'widget/whatsapp_send.dart';

void registerAllScreenSessionEntries() {
  CustodyCountList.registerScreenSession();
  CustodyReveal.registerScreenSession();
  ItemExecutionList.registerScreenSession();
  ItemExecutionSubmit.registerScreenSession();
  WhatsAppSend.registerScreenSession();
  PayoutList.registerScreenSession();
  ListActionCard.registerScreenSession();
  GroupPicker.registerScreenSession();
  ExecutorDesignateCard.registerScreenSession();
  NfcReader.registerScreenSession();
  SignaturePad.registerScreenSession();
  ApproverStickyBar.registerScreenSession();
  registerDriverHomeScreenSession();
  TaskManifestList.registerScreenSession();
  CustodyEventSubmit.registerScreenSession();
  TaskItemBuilder.registerScreenSession();
  TaskCreateSubmit.registerScreenSession();
  NotaCreateSubmit.registerScreenSession();
  TaskFeedList.registerScreenSession();
  CustomerOutstandingList.registerScreenSession();
  AssetStockList.registerScreenSession();
  TablePicker.registerScreenSession();
  AdminCreateTaskSupport.registerScreenSession();
  ItemCardDetail.registerScreenSession();
}
