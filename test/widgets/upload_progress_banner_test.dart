import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/chat/widgets/upload_progress_banner.dart';
void main() {
  Widget buildBanner({
    required UploadState state,
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: UploadProgressBanner(
          state: state,
          onCancel: onCancel ?? () {},
        ),
      ),
    );
  }

  group('UploadProgressBanner', () {
    testWidgets('shows uploading state with spinner and filename',
        (tester) async {
      await tester.pumpWidget(buildBanner(
        state: const UploadState(
          status: UploadStatus.uploading,
          fileName: 'photo.jpg',
        ),
      ),);

      expect(find.text('Uploading…'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(KIcons.errorOutlineRounded), findsNothing);
    });

    testWidgets('shows error state with error icon', (tester) async {
      await tester.pumpWidget(buildBanner(
        state: const UploadState(
          status: UploadStatus.error,
          fileName: 'document.pdf',
          error: 'Network error',
        ),
      ),);

      expect(find.text('Upload failed'), findsOneWidget);
      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.byIcon(KIcons.errorOutlineRounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('cancel button fires callback', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(buildBanner(
        state: const UploadState(
          status: UploadStatus.uploading,
          fileName: 'file.txt',
        ),
        onCancel: () => cancelled = true,
      ),);

      await tester.tap(find.byIcon(KIcons.closeRounded));
      expect(cancelled, isTrue);
    });
  });
}
