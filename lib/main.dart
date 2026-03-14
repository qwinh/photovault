// lib/main.dart
// Entry point. Sets up the provider tree, initialises notification service,
// and boots go_router.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/album_provider.dart';
import 'providers/image_provider.dart';
import 'providers/selection_provider.dart';
import 'providers/tag_provider.dart';
import 'router/app_router.dart';
import 'services/notification_service.dart';
import 'views/images_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const PhotoVaultApp());
}

class PhotoVaultApp extends StatelessWidget {
  const PhotoVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlbumProvider()),
        ChangeNotifierProvider(create: (_) => TagProvider()),
        ChangeNotifierProvider(create: (_) => DeviceImageProvider()),
        ChangeNotifierProvider(create: (_) => SelectionProvider()),
        ChangeNotifierProvider(create: (_) => SelectionCountNotifier()),
        ChangeNotifierProvider(create: (_) => FilteredListNotifier()),
      ],
      child: _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  @override
  void initState() {
    super.initState();
    // Keep SelectionCountNotifier in sync with SelectionProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selProv = context.read<SelectionProvider>();
      final countNotifier = context.read<SelectionCountNotifier>();
      selProv.addListener(() => countNotifier.update(selProv.count));
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PhotoVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
