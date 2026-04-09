'use strict';

// ── Push event ────────────────────────────────────────────────
self.addEventListener('push', function (event) {
  var roomName = 'New message';
  var body = 'You have a new message';
  var tag = 'lattice-push';
  var data = {};

  if (event.data) {
    try {
      var payload = event.data.json();
      var notification = payload.notification || {};
      var roomId = notification.room_id;
      var senderName = notification.sender_display_name;
      var counts = notification.counts || {};

      if (notification.room_name) roomName = notification.room_name;
      if (senderName) body = senderName + ': New message';
      if (roomId) tag = roomId;
      data = { roomId: roomId || null, unreadCount: counts.unread || 0 };
    } catch (e) {
      // Parse failed — fall through to show a generic notification.
    }
  }

  event.waitUntil(
    self.registration.showNotification(roomName, {
      body: body,
      icon: 'icons/Icon-192.png',
      tag: tag,
      data: data,
    }).then(function () {
      try {
        if (self.navigator && self.navigator.setAppBadge && data.unreadCount) {
          self.navigator.setAppBadge(data.unreadCount);
        }
      } catch (e) {
        // Badge API not supported — ignore.
      }
    }).catch(function (e) {
      // showNotification failed — log for debugging.
      console.error('[Lattice SW] showNotification failed:', e);
    })
  );
});

// ── Notification click ────────────────────────────────────────
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  try {
    if (self.navigator && self.navigator.clearAppBadge) {
      self.navigator.clearAppBadge();
    }
  } catch (e) {
    // Badge API not supported — ignore.
  }

  var roomId = (event.notification.data || {}).roomId;
  var urlPath = roomId ? '/#/rooms/' + encodeURIComponent(roomId) : '/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        if (client.url.indexOf(self.registration.scope) !== -1) {
          client.postMessage({ type: 'notification_click', roomId: roomId });
          return client.focus();
        }
      }
      return self.clients.openWindow(urlPath);
    })
  );
});

// ── Subscription change ──────────────────────────────────────
self.addEventListener('pushsubscriptionchange', function (event) {
  var options = (event.oldSubscription && event.oldSubscription.options) || {};
  event.waitUntil(
    self.registration.pushManager.subscribe(options)
      .then(function (newSubscription) {
        return self.clients.matchAll({ type: 'window' }).then(function (clientList) {
          for (var i = 0; i < clientList.length; i++) {
            clientList[i].postMessage({
              type: 'pushsubscriptionchange',
              oldEndpoint: event.oldSubscription ? event.oldSubscription.endpoint : null,
              newSubscription: newSubscription.toJSON(),
            });
          }
        });
      })
  );
});

// ── Lifecycle ─────────────────────────────────────────────────
self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});
