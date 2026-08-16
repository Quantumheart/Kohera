// coverage:ignore-file

import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

// ── WorkerBoot ────────────────────────────────────────────────────
//
// The message sent from the UI isolate to the worker at spawn time.
// All fields must be sendable across isolate boundaries.

class WorkerBoot {
  final SendPort uiPort;
  final RootIsolateToken? token;
  final WorkerHandler Function() handlerFactory;

  const WorkerBoot({
    required this.uiPort,
    required this.handlerFactory,
    this.token,
  });
}

// ── Worker entry point ────────────────────────────────────────────
//
// Must be a top-level function (Isolate.spawn requirement).
// The lifecycle is:
//   1. Initialise platform channels (RootIsolateToken).
//   2. Create a ReceivePort and send its SendPort back to the UI.
//   3. Listen for BackendCall messages, dispatch to the handler.
//   4. Send BackendReply / BackendEvent back via uiPort.
//   5. Exit cleanly when the ReceivePort sends null (closed by the UI).

// Isolate.spawn requires a void entry point; the body runs an async loop.
// ignore: avoid_void_async
void workerEntry(WorkerBoot boot) async {
  // 1. Platform channels on the worker (skipped in tests)
  if (boot.token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(boot.token!);
  }

  // 2. Create worker ReceivePort, send SendPort back to UI
  final workerReceivePort = ReceivePort();
  boot.uiPort.send(workerReceivePort.sendPort);

  // 3. Instantiate the handler on the worker
  final handler = boot.handlerFactory();

  // 4. Wire the emit callback: handler → uiPort
  void emit(BackendEvent event) {
    boot.uiPort.send(encodeMessage(event));
  }

  // 5. Listen for calls from the UI
  await for (final raw in workerReceivePort) {
    if (raw == null) break; // ReceivePort closed → shutdown

    final message = decodeMessage(raw as Map<String, dynamic>);
    if (message is! BackendCall) continue; // ignore stray replies/events

    try {
      final result = await handler.handle(message, emit);
      boot.uiPort.send(encodeMessage(
        BackendReply(
          id: message.id,
          ok: result.ok,
          result: result.data,
          error: result.error,
        ),
      ));
    } catch (e, s) {
      boot.uiPort.send(encodeMessage(
        BackendReply(
          id: message.id,
          ok: false,
          error: BackendError(
            code: 'worker_exception',
            message: e.toString(),
            stackTrace: s.toString(),
          ),
        ),
      ));
    }
  }

  // 6. Clean up
  await handler.dispose();
  workerReceivePort.close();
  Isolate.exit();
}
