import 'package:kohera/data/models/kohera_thread_summary.dart';

int totalThreadUnread(List<KoheraThreadSummary> summaries) =>
    summaries.fold(0, (sum, s) => sum + s.unreadCount);
