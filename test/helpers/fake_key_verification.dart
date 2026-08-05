import 'dart:typed_data';

import 'package:matrix/encryption.dart';
import 'package:mockito/mockito.dart';

/// A fake [KeyVerification] for testing. We cannot use Mockito because
/// [onUpdate] and [state] are plain fields, not methods.
///
/// Extracted from key_verification_dialog_test.dart for reuse.
class FakeKeyVerification extends Fake implements KeyVerification {
  @override
  void Function()? onUpdate;

  @override
  KeyVerificationState state;

  @override
  String? canceledReason;

  @override
  String? canceledCode;

  @override
  bool canceled;

  List<KeyVerificationEmoji> _sasEmojis = [];

  @override
  List<KeyVerificationEmoji> get sasEmojis => _sasEmojis;

  List<int> _sasNumbers = [];

  @override
  List<int> get sasNumbers => _sasNumbers;

  List<String> _sasTypes = [];

  @override
  List<String> get sasTypes => _sasTypes;

  @override
  List<String> possibleMethods = [];

  @override
  QRCode? qrCode;

  bool cancelCalled = false;
  bool acceptVerificationCalled = false;
  bool acceptSasCalled = false;
  bool rejectSasCalled = false;
  String? continueVerificationMethod;

  FakeKeyVerification({
    this.state = KeyVerificationState.waitingAccept,
    this.canceledReason,
    this.canceledCode,
    this.canceled = false,
  });

  void setSasEmojis(List<KeyVerificationEmoji> emojis) {
    _sasEmojis = emojis;
  }

  void setSasNumbers(List<int> numbers) {
    _sasNumbers = numbers;
  }

  void setSasTypes(List<String> types) {
    _sasTypes = types;
  }

  void simulateStateChange(KeyVerificationState newState) {
    state = newState;
    onUpdate?.call();
  }

  @override
  Future<void> cancel([String? code, bool quiet = false]) async {
    cancelCalled = true;
    canceled = true;
    state = KeyVerificationState.error;
  }

  @override
  Future<void> acceptVerification() async {
    acceptVerificationCalled = true;
  }

  @override
  Future<void> acceptSas() async {
    acceptSasCalled = true;
  }

  @override
  Future<void> rejectSas() async {
    rejectSasCalled = true;
  }

  @override
  Future<void> acceptQRScanConfirmation() async {}

  @override
  Future<void> continueVerification(
    String type, {
    Uint8List? qrDataRawBytes,
  }) async {
    continueVerificationMethod = type;
  }

  @override
  Future<void> start() async {}

  @override
  bool get isDone =>
      canceled ||
      {KeyVerificationState.error, KeyVerificationState.done}.contains(state);
}