import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/network_photo.dart';

/// Complete / edit your profile: a photo and your home town. Shown right after
/// a new member verifies (onboarding = true) to nudge them to finish setting
/// up, and reachable any time from the Profile tab.
class EditProfileScreen extends StatefulWidget {
  final AuthService auth;
  final ApiService api;
  final bool onboarding;

  const EditProfileScreen({
    super.key,
    required this.auth,
    required this.api,
    this.onboarding = false,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

// Same town list the Sell flow uses, so a seller's profile town and their ad
// town line up.
const List<String> _imTowns = [
  'Douglas', 'Onchan', 'Ramsey', 'Peel', 'Castletown', 'Port Erin',
  'Port St Mary', 'Ballasalla', 'Laxey', 'Kirk Michael', 'Ballaugh',
  'Sulby', 'Andreas', 'Foxdale', 'Colby', 'Crosby', 'Glen Vine', 'Santon',
];

class _EditProfileScreenState extends State<EditProfileScreen> {
  String? _town;
  String? _pickedAvatarUrl; // freshly uploaded URL — only this gets sent
  String? _displayAvatar; // what the preview shows (current or just picked)
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = widget.auth.user;
    if (u?.location != null && _imTowns.contains(u!.location)) _town = u.location;
    _displayAvatar = u?.avatar;
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    XFile? x;
    try {
      x = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
    } catch (_) {}
    if (x == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await widget.api.uploadPhoto(File(x.path));
      if (!mounted) return;
      setState(() {
        _pickedAvatarUrl = url;
        _displayAvatar = url;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not upload the photo. Try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_pickedAvatarUrl == null && _town == null) {
      Navigator.of(context).pop(true); // nothing to change
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api
          .updateBasicProfile(imageUrl: _pickedAvatarUrl, location: _town);
      await widget.auth.refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: AppColors.success,
        ));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.auth.user;
    final initials = u?.initials ?? '?';
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Set up your profile' : 'Edit profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (widget.onboarding) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.verified_rounded, color: AppColors.success),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "You're verified! 🎉  Finish setting up — add a profile "
                      'photo and your town so people know who they are dealing with.',
                      style: TextStyle(
                          fontSize: 14, height: 1.45, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],

          // --- Profile photo ---
          Center(
            child: GestureDetector(
              onTap: _uploading ? null : _pickAvatar,
              child: Stack(
                children: [
                  ClipOval(
                    child: (_displayAvatar != null && _displayAvatar!.isNotEmpty)
                        ? NetworkPhoto(url: _displayAvatar, width: 108, height: 108)
                        : Container(
                            width: 108,
                            height: 108,
                            color: AppColors.primary,
                            alignment: Alignment.center,
                            child: Text(initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.w700)),
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt_rounded,
                              color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _uploading ? null : _pickAvatar,
              child: Text((_displayAvatar != null && _displayAvatar!.isNotEmpty)
                  ? 'Change photo'
                  : 'Add a photo'),
            ),
          ),
          const SizedBox(height: 18),

          // --- Town / location ---
          const Text('Your location',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _town,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Select your town…',
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            ),
            items: [
              for (final t in _imTowns)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _town = v),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],

          const SizedBox(height: 26),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (_saving || _uploading) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.onboarding ? 'Save & continue' : 'Save'),
            ),
          ),
          if (widget.onboarding) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: (_saving || _uploading)
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Skip for now'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
