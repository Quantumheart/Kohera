import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/rooms/models/kohera_room_permissions.dart';
import 'package:kohera/features/rooms/widgets/admin_settings_section.dart';
KoheraRoomPermissions _perms({
  String roomId = '!r:e.com',
  String displayName = 'Test Room',
  String topic = 'A topic',
  bool canEditName = true,
  bool canEditTopic = true,
  bool canEnableEncryption = true,
  bool isEncrypted = false,
  bool canChangePowerLevels = false,
  bool canChangeJoinRules = false,
}) =>
    KoheraRoomPermissions(
      roomId: roomId,
      displayName: displayName,
      topic: topic,
      canEditName: canEditName,
      canEditTopic: canEditTopic,
      canEditAvatar: false,
      canInvite: false,
      canChangeJoinRules: canChangeJoinRules,
      canChangePowerLevels: canChangePowerLevels,
      canEnableEncryption: canEnableEncryption,
      isEncrypted: isEncrypted,
      powerLevelsContent: const {},
      participants: const [],
      myPowerLevel: 100,
    );

Widget _wrap(AdminSettingsSection child) => MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

void main() {
  group('AdminSettingsSection', () {
    testWidgets('shows room name and topic fields', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADMIN SETTINGS'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Room name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Topic'), findsOneWidget);
    });

    testWidgets('pre-fills name and topic from permissions', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(displayName: 'My Room', topic: 'My topic'),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Room name'),
      );
      expect(nameField.controller?.text, 'My Room');

      final topicField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Topic'),
      );
      expect(topicField.controller?.text, 'My topic');
    });

    testWidgets('saving name calls onSaveName', (tester) async {
      String? savedName;
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (name) async => savedName = name,
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room name'),
        'New Name',
      );
      await tester.tap(find.byIcon(KIcons.checkRounded).first);
      await tester.pumpAndSettle();

      expect(savedName, 'New Name');
    });

    testWidgets('saving topic calls onSaveTopic', (tester) async {
      String? savedTopic;
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (_) async {},
            onSaveTopic: (topic) async => savedTopic = topic,
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Topic'),
        'New topic',
      );
      await tester.tap(find.byIcon(KIcons.checkRounded).at(1));
      await tester.pumpAndSettle();

      expect(savedTopic, 'New topic');
    });

    testWidgets('shows enable encryption button for unencrypted room',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enable encryption'), findsOneWidget);
    });

    testWidgets('hides encryption button for encrypted room', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(isEncrypted: true, canEnableEncryption: false),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enable encryption'), findsNothing);
    });

    testWidgets('enable encryption shows confirmation dialog', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Enable').last);
      await tester.pumpAndSettle();

      expect(find.text('Enable encryption?'), findsOneWidget);
      expect(find.textContaining('irreversible'), findsOneWidget);
    });

    testWidgets('confirming encryption calls onEnableEncryption',
        (tester) async {
      var encryptionCalled = false;
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async => encryptionCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Enable').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Enable').last);
      await tester.pumpAndSettle();

      expect(encryptionCalled, isTrue);
    });

    testWidgets('shows error on save failure', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (_) async => throw Exception('Server error'),
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room name'),
        'Failing Name',
      );
      await tester.tap(find.byIcon(KIcons.checkRounded).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('shows success message after save', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room name'),
        'Updated Name',
      );
      await tester.tap(find.byIcon(KIcons.checkRounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Room name updated'), findsOneWidget);
    });

    testWidgets('hides name field when lacking permission', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AdminSettingsSection(
            permissions: _perms(canEditName: false),
            onSaveName: (_) async {},
            onSaveTopic: (_) async {},
            onEnableEncryption: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Room name'), findsNothing);
    });
  });
}
