import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Regression for account-switch stale data.
///
/// On switch, the active-account provider subtree remounts, but go_router's
/// navigators are GlobalKey-backed and survive that remount — and go_router
/// does not re-run a page builder on a same-location refresh. A screen sitting
/// on the room list when the account switches is therefore never rebuilt, and
/// its create-once controller keeps the *previous* account's repository.
///
/// The composition root fixes this by rebuilding the router on switch (see
/// `main.dart`): a fresh router gives fresh navigators, so the whole screen
/// tree tears down and rebinds to the switched-in repositories — with no
/// account-switch logic leaking into the (account-agnostic) screens.
class _Repo {
  const _Repo(this.account);
  final String account;
}

class _Controller {
  _Controller(this.account);
  final String account;
}

/// An account-agnostic screen: create-once controller, no dependency on the
/// account, no keying. Exactly the shape of the real screens.
class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    return Provider<_Controller>(
      create: (ctx) => _Controller(ctx.read<_Repo>().account),
      child: Builder(
        builder: (ctx) => Text(
          ctx.read<_Controller>().account,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}

GoRouter _makeRouter() => GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) => child,
          routes: [GoRoute(path: '/', builder: (context, state) => const _Screen())],
        ),
      ],
    );

/// Mirrors the composition root: the provider subtree is keyed by account, and
/// [rebuildRouterOnSwitch] controls whether a fresh router (and thus fresh
/// navigators) is used when the account changes.
Widget _harness({
  required ValueNotifier<_Repo> active,
  required bool rebuildRouterOnSwitch,
}) {
  var router = _makeRouter();
  if (rebuildRouterOnSwitch) {
    active.addListener(() => router = _makeRouter());
  }

  return ValueListenableBuilder<_Repo>(
    valueListenable: active,
    builder: (context, repo, _) => MultiProvider(
      key: ValueKey('providers-${repo.account}'),
      providers: [Provider<_Repo>.value(value: repo)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  testWidgets(
    'rebuilding the router on switch rebinds an account-agnostic screen',
    (tester) async {
      final active = ValueNotifier<_Repo>(const _Repo('a'));
      addTearDown(active.dispose);

      await tester.pumpWidget(
        _harness(active: active, rebuildRouterOnSwitch: true),
      );
      expect(find.text('a'), findsOneWidget);

      active.value = const _Repo('b');
      await tester.pumpAndSettle();

      expect(find.text('b'), findsOneWidget);
      expect(find.text('a'), findsNothing);
    },
  );

  testWidgets(
    'reusing the router across a switch leaves the screen stale (the bug)',
    (tester) async {
      final active = ValueNotifier<_Repo>(const _Repo('a'));
      addTearDown(active.dispose);

      await tester.pumpWidget(
        _harness(active: active, rebuildRouterOnSwitch: false),
      );
      expect(find.text('a'), findsOneWidget);

      active.value = const _Repo('b');
      await tester.pumpAndSettle();

      // The GlobalKey'd navigator survives the provider remount, so the
      // create-once controller is preserved and still shows account 'a'.
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsNothing);
    },
  );
}
