import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'screens/main_shell.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ListitApp());
}

class ListitApp extends StatefulWidget {
  const ListitApp({super.key});

  @override
  State<ListitApp> createState() => _ListitAppState();
}

class _ListitAppState extends State<ListitApp> {
  // The session (JWT + user) and the HTTP client are wired together: the client
  // reads the current token through a closure so it can attach the auth header
  // without owning session state. One of each lives for the app's lifetime.
  final AuthService _auth = AuthService();
  late final ApiService _api = ApiService(getToken: () => _auth.token);

  @override
  void initState() {
    super.initState();
    _auth.bind(_api);
    _auth.restore(); // best-effort restore of a persisted session
  }

  @override
  void dispose() {
    _api.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Listit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MainShell(api: _api, auth: _auth),
    );
  }
}
