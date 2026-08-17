import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// The listit.im pages the profile menu links out to (real routes on the site).
class ListitLinks {
  ListitLinks._();
  static const help = 'https://listit.im/help';
  static const contact = 'https://listit.im/contactus';
  static const terms = 'https://listit.im/terms';
  static const privacy = 'https://listit.im/privacypolicy';
  static const dataRequest = 'https://listit.im/data-request';

  static Future<void> open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* nothing we can do if there's no browser */}
  }
}

/// A reusable on/off preferences screen backed by shared_preferences, so the
/// choices persist on the device. Used for both Notifications and Consent.
class TogglePrefsScreen extends StatefulWidget {
  final String title;
  final String? intro;
  final List<TogglePref> prefs;
  const TogglePrefsScreen({
    super.key,
    required this.title,
    this.intro,
    required this.prefs,
  });

  @override
  State<TogglePrefsScreen> createState() => _TogglePrefsScreenState();
}

class TogglePref {
  final String key;
  final String label;
  final String? subtitle;
  final bool defaultOn;
  const TogglePref(this.key, this.label, {this.subtitle, this.defaultOn = true});
}

class _TogglePrefsScreenState extends State<TogglePrefsScreen> {
  final Map<String, bool> _values = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final p in widget.prefs) {
      _values[p.key] = prefs.getBool(p.key) ?? p.defaultOn;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _set(String key, bool v) async {
    setState(() => _values[key] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              children: [
                if (widget.intro != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(widget.intro!,
                        style: const TextStyle(
                            color: AppColors.slate, fontSize: 13.5, height: 1.4)),
                  ),
                const SizedBox(height: 6),
                for (final p in widget.prefs)
                  Container(
                    color: Colors.white,
                    child: SwitchListTile(
                      activeThumbColor: AppColors.primary,
                      title: Text(p.label,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink)),
                      subtitle: p.subtitle == null
                          ? null
                          : Text(p.subtitle!,
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppColors.slate)),
                      value: _values[p.key] ?? p.defaultOn,
                      onChanged: (v) => _set(p.key, v),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Notification preferences (stored on the device; honoured when push lands).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TogglePrefsScreen(
      title: 'Notification Preferences',
      prefs: [
        TogglePref('notif_all', 'Notifications',
            subtitle: 'Turn all notifications on or off'),
        TogglePref('notif_sound', 'Sound',
            subtitle: 'Play a sound when you receive a notification'),
        TogglePref('notif_vibrate', 'Vibrate',
            subtitle: 'Vibrate your device when you receive a notification'),
        TogglePref('notif_led', 'LED Indicator',
            subtitle: 'Flash the LED light when you receive a notification'),
      ],
    );
  }
}

/// Consent / privacy choices (device-level).
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TogglePrefsScreen(
      title: 'Consent options',
      intro:
          'Manage how your activity is used. You can change these at any time.',
      prefs: [
        TogglePref('consent_recommendations', 'Personalised recommendations',
            subtitle: 'Use what you view to suggest listings'),
        TogglePref('consent_analytics', 'Usage analytics',
            subtitle: 'Help improve the app with anonymous usage data'),
        TogglePref('consent_marketing', 'Marketing updates',
            subtitle: 'Occasional news and offers from Listit',
            defaultOn: false),
      ],
    );
  }
}

/// Legal policies - links out to the pages on the website.
class LegalPoliciesScreen extends StatelessWidget {
  const LegalPoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Legal policies')),
      body: ListView(
        children: [
          const SizedBox(height: 6),
          _link(context, Icons.description_outlined, 'Terms & Conditions',
              ListitLinks.terms),
          _link(context, Icons.privacy_tip_outlined, 'Privacy Policy',
              ListitLinks.privacy),
          _link(context, Icons.download_outlined, 'Data request',
              ListitLinks.dataRequest),
        ],
      ),
    );
  }

  Widget _link(
      BuildContext context, IconData icon, String label, String url) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: AppColors.slate),
        title: Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
        trailing: const Icon(Icons.open_in_new_rounded,
            size: 18, color: AppColors.muted),
        onTap: () => ListitLinks.open(url),
      ),
    );
  }
}
