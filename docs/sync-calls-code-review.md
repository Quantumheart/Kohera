# Code Review: Sync Call Fixes

## Scope

Three fixes were implemented to reduce redundant `/sync` HTTP requests:

- **Fix 1** (`sync_service.dart`): Skip `abortSync()` on web — prevents orphaned HTTP requests by not clearing the SDK's `_currentSync` guard.
- **Fix 2** (`client_manager.dart`): Only sync the active account — pauses inactive accounts after init and on account switch.
- **Fix 3** (`matrix_service.dart`): Debounce lifecycle-driven sync pause by 3 seconds — prevents abort/restart churn from brief tab switches on web.

## Findings

### 1. HIGH — Lifecycle observer on all accounts undoes Fix 2

**Files:** `matrix_service.dart` `_activateSession()`, `didChangeAppLifecycleState()`

Every `MatrixService` registers itself as a `WidgetsBindingObserver` in `_activateSession()`:

```dart
Future<void> _activateSession() async {
    auth.activateRestoredSession();
    if (!_lifecycleObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);  // ← every account
      _lifecycleObserverRegistered = true;
    }
    if (_isAppForegrounded()) {
      _startForegroundSync();
    }
}
```

`_activateSession()` is called for **all** accounts during `ClientManager.init()` (each `MatrixService.init()` → `_restoreSession()` → `_activateSession()`). This means every account receives `didChangeAppLifecycleState`.

When the app transitions to `resumed`, **all** accounts call:

```dart
case AppLifecycleState.resumed:
    _pauseDebounce?.cancel();
    _pauseDebounce = null;
    sync.resume();           // ← resumes ALL accounts, not just active
    _startForegroundSync();
    presence.setOnline();
```

`sync.resume()` sets `_client.backgroundSync = true`, which restarts the SDK sync loop. This un-pauses inactive accounts that were paused by Fix 2's `init()` or `setActiveAccount()`.

**Result:** After any background→foreground cycle, all accounts sync again. Fix 2 only takes effect:
- During the initial startup settling period (first 30–40s after `init()`)
- Immediately after an account switch (until the next lifecycle cycle)

**Reproduction:**
1. App starts with 2 accounts → Fix 2 pauses account 1 → only account 0 syncs
2. User switches to another tab → all accounts pause (debounced)
3. User returns → all accounts resume → **both accounts sync again**
4. User switches account → Fix 2 pauses old → only new active syncs (until next lifecycle cycle)

**Recommended fix:** Only the active account should act on lifecycle `resumed`. Options:
- (a) Only the active account registers a lifecycle observer; `ClientManager` registers/unregisters observers on account switch.
- (b) Add an `isActiveAccount` flag to `MatrixService`; `didChangeAppLifecycleState(resumed)` checks it before calling `sync.resume()` and `_startForegroundSync()`.
- (c) Move lifecycle management out of `MatrixService` entirely into a single observer in `ClientManager` that only resumes the active account.

Option (b) is the smallest change:

```dart
// matrix_service.dart
bool _isActiveAccount = true; // set by ClientManager
set isActiveAccount(bool value) {
  _isActiveAccount = value;
  if (!value) unawaited(sync.pause());
  else sync.resume();
}

// didChangeAppLifecycleState:
case AppLifecycleState.resumed:
    _pauseDebounce?.cancel();
    _pauseDebounce = null;
    if (_isActiveAccount) {
      sync.resume();
      _startForegroundSync();
      presence.setOnline();
    }
```

```dart
// client_manager.dart — setActiveAccount:
void setActiveAccount(int index) {
    if (index < 0 || index >= _services.length) return;
    if (index == _activeIndex) return;
    _services[_activeIndex].isActiveAccount = false;
    _activeIndex = index;
    _services[index].isActiveAccount = true;
    notifyListeners();
}
```

### 2. MEDIUM — `pause()` is a no-op when `_syncing` is false

**File:** `sync_service.dart`

```dart
Future<void> pause() async {
    if (!_syncing) return;      // ← returns early if startSync() was never called
    _client.backgroundSync = false;
    if (!kIsWeb) {
      await _client.abortSync();
    }
}
```

`_syncing` is only set to `true` by `SyncService.startSync()`, which is called from `_startForegroundSync()` (when the app is foregrounded). The SDK's `Client.init()` starts the sync loop independently of `startSync()` — `_backgroundSync` defaults to `true` and `init()` calls `_sync()`.

If the app starts in the background:
1. Each account's SDK `init()` starts the sync loop (`_backgroundSync = true`)
2. `_activateSession()` defers `_startForegroundSync()` because the app isn't foregrounded
3. `_syncing` remains `false` for all accounts
4. Fix 2's `init()` calls `pause()` on inactive accounts → **no-op** because `_syncing` is false
5. All accounts' SDK sync loops continue running

Fix 2 doesn't pause inactive accounts when the app starts in the background. When the app later comes to foreground, `_startForegroundSync()` is called for all accounts (because all accounts are lifecycle observers — see Finding 1), setting `_syncing = true`. From that point, `pause()` works, but all accounts are already syncing.

**Recommended fix:** `pause()` should set `backgroundSync = false` regardless of `_syncing`, since the SDK sync loop can run without `startSync()` being called:

```dart
Future<void> pause() async {
    _client.backgroundSync = false;
    if (!kIsWeb) {
      await _client.abortSync();
    }
}
```

This is safe — if the SDK loop isn't running, `backgroundSync = false` is a no-op. If it is running, the loop stops after the current sync completes.

### 3. MEDIUM — `resume()` is a no-op when `_syncing` is false

**File:** `sync_service.dart`

```dart
void resume() {
    if (_disposed || !_syncing) return;  // ← returns early if startSync() was never called
    _client.backgroundSync = true;
}
```

Even if Finding 2 is fixed (pause works without `_syncing`), `resume()` still checks `_syncing`. If an inactive account was paused (backgroundSync = false) but `_syncing` is false (app started in background), then:
- `setActiveAccount()` calls `resume()` on the new active account → no-op (`_syncing` is false)
- The SDK sync loop stays stopped
- The account doesn't start syncing until `_startForegroundSync()` is called (which requires the lifecycle observer to fire `resumed`)

If the app is already foregrounded when the account switch happens, the lifecycle observer won't fire `resumed` again, so the account stays unsynced.

**Recommended fix:** `resume()` should restart the sync loop regardless of `_syncing`, or `setActiveAccount()` should call `startSync()` instead of `resume()` for accounts that haven't started syncing yet. The cleanest approach ties into the Finding 1 fix — only the active account's lifecycle observer fires, and it calls `startSync()` if sync hasn't been started, or `resume()` if it has.

### 4. LOW — `_pauseDebounce` not cancelled on logout

**File:** `matrix_service.dart` `_onAuthChanged()`

When the user logs out, `_onAuthChanged()` fires and removes the lifecycle observer:

```dart
} else {
    ...
    sync.cancelSyncSub();
    ...
    _foregroundSyncStarted = false;
    if (_lifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverRegistered = false;
    }
}
```

But `_pauseDebounce` is not cancelled. If a `hidden`/`paused` event fired shortly before logout (setting the 3-second debounce timer), the timer fires after logout. It calls `sync.pause()`, which is a no-op because `cancelSyncSub()` set `_syncing = false`. Harmless, but the timer should be cancelled for cleanliness.

**Recommended fix:** Add `_pauseDebounce?.cancel()` to the logout branch of `_onAuthChanged()`:

```dart
} else {
    _pauseDebounce?.cancel();
    unawaited(_loginStateSub?.cancel());
    ...
}
```

### 5. LOW — `cancelSyncSub()` doesn't stop the SDK sync loop (pre-existing)

**File:** `sync_service.dart`

```dart
void cancelSyncSub() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    _syncing = false;
}
```

`cancelSyncSub()` cancels the stream subscription and sets `_syncing = false`, but doesn't set `_client.backgroundSync = false` or call `abortSync()`. The SDK sync loop continues running until `Client.dispose()` calls `abortSync()`.

This is a pre-existing issue, not introduced by these fixes. The window between `cancelSyncSub()` (called in `_onAuthChanged` on logout) and `Client.dispose()` (called from `removeService()`) has the SDK sync loop running without Kohera listening to the stream. The sync responses are processed by the SDK but not acted upon by Kohera.

**Not a regression**, but worth noting for completeness.

### 6. INFO — Double-resume guard in `signOut()` → `removeService()`

**File:** `client_manager.dart`

`signOut()` calls `_services[_activeIndex].sync.resume()` when the active account is being signed out. Then it calls `removeService()`, which checks `wasActive = (index == _activeIndex)`. Since `signOut()` already changed `_activeIndex`, `wasActive` is `false`, so `removeService()` doesn't call `resume()` again. No double-resume. Verified correct.

### 7. INFO — `setActiveAccount()` early-return for same index

**File:** `client_manager.dart`

```dart
void setActiveAccount(int index) {
    if (index < 0 || index >= _services.length) return;
    if (index == _activeIndex) return;  // ← new guard
    ...
}
```

The new `if (index == _activeIndex) return;` guard prevents pausing and immediately resuming the same account. This is correct and prevents a no-op pause/resume cycle. The existing test "switches active service and notifies listeners" passes with this guard because it switches to a different index. No regression.

## Summary

| # | Severity | Finding | Fix Introduced |
|---|----------|---------|----------------|
| 1 | HIGH | All accounts resume sync on app foreground, undoing Fix 2 | Fix 2 |
| 2 | MEDIUM | `pause()` no-op when `_syncing` is false (background start) | Fix 2 |
| 3 | MEDIUM | `resume()` no-op when `_syncing` is false (can't restart paused account) | Fix 2 |
| 4 | LOW | `_pauseDebounce` not cancelled on logout | Fix 3 |
| 5 | LOW | `cancelSyncSub()` doesn't stop SDK loop (pre-existing) | None |
| 6 | INFO | `signOut()` → `removeService()` has no double-resume | Fix 2 |
| 7 | INFO | `setActiveAccount()` same-index guard is correct | Fix 2 |

Finding 1 is the most significant — it means Fix 2 only works between `init()` and the first lifecycle cycle, or immediately after an account switch. The recommended fix (adding an `isActiveAccount` flag to `MatrixService`) would make Fix 2 robust across lifecycle cycles. Findings 2 and 3 are edge cases that only manifest when the app starts in the background; fixing Finding 1 would largely address them as well since only the active account would receive `resume()`.

## Notification impact analysis (Finding 1)

Finding 1 does **not** affect notification delivery. Two independent paths deliver notifications:

### Push notifications (all platforms)

Push notifications are entirely independent of the sync loop. The homeserver sends push events to a push gateway (UnifiedPush on Android, APNs on iOS, Web Push on web), which delivers them to the device. The app processes the push payload via `PushService._onMessage()` (Android), `ApnsPushService` (iOS), or the service worker (web) — none of which depend on `client.onSync.stream` or `backgroundSync` being true.

Pausing an inactive account's sync loop does not stop its pusher registration. The homeserver still sends push notifications for that account. The push notification is processed using `client.getOneRoomEvent()` (a direct HTTP call), not the sync loop.

### Sync-driven notifications (active account only)

`NotificationService` listens to `matrixService.client.onSync.stream`, but it is only created for the **active** account. `NotificationLifecycleObserver` in `main.dart` receives `widget.matrixService` (the active account's service). When the active account changes, `didUpdateWidget` disposes the old `NotificationService` and creates a new one for the new active account.

Inactive accounts' sync events are never processed for OS notifications, even if they are syncing (Finding 1). The extra sync calls from Finding 1 waste network resources but do not produce duplicate notifications.

### Conclusion

Finding 1 is a resource efficiency issue, not a notification correctness issue. Users receive notifications correctly regardless of whether inactive accounts are syncing.

## Unawaited call analysis

The fixes introduce `unawaited()` calls in two distinct contexts. After review, most were eliminated by making methods properly async. Two remain, each for a different reason:

### Eliminated: `commitPendingService()` and `addService()`

Originally both used `unawaited(oldActive.sync.pause())`. On review, neither needed to be fire-and-forget:

- `commitPendingService()` was `void` but all three call sites (`login_controller.dart:83`, `login_controller.dart:151`, `registration_controller.dart:234`) are inside `async` methods. Changed to `Future<void>` and all callers now `await` it. The old account's sync is fully stopped before the UI transitions.
- `addService()` was already `async` — there was no excuse for `unawaited`. Now properly awaits `oldActive.sync.pause()`.

### Remaining: `unawaited(oldActive.sync.pause())` in `setActiveAccount()`

`setActiveAccount()` is `void` because it's called from `onTap` callbacks (`account_switcher.dart:45`, `space_rail.dart:589`), which are `VoidCallback?` = `void Function()`. Making it `Future<void>` would just move the `unawaited` to the call site — Flutter's `onTap` ignores the returned future regardless.

Mitigated by reordering: the new account is resumed and the UI is updated via `notifyListeners()` **before** the old account's pause fires. The old account's `pause()` sets `backgroundSync = false` as its first line (synchronous), so the SDK loop stops immediately even though `abortSync()` (native) completes asynchronously. The fire-and-forget is after all critical work is done.

### Remaining: `unawaited(sync.pause())` in debounce timer callback

`Timer` callbacks are `void Function()` by API contract — there is no way to return a `Future` from a timer callback. `unawaited()` is the only correct pattern here. The timer either fires 3 seconds after the tab is hidden (correct behavior — pause sync) or is cancelled by a `resumed` event before it fires (correct behavior — sync continues). If logout happened in the interim, `cancelSyncSub()` set `_syncing = false`, making `pause()` a no-op.