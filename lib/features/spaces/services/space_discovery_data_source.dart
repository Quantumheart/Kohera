import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/kohera_auth_exception.dart';
import 'package:kohera/data/models/kohera_public_room.dart';
import 'package:kohera/data/models/kohera_space_hierarchy.dart';
import 'package:kohera/data/repositories/space_repository.dart';

abstract class SpaceDiscoveryDataSource {
  Future<KoheraPublicRoomsPage> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    KoheraPublicRoomFilter? filter,
  });

  Future<KoheraSpaceHierarchy> getSpaceHierarchy(
    String roomId, {
    int? maxDepth,
    bool? suggestedOnly,
  });

  /// Joins [roomIdOrAlias] and waits until the resulting room is in the
  /// local sync. Returns the joined room id.
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via});

  /// True if the user is already a `join` member of [roomId].
  bool isMember(String roomId);

  /// True when [roomId] resolves to a space (room type `m.space`). Used
  /// by the dialog after a join to decide whether to select the space
  /// and pop, or remain in the preview.
  bool isSpace(String roomId);

  /// Room IDs whose membership changed in each sync (join, leave, invite).
  Stream<Set<String>> get membershipChanges;
}

class LiveSpaceDiscoveryDataSource implements SpaceDiscoveryDataSource {
  LiveSpaceDiscoveryDataSource(this._spaces);

  final SpaceRepository _spaces;

  @override
  Future<KoheraPublicRoomsPage> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    KoheraPublicRoomFilter? filter,
  }) =>
      _spaces.queryPublicRooms(
        limit: limit,
        since: since,
        server: server,
        filter: filter,
      );

  @override
  Future<KoheraSpaceHierarchy> getSpaceHierarchy(
    String roomId, {
    int? maxDepth,
    bool? suggestedOnly,
  }) =>
      _spaces.getSpaceHierarchy(
        roomId,
        maxDepth: maxDepth,
        suggestedOnly: suggestedOnly,
      );

  @override
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via}) =>
      _spaces.joinRoomAndWait(roomIdOrAlias, via: via);

  @override
  bool isMember(String roomId) => _spaces.isJoinedRoom(roomId);

  @override
  bool isSpace(String roomId) => _spaces.isSpaceRoom(roomId);

  @override
  Stream<Set<String>> get membershipChanges => _spaces.membershipChanges;
}

// ── Fake fixture ────────────────────────────────────────────────

class FakeSpaceDiscoveryDataSource implements SpaceDiscoveryDataSource {
  FakeSpaceDiscoveryDataSource({
    this.delay = const Duration(milliseconds: 400),
    this.failHierarchyForRoomId = '!fake-broken:example.org',
    this.forbiddenHierarchyForRoomId,
    this.failingServers = const {},
  });

  final Duration delay;
  final String? failHierarchyForRoomId;
  final String? forbiddenHierarchyForRoomId;
  final Set<String> failingServers;
  final Set<String> _joined = {};

  /// Test hook: emit membership-changed room IDs to listeners.
  final StreamController<Set<String>> membershipChangesController =
      StreamController<Set<String>>.broadcast();

  static final List<KoheraPublicRoom> _allSpaces = _generateSpaces();
  static final List<KoheraPublicRoom> _matrixOrgSpaces =
      _generateMatrixOrgSpaces();
  static final Map<String, KoheraSpaceHierarchy> _hierarchies =
      _generateHierarchies();
  static final Set<String> _spaceIds = {
    ..._allSpaces.map((c) => c.roomId),
    ..._matrixOrgSpaces.map((c) => c.roomId),
    '!fake-subspace-tech:example.org',
    '!fake-subspace-deep:example.org',
  };

  @override
  Future<KoheraPublicRoomsPage> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    KoheraPublicRoomFilter? filter,
  }) async {
    await Future<void>.delayed(delay);
    if (server != null && failingServers.contains(server)) {
      throw const KoheraAuthException(
        'Federation denied by server',
        errcode: 'M_FORBIDDEN',
      );
    }
    final source = switch (server) {
      null => _allSpaces,
      'matrix.org' => _matrixOrgSpaces,
      _ => const <KoheraPublicRoom>[],
    };
    final term = filter?.genericSearchTerm?.trim().toLowerCase();
    final filtered = (term == null || term.isEmpty)
        ? source
        : source.where((c) {
            final hay = [
              c.name,
              c.topic,
              c.canonicalAlias,
            ].whereType<String>().map((s) => s.toLowerCase());
            return hay.any((s) => s.contains(term));
          }).toList();
    final pageSize = limit ?? 20;
    final start = since == null ? 0 : int.tryParse(since) ?? 0;
    final end = math.min(start + pageSize, filtered.length);
    final chunk =
        start >= filtered.length ? <KoheraPublicRoom>[] : filtered.sublist(start, end);
    final nextBatch = end < filtered.length ? end.toString() : null;
    return KoheraPublicRoomsPage(
      items: chunk,
      nextBatch: nextBatch,
      totalRoomCountEstimate: filtered.length,
    );
  }

  @override
  Future<KoheraSpaceHierarchy> getSpaceHierarchy(
    String roomId, {
    int? maxDepth,
    bool? suggestedOnly,
  }) async {
    await Future<void>.delayed(delay);
    if (roomId == forbiddenHierarchyForRoomId) {
      throw const KoheraAuthException(
        'Preview not allowed',
        errcode: 'M_FORBIDDEN',
      );
    }
    if (roomId == failHierarchyForRoomId) {
      throw Exception('Fake hierarchy failure for $roomId');
    }
    final hit = _hierarchies[roomId];
    if (hit != null) return hit;
    return _hierarchyForUnknownSpace(roomId);
  }

  // ── Fixture generation ───────────────────────────────────────

  static List<KoheraPublicRoom> _generateSpaces() {
    const themes = [
      ['Quantum HQ', 'Default home for quantum-matrix users.'],
      ['Linux', 'All things Linux: distros, kernels, tooling.'],
      ['Self-Hosted', 'Run your own services. Helpful tips and rants.'],
      ['Flutter Devs', 'Cross-platform UI talk, package showcases.'],
      ['Homelab', 'Racks, hypervisors, weird DIY networking.'],
      ['Photography', 'Gear, technique, critique.'],
      ['Music Lounge', 'Sharing what we listen to.'],
      ['Cooking', 'Recipes, kitchen disasters, sourdough.'],
      ['Books', 'Fiction, nonfiction, recommendations.'],
      ['Movies & TV', null],
      ['Gaming', 'Discussion across platforms and genres.'],
      ['Indie Web', 'Personal sites, RSS, the open web.'],
      ['Privacy', 'Threat models, OPSEC, tooling.'],
      ['Cycling', 'Routes, mechanicals, n+1.'],
      ['Coffee', null],
      ['Open Source', 'Contributing, maintaining, governance.'],
      ['News & Current Events', 'Mostly civil discussion.'],
      ['Travel', 'Trip reports and planning.'],
      ['Languages', 'Polyglots and learners.'],
      ['Dev Tools', 'Editors, terminals, CLIs.'],
      ['Astro', null],
      ['Fediverse', 'Mastodon, Lemmy, the rest.'],
      ['Crypto', 'Cryptography, not coins.'],
      ['Math', 'From arithmetic to algebraic topology.'],
      ['Birding', 'eBird logs, field marks.'],
      ['Woodworking', null],
      ['3D Printing', 'Prints, slicers, filament.'],
      ['DIY Electronics', 'Hand-soldered fun.'],
      ['Mech Keyboards', 'Switches, layouts, group buys.'],
      ['Retro Gaming', null],
      ['Movies (Foreign)', 'World cinema appreciation.'],
      ['Whisky', 'Tasting notes and bottle hunts.'],
      ['Tea', null],
      ['Hiking', 'Trails and trip reports.'],
      ['Climbing', 'Routes, gyms, gear.'],
      ['Running', 'Training plans and race reports.'],
      ['Yoga', null],
      ['Stoicism', 'Practical philosophy.'],
      ['Productivity', 'Systems and habits.'],
      ['Note-taking', 'Org, Obsidian, Logseq, paper.'],
      ['Esoteric Programming', null],
      ['Functional Programming', 'Haskell, OCaml, Rust folks too.'],
      ['Rust', 'Systems programming with rustc.'],
      ['Go', 'Goroutines, channels, build tags.'],
      ['Zig', null],
      ['Game Dev', 'Engines, art, design.'],
      ['Pixel Art', 'Aseprite, palettes, animation.'],
      ['Synthesizers', 'Modular, soft, vintage.'],
      ['Electronic Music', null],
      ['Classical Music', 'Performances, recordings, scores.'],
      ['Jazz', 'Standards and adventurous corners.'],
      ['Plants', 'Houseplants and gardens.'],
      ['Aquariums', 'Freshwater, planted, reef.'],
      ['Star Trek', null],
      ['Star Wars', null],
      ['Anime', 'Currently airing and classics.'],
      ['Tabletop RPG', 'D&D, indie systems, GM advice.'],
      ['Board Games', 'Heavy euros to filler.'],
      ['Puzzle Hunts', null],
      ['Math Puzzles', 'Riddles and Olympiad problems.'],
    ];
    final rng = math.Random(42);
    return [
      for (var i = 0; i < themes.length; i++)
        KoheraPublicRoom(
          guestCanJoin: false,
          memberCount: 5 + rng.nextInt(11000),
          roomId: '!fake-space-$i:example.org',
          worldReadable: true,
          name: themes[i][0],
          topic: themes[i][1],
          canonicalAlias:
              '#${themes[i][0]!.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}'
              ':example.org',
          roomType: 'm.space',
        ),
    ];
  }

  static List<KoheraPublicRoom> _generateMatrixOrgSpaces() {
    const themes = [
      ['matrix.org Lounge', 'General chat for matrix.org users.'],
      ['Synapse', 'Discussion of the Synapse homeserver.'],
      ['Element', 'Element client community.'],
      ['Matrix Spec', 'Spec process and proposals.'],
      ['Bridges', 'IRC, XMPP, Discord, Slack bridges.'],
      ['Federation', 'Cross-server topics.'],
      ['New to Matrix', 'Newcomer questions and pointers.'],
    ];
    final rng = math.Random(7);
    return [
      for (var i = 0; i < themes.length; i++)
        KoheraPublicRoom(
          guestCanJoin: false,
          memberCount: 200 + rng.nextInt(40000),
          roomId: '!fake-mxorg-$i:matrix.org',
          worldReadable: true,
          name: themes[i][0],
          topic: themes[i][1],
          canonicalAlias:
              '#${themes[i][0].toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}'
              ':matrix.org',
          roomType: 'm.space',
        ),
    ];
  }

  static Map<String, KoheraSpaceHierarchy> _generateHierarchies() {
    final out = <String, KoheraSpaceHierarchy>{};

    KoheraSpaceHierarchyChunk chunk({
      required String roomId,
      required String name,
      String? topic,
      int members = 50,
      String? roomType,
      String? alias,
      List<KoheraSpaceChildState> childrenState = const [],
    }) {
      return KoheraSpaceHierarchyChunk(
        guestCanJoin: false,
        memberCount: members,
        roomId: roomId,
        worldReadable: true,
        childrenState: childrenState,
        name: name,
        topic: topic,
        canonicalAlias: alias,
        roomType: roomType,
      );
    }

    // Quantum HQ — rich hierarchy with a subspace.
    out['!fake-space-0:example.org'] = KoheraSpaceHierarchy(
      rooms: [
        chunk(
          roomId: '!fake-space-0:example.org',
          name: 'Quantum HQ',
          topic: 'Default home for quantum-matrix users.',
          members: 1247,
          roomType: 'm.space',
          alias: '#quantum-hq:example.org',
          childrenState: const [
            KoheraSpaceChildState(
              type: 'm.space.child',
              stateKey: '!fake-room-lounge:example.org',
              isSuggested: true,
              order: 'a',
            ),
            KoheraSpaceChildState(
              type: 'm.space.child',
              stateKey: '!fake-room-offtopic:example.org',
              order: 'b',
            ),
            KoheraSpaceChildState(
              type: 'm.space.child',
              stateKey: '!fake-room-devtalk:example.org',
              isSuggested: true,
              order: 'c',
            ),
            KoheraSpaceChildState(
              type: 'm.space.child',
              stateKey: '!fake-subspace-tech:example.org',
            ),
            KoheraSpaceChildState(
              type: 'm.space.child',
              stateKey: '!fake-room-announcements:example.org',
              order: 'd',
            ),
          ],
        ),
        chunk(
          roomId: '!fake-room-lounge:example.org',
          name: 'lounge',
          topic: 'Casual hangout.',
          members: 412,
          alias: '#lounge:example.org',
        ),
        chunk(
          roomId: '!fake-room-offtopic:example.org',
          name: 'offtopic',
          members: 138,
          alias: '#offtopic:example.org',
        ),
        chunk(
          roomId: '!fake-room-devtalk:example.org',
          name: 'dev-talk',
          topic: 'Technical chatter.',
          members: 201,
          alias: '#dev-talk:example.org',
        ),
        chunk(
          roomId: '!fake-subspace-tech:example.org',
          name: 'Tech',
          topic: 'Subspace for technical rooms.',
          members: 320,
          roomType: 'm.space',
          alias: '#tech:example.org',
        ),
        chunk(
          roomId: '!fake-room-announcements:example.org',
          name: 'announcements',
          members: 87,
          alias: '#announcements:example.org',
        ),
      ],
    );

    // Tech subspace under Quantum HQ.
    out['!fake-subspace-tech:example.org'] = KoheraSpaceHierarchy(
      rooms: [
        chunk(
          roomId: '!fake-subspace-tech:example.org',
          name: 'Tech',
          topic: 'Subspace for technical rooms.',
          members: 320,
          roomType: 'm.space',
          alias: '#tech:example.org',
        ),
        chunk(
          roomId: '!fake-room-linux-tech:example.org',
          name: 'linux',
          members: 144,
          alias: '#linux-tech:example.org',
        ),
        chunk(
          roomId: '!fake-room-homelab:example.org',
          name: 'homelab',
          members: 98,
          alias: '#homelab-tech:example.org',
        ),
        chunk(
          roomId: '!fake-subspace-deep:example.org',
          name: 'Deep dive',
          topic: 'Nested subspace for testing recursion.',
          members: 12,
          roomType: 'm.space',
          alias: '#deep:example.org',
        ),
      ],
    );

    // Deep nested subspace.
    out['!fake-subspace-deep:example.org'] = KoheraSpaceHierarchy(
      rooms: [
        chunk(
          roomId: '!fake-subspace-deep:example.org',
          name: 'Deep dive',
          topic: 'Nested subspace for testing recursion.',
          members: 12,
          roomType: 'm.space',
          alias: '#deep:example.org',
        ),
        chunk(
          roomId: '!fake-room-deeper:example.org',
          name: 'deeper',
          members: 4,
          alias: '#deeper:example.org',
        ),
      ],
    );

    // Empty space — preview shows "No rooms yet".
    out['!fake-space-9:example.org'] = KoheraSpaceHierarchy(
      rooms: [
        chunk(
          roomId: '!fake-space-9:example.org',
          name: 'Movies & TV',
          members: 88,
          roomType: 'm.space',
          alias: '#movies-tv:example.org',
        ),
      ],
    );

    return out;
  }

  @override
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via}) async {
    await Future<void>.delayed(delay);
    var id = roomIdOrAlias;
    if (id.startsWith('#')) {
      final match = _allSpaces.firstWhere(
        (s) => s.canonicalAlias == id,
        orElse: () => _allSpaces.first,
      );
      id = match.roomId;
    }
    _joined.add(id);
    return id;
  }

  @override
  bool isMember(String roomId) => _joined.contains(roomId);

  @override
  bool isSpace(String roomId) => _spaceIds.contains(roomId);

  @override
  Stream<Set<String>> get membershipChanges =>
      membershipChangesController.stream;

  KoheraSpaceHierarchy _hierarchyForUnknownSpace(String roomId) {
    final spaceMatch = _allSpaces.firstWhere(
      (s) => s.roomId == roomId,
      orElse: () => _allSpaces.first,
    );
    return KoheraSpaceHierarchy(
      rooms: [
        KoheraSpaceHierarchyChunk(
          guestCanJoin: false,
          memberCount: spaceMatch.memberCount,
          roomId: spaceMatch.roomId,
          worldReadable: true,
          name: spaceMatch.name,
          topic: spaceMatch.topic,
          canonicalAlias: spaceMatch.canonicalAlias,
          roomType: 'm.space',
        ),
        KoheraSpaceHierarchyChunk(
          guestCanJoin: false,
          memberCount: 64,
          roomId: '!fake-room-${roomId.hashCode}-a:example.org',
          worldReadable: true,
          name: 'general',
        ),
        KoheraSpaceHierarchyChunk(
          guestCanJoin: false,
          memberCount: 21,
          roomId: '!fake-room-${roomId.hashCode}-b:example.org',
          worldReadable: true,
          name: 'meta',
        ),
      ],
    );
  }
}

// ── Selector ────────────────────────────────────────────────────

/// Build-time flag. Run with
/// `flutter run --dart-define=KOHERA_FAKE_DISCOVERY=true` to swap the
/// live data source for canned data.
const bool kFakeSpaceDiscovery = bool.fromEnvironment(
  'KOHERA_FAKE_DISCOVERY',
);

SpaceDiscoveryDataSource defaultSpaceDiscoveryDataSource(
  SpaceRepository spaces,
) {
  if (kFakeSpaceDiscovery) {
    debugPrint('[Kohera] SpaceDiscovery: using fake data source');
    return FakeSpaceDiscoveryDataSource();
  }
  return LiveSpaceDiscoveryDataSource(spaces);
}
