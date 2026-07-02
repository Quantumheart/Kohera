import 'package:kohera/shared/models/kohera_user_summary.dart';

/// A read receipt with a pre-computed [KoheraUserSummary] and timestamp.
///
/// Produced by the conversion boundary (`buildReceiptMap` in
/// `read_receipts.dart`) from the SDK `Receipt` type. Consumed by
/// `ReadReceiptsRow` and `showReadersSheet` — neither of which touch the
/// Matrix SDK directly.
class KoheraReadReceipt {
  const KoheraReadReceipt({required this.user, required this.time});

  final KoheraUserSummary user;
  final DateTime time;
}
