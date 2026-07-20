import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/features/rooms/screens/room_details_screen.dart';

/// Minimal GoRouter used by room-details tests so [RoomDetailsScreen] can
/// navigate (back, leave-to-home) faithfully. Routes `/rooms/:roomId/details`
/// to the screen over a placeholder home and parent room route.
GoRouter buildRoomDetailsTestRouter({required String roomId}) {
  return GoRouter(
    initialLocation: '/rooms/$roomId/details',
    routes: [
      GoRoute(
        path: '/',
        name: Routes.home,
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/rooms/:${RouteParams.roomId}',
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        routes: [
          GoRoute(
            path: RouteSegments.roomDetails,
            name: Routes.roomDetails,
            builder: (_, state) => RoomDetailsScreen(
              roomId: state.pathParameters[RouteParams.roomId]!,
            ),
          ),
        ],
      ),
    ],
  );
}
