import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const ListitApp());
}

class ListitApp extends StatefulWidget {
  const ListitApp({super.key});

  @override
  State<ListitApp> createState() => _ListitAppState();
}

class _ListitAppState extends State<ListitApp> {
  // One shared client for the app's lifetime - keeps the HTTP connection pool
  // and image cache warm across screens.
  final ApiService _api = ApiService();

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Listit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: HomeScreen(api: _api),
    );
  }
}
