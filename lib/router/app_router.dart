// lib/router/app_router.dart
// Defines all routes using go_router 14.x with custom page transitions.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// import '../providers/album_provider.dart';
import '../views/albums_view.dart';
import '../views/album_view.dart';
import '../views/album_add_view.dart';
import '../views/tags_view.dart';
import '../views/images_view.dart';
import '../views/image_view.dart';
import '../views/images_selected_view.dart';

// Shared key so ShellRoute keeps the bottom nav bar alive.
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final appRouter = GoRouter(
  initialLocation: '/images',
  routes: [
    ShellRoute(
      navigatorKey: _shellKey,
      builder: (context, state, child) => _ScaffoldShell(child: child),
      routes: [
        // ── Images ────────────────────────────────────────────────────────
        GoRoute(
          path: '/images',
          pageBuilder: (context, state) => _fadePage(
            state,
            const ImagesView(),
          ),
          routes: [
            GoRoute(
              path: 'view/:index',
              parentNavigatorKey: _shellKey,
              pageBuilder: (context, state) {
                final index =
                    int.tryParse(state.pathParameters['index'] ?? '0') ?? 0;
                return _scalePage(state, ImageView(initialIndex: index));
              },
            ),
          ],
        ),

        // ── Albums ─────────────────────────────────────────────────────────
        GoRoute(
          path: '/albums',
          pageBuilder: (context, state) => _fadePage(state, const AlbumsView()),
          routes: [
            GoRoute(
              path: 'add',
              pageBuilder: (context, state) =>
                  _slidePage(state, const AlbumAddView()),
            ),
            GoRoute(
              path: ':id',
              pageBuilder: (context, state) {
                final id = int.parse(state.pathParameters['id']!);
                final editMode =
                    state.uri.queryParameters['edit'] == 'true';
                return _fadePage(
                    state, AlbumView(albumId: id, startInEditMode: editMode));
              },
            ),
          ],
        ),

        // ── Tags ───────────────────────────────────────────────────────────
        GoRoute(
          path: '/tags',
          pageBuilder: (context, state) => _fadePage(state, const TagsView()),
        ),

        // ── Selected images ────────────────────────────────────────────────
        GoRoute(
          path: '/selected',
          pageBuilder: (context, state) =>
              _slidePage(state, const ImagesSelectedView()),
        ),
      ],
    ),
  ],
);

// ── Transition helpers ────────────────────────────────────────────────────────

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (_, animation, __, child) {
      final offset =
          Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeInOut));
      return SlideTransition(position: offset, child: child);
    },
  );
}

CustomTransitionPage<void> _scalePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (_, animation, __, child) {
      final scale = Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut));
      return ScaleTransition(scale: scale, child: child);
    },
  );
}

// ── Shell scaffold with bottom navigation bar ─────────────────────────────────

class _ScaffoldShell extends StatelessWidget {
  final Widget child;
  const _ScaffoldShell({required this.child});

  static const _tabs = [
    (label: 'Photos', icon: Icons.photo_library_outlined,
     activeIcon: Icons.photo_library, path: '/images'),
    (label: 'Albums', icon: Icons.photo_album_outlined,
     activeIcon: Icons.photo_album, path: '/albums'),
    (label: 'Tags', icon: Icons.label_outline,
     activeIcon: Icons.label, path: '/tags'),
    (label: 'Selected', icon: Icons.check_circle_outline,
     activeIcon: Icons.check_circle, path: '/selected'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = _currentIndex(context);
    final selectionCount =
        context.watch<SelectionCountNotifier>().count;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIdx,
        onDestinationSelected: (idx) =>
            context.go(_tabs[idx].path),
        destinations: _tabs.map((t) {
          Widget icon = Icon(t.icon);
          Widget activeIcon = Icon(t.activeIcon);
          if (t.path == '/selected' && selectionCount > 0) {
            activeIcon = Badge(
              label: Text('$selectionCount'),
              child: Icon(t.activeIcon),
            );
            icon = Badge(
              label: Text('$selectionCount'),
              child: Icon(t.icon),
            );
          }
          return NavigationDestination(
            icon: icon,
            selectedIcon: activeIcon,
            label: t.label,
          );
        }).toList(),
      ),
    );
  }
}

/// A tiny ChangeNotifier that the shell listens to for badge updates.
/// Wrap it around MaterialApp and update via SelectionProvider listener.
class SelectionCountNotifier extends ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void update(int count) {
    if (_count != count) {
      _count = count;
      notifyListeners();
    }
  }
}
