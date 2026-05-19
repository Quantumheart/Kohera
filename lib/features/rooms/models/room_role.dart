/// Abstraction for Matrix room roles based on power levels.
///
/// This module provides a type-safe way to work with room roles instead of
/// raw power-level integers. It handles conversions between roles and levels,
/// enforces Matrix hierarchy rules, and provides human-readable descriptions.
library;

import 'package:flutter/foundation.dart';

/// Represents a role in a Matrix room with associated power level.
///
/// Roles are mapped to standard power levels:
/// - [admin] = 100
/// - [moderator] = 50
/// - [member] = 0
/// - [custom] = any integer not matching the presets
///
/// This enum abstracts away raw power-level integers while maintaining
/// compatibility with the Matrix protocol.
sealed class RoomRole {
  const RoomRole();

  /// Creates a [RoomRole] from a power level integer.
  ///
  /// Maps standard levels (100 → admin, 50 → moderator, 0 → member)
  /// to their presets, and creates a [custom] variant for other values.
  factory RoomRole.fromPowerLevel(int level) {
    return switch (level) {
      100 => const RoomRole.admin(),
      50 => const RoomRole.moderator(),
      0 => const RoomRole.member(),
      _ => RoomRole.custom(level),
    };
  }

  /// Admin role with full room control (power level 100).
  const factory RoomRole.admin() = _AdminRole;

  /// Moderator role with limited administrative privileges (power level 50).
  const factory RoomRole.moderator() = _ModeratorRole;

  /// Member role with basic permissions (power level 0).
  const factory RoomRole.member() = _MemberRole;

  /// Custom role with non-standard power level.
  const factory RoomRole.custom(int value) = _CustomRole;

  /// Converts this role to its corresponding power level integer.
  int toPowerLevel() => switch (this) {
        _AdminRole() => 100,
        _ModeratorRole() => 50,
        _MemberRole() => 0,
        _CustomRole(:final value) => value,
      };

  /// Human-readable label for this role.
  ///
  /// Examples: "Admin", "Moderator", "Member", "Custom (45)"
  String get label => switch (this) {
        _AdminRole() => 'Admin',
        _ModeratorRole() => 'Moderator',
        _MemberRole() => 'Member',
        _CustomRole(:final value) => 'Custom ($value)',
      };

  /// One-line description of this role's capabilities.
  String get description => map(
        admin: (_) => 'Full room control and management',
        moderator: (_) => 'Can moderate members and pin messages',
        member: (_) => 'Can send messages and react',
        custom: (_) => 'Custom power level',
      );

  /// Determines if a user with [ownLevel] can assign [target] role to a user
  /// currently at [targetCurrentLevel].
  ///
  /// Enforces Matrix hierarchy rules:
  /// 1. Can only assign roles ≤ own power level
  /// 2. Can only modify users strictly below own power level
  ///
  /// Examples:
  /// - Admin (100) can assign any role to users below them ✓
  /// - Moderator (50) can only assign Member (0) to users below them ✓
  /// - Moderator (50) cannot demote another Moderator ✗
  /// - Member (0) cannot assign any role ✗
  static bool canAssignRole({
    required RoomRole target,
    required int ownLevel,
    required int targetCurrentLevel,
  }) {
    final targetLevel = target.toPowerLevel();

    // Can only assign roles at or below own level
    if (targetLevel > ownLevel) {
      return false;
    }

    // Can only modify users strictly below own level
    if (targetCurrentLevel >= ownLevel) {
      return false;
    }

    return true;
  }

  /// Pattern matches on the role type.
  ///
  /// This is the primary way to handle role-specific logic.
  T map<T>({
    required T Function(RoomRole) admin,
    required T Function(RoomRole) moderator,
    required T Function(RoomRole) member,
    required T Function(RoomRole) custom,
  }) =>
      switch (this) {
        _AdminRole _ => admin(this),
        _ModeratorRole _ => moderator(this),
        _MemberRole _ => member(this),
        _CustomRole _ => custom(this),
      };

  /// Pattern matches with null-coalescing for convenience.
  T maybeMap<T>({
    required T orElse,
    T Function(RoomRole)? admin,
    T Function(RoomRole)? moderator,
    T Function(RoomRole)? member,
    T Function(RoomRole)? custom,
  }) =>
      map(
        admin: admin != null ? (role) => admin(role) : (_) => orElse,
        moderator: moderator != null ? (role) => moderator(role) : (_) => orElse,
        member: member != null ? (role) => member(role) : (_) => orElse,
        custom: custom != null ? (role) => custom(role) : (_) => orElse,
      );

  @override
  String toString() => label;
}

@immutable
final class _AdminRole extends RoomRole {
  const _AdminRole();

  @override
  bool operator ==(Object other) => other is _AdminRole;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
final class _ModeratorRole extends RoomRole {
  const _ModeratorRole();

  @override
  bool operator ==(Object other) => other is _ModeratorRole;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
final class _MemberRole extends RoomRole {
  const _MemberRole();

  @override
  bool operator ==(Object other) => other is _MemberRole;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
final class _CustomRole extends RoomRole {
  final int value;

  const _CustomRole(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CustomRole &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}
