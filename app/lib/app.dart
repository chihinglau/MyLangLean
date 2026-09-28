import 'package:flutter/material.dart';

import 'core/app_router.dart';
import 'core/constants.dart';
import 'core/theme/app_theme.dart';

class MyLangLeanApp extends StatelessWidget {
  const MyLangLeanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
