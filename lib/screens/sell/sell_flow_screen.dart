import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/category.dart';
import '../../models/country.dart';
import '../../models/plan.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/flag_badge.dart';
import '../../widgets/network_photo.dart';
import '../auth/auth_screen.dart';
import '../auth/verify_screen.dart';

/// The Sell tab. Gates on a signed-in session, then runs the multi-step
/// "place an ad" wizard (DoneDeal-style): category -> details -> photos ->
/// contact -> review -> publish. Rebuilds itself when the auth state flips so
/// signing in from the prompt drops straight into the flow.
class SellFlowScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const SellFlowScreen({super.key, required this.api, required this.auth});

  @override
  State<SellFlowScreen> createState() => _SellFlowScreenState();
}

class _SellFlowScreenState extends State<SellFlowScreen> {
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.auth.isLoggedIn) {
      return _SellSignInPrompt(auth: widget.auth);
    }
    // A fresh wizard per session so leaving and returning starts clean.
    return _PlaceAdWizard(
      key: ValueKey(widget.auth.user?.id),
      api: widget.api,
      auth: widget.auth,
    );
  }
}

/// Shown when someone taps Sell without being logged in.
class _SellSignInPrompt extends StatelessWidget {
  final AuthService auth;
  const _SellSignInPrompt({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sell')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_offer_outlined, size: 64, color: AppColors.primary),
              const SizedBox(height: 18),
              const Text(
                'Sell something on List it',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Sign in to place an ad. It takes under two minutes\nto reach thousands of Isle of Man buyers.',
                style: TextStyle(color: AppColors.slate, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          AuthScreen(auth: auth, reason: 'to place an ad'),
                    ));
                  },
                  child: const Text('Sign in or create account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- The wizard -------------------------------------------------------------

class _PlaceAdWizard extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const _PlaceAdWizard({super.key, required this.api, required this.auth});

  @override
  State<_PlaceAdWizard> createState() => _PlaceAdWizardState();
}

class _PlaceAdWizardState extends State<_PlaceAdWizard> {
  static const _steps = ['Category', 'Details', 'Photos', 'Contact', 'Review'];
  static const _imTowns = [
    'Douglas', 'Onchan', 'Ramsey', 'Peel', 'Castletown', 'Port Erin',
    'Port St Mary', 'Ballasalla', 'Laxey', 'Kirk Michael', 'Ballaugh',
    'Sulby', 'Andreas', 'Foxdale', 'Colby', 'Crosby', 'Glen Vine', 'Santon',
  ];

  int _step = 0;

  // Reference data
  List<Category>? _allCats;
  Plan? _plan; // the free "Lite" tier (or cheapest available)
  String? _loadError;

  // Draft
  final List<Category> _catPath = []; // top-level ... leaf
  int _adType = 1; // 1 = For sale, 2 = Wanted
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _poa = false; // price on application / negotiable
  final List<_Photo> _photos = [];
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  PhoneCountry _country = kDefaultCountry;
  String? _location;
  bool _allowCall = true;
  bool _allowMessage = true;

  bool _publishing = false;

  Category? get _leaf => _catPath.isNotEmpty ? _catPath.last : null;
  int get _maxPhotos => _plan?.photos ?? 4;

  @override
  void initState() {
    super.initState();
    final u = widget.auth.user;
    _nameCtrl.text = u?.name ?? '';
    _phoneCtrl.text = u?.phone ?? '';
    _country = countryFor(iso: u?.countryCode, dial: u?.flag);
    _location = (u?.location != null && _imTowns.contains(u!.location)) ? u.location : null;
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final cats = await widget.api.fetchAllCategories();
      List<Plan> plans = const [];
      try {
        plans = await widget.api.fetchPlans();
      } catch (_) {
        // Plans are non-fatal; fall back to a sensible free default below.
      }
      Plan? free;
      for (final p in plans) {
        if (p.isFree) {
          free = p;
          break;
        }
      }
      free ??= plans.isNotEmpty ? plans.first : null;
      // Absolute fallback: the known free "Lite" plan.
      free ??= const Plan(
          id: 11, name: 'Lite', price: 0, days: 360, photos: 4, recommended: false);
      if (mounted) setState(() { _allCats = cats; _plan = free; });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  List<Category> _childrenOf(int parentId) {
    final list = (_allCats ?? []).where((c) => c.parentId == parentId).toList();
    list.sort((a, b) => b.adCount.compareTo(a.adCount));
    return list;
  }

  bool _isLeaf(Category c) => _childrenOf(c.id).isEmpty;

  // --- Navigation ----------------------------------------------------------

  void _next() {
    if (!_validateStep()) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  bool _validateStep() {
    switch (_step) {
      case 0:
        if (_leaf == null || !_isLeaf(_leaf!)) {
          _toast('Please choose a category');
          return false;
        }
        return true;
      case 1:
        if (_titleCtrl.text.trim().length < 3) {
          _toast('Give your ad a title (at least 3 characters)');
          return false;
        }
        if (_descCtrl.text.trim().length < 10) {
          _toast('Add a short description (at least 10 characters)');
          return false;
        }
        return true;
      case 2:
        if (_photos.isEmpty) {
          _toast('Add at least one photo');
          return false;
        }
        if (_photos.any((p) => p.uploading)) {
          _toast('Please wait for photos to finish uploading');
          return false;
        }
        return true;
      case 3:
        if (_nameCtrl.text.trim().isEmpty) {
          _toast('Enter your name');
          return false;
        }
        if (_phoneCtrl.text.trim().length < 6) {
          _toast('Enter a contact phone number');
          return false;
        }
        if (_location == null) {
          _toast('Choose a location');
          return false;
        }
        if (!_allowCall && !_allowMessage) {
          _toast('Pick at least one way for buyers to reach you');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // --- Publish -------------------------------------------------------------

  String _expiryString() {
    final now = DateTime.now();
    final exp = now.add(Duration(days: _plan?.days ?? 360));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${exp.year}-${two(exp.month)}-${two(exp.day)} 00:00:00';
  }

  Future<void> _publish() async {
    final u = widget.auth.user;
    if (u == null) return;
    setState(() => _publishing = true);
    final contact = <String>[];
    if (_allowCall) contact.add('1');
    if (_allowMessage) contact.add('2');
    final categoriesCsv = _catPath.map((c) => c.id).join(',');
    final price = _poa ? 0 : (double.tryParse(_priceCtrl.text.trim()) ?? 0);

    final payload = <String, dynamic>{
      'user_id': u.id,
      'categories': categoriesCsv,
      'ad_type': _adType,
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': price,
      'price_qualifier': _poa ? 'poa' : null,
      'full_name': _nameCtrl.text.trim(),
      'email': u.email,
      'phone': _phoneCtrl.text.trim(),
      'country_code': _country.iso,
      'phone_code': _country.dial,
      'country': _country.name,
      'location': _location,
      'allow_contact': contact.join(','),
      'plan_id': _plan?.id ?? 11,
      'plan_name': _plan?.name ?? 'Lite',
      'days_of_listing': _plan?.days ?? 360,
      'plan_price': 0,
      'total_price': 0,
      'amount_paid': 0,
      'spotlight_days': 0,
      'bump': 0,
      'priority_placement': 0,
      'status': 1,
      'is_vehicle': (_leaf?.isVehicle ?? false) ? 1 : 0,
      'phone_verified': 1,
      'images': _photos.map((p) => p.url).toList(),
      'attribute': <String, dynamic>{},
      'expiry': _expiryString(),
    };

    try {
      final data = await widget.api.createAd(payload);
      if (!mounted) return;
      final id = data['ad_id'] ?? data['id'] ?? data['result'];
      _showSuccess(id is int ? id : int.tryParse('$id'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _showPublishError(e.toString());
    }
  }

  void _showPublishError(String message) {
    // The server blocks unverified accounts with a specific message; give that
    // its own friendly treatment since it's the one thing the seller can act on.
    final verifyGate = message.toLowerCase().contains('verify');
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(verifyGate ? 'Verify your account first' : "Couldn't publish"),
        content: Text(verifyGate
            ? 'To keep List it safe, you need a verified email and phone number '
                'before your first ad goes live. It only takes a minute.'
            : message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(verifyGate ? 'Later' : 'OK'),
          ),
          if (verifyGate)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openVerify();
              },
              child: const Text('Verify now'),
            ),
        ],
      ),
    );
  }

  Future<void> _openVerify() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VerifyScreen(
          auth: widget.auth,
          api: widget.api,
          reason: 'to publish your ad',
        ),
      ),
    );
    // If they finished verifying, drop them straight back onto Publish.
    if (ok == true && mounted && (widget.auth.user?.fullyVerified ?? false)) {
      _toast('Verified — tap Publish to go live');
    }
  }

  void _showSuccess(int? adId) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 10),
            Text('Your ad is live!'),
          ],
        ),
        content: const Text(
          'Nice one — your listing is now on List it for buyers across the '
          'Isle of Man to find.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _reset();
            },
            child: const Text('Place another'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _reset();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      _step = 0;
      _catPath.clear();
      _adType = 1;
      _titleCtrl.clear();
      _descCtrl.clear();
      _priceCtrl.clear();
      _poa = false;
      _photos.clear();
      _publishing = false;
    });
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place an ad'),
        leading: _step > 0
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back)
            : null,
      ),
      body: _loadError != null
          ? _ErrorState(message: _loadError!, onRetry: _load)
          : _allCats == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _StepBar(steps: _steps, current: _step),
                    Expanded(child: _buildStep()),
                    _bottomBar(),
                  ],
                ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _categoryStep();
      case 1:
        return _detailsStep();
      case 2:
        return _photosStep();
      case 3:
        return _contactStep();
      default:
        return _reviewStep();
    }
  }

  Widget _bottomBar() {
    if (_allCats == null) return const SizedBox.shrink();
    final isReview = _step == _steps.length - 1;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _publishing
                ? null
                : isReview
                    ? _publish
                    : _next,
            child: _publishing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(isReview ? 'Publish ad — Free' : 'Continue'),
          ),
        ),
      ),
    );
  }

  // --- Step 0: Category ----------------------------------------------------

  Widget _categoryStep() {
    // Current level = children of the last chosen category (or top level).
    final parentId = _catPath.isEmpty ? 0 : _catPath.last.id;
    final options = _childrenOf(parentId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_catPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < _catPath.length; i++) ...[
                  InkWell(
                    onTap: () => setState(
                        () => _catPath.removeRange(i + 1, _catPath.length)),
                    child: Text(
                      _catPath[i].name,
                      style: const TextStyle(
                          color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (i < _catPath.length - 1)
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            _catPath.isEmpty ? 'What are you selling?' : 'Choose a subcategory',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = options[i];
              final leaf = _isLeaf(c);
              final selected = _leaf?.id == c.id && leaf;
              return ListTile(
                title: Text(c.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: c.adCount > 0
                    ? Text('${c.adCount} live', style: const TextStyle(fontSize: 12))
                    : null,
                trailing: leaf
                    ? (selected
                        ? const Icon(Icons.check_circle, color: AppColors.primary)
                        : const Icon(Icons.radio_button_unchecked,
                            color: AppColors.muted))
                    : const Icon(Icons.chevron_right, color: AppColors.muted),
                onTap: () {
                  setState(() {
                    if (leaf) {
                      // Replace any previously chosen leaf at this level.
                      if (_leaf?.id == c.id) {
                        _catPath.removeLast();
                      } else {
                        _catPath.add(c);
                      }
                    } else {
                      _catPath.add(c);
                    }
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // --- Step 1: Details -----------------------------------------------------

  Widget _detailsStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Listing type',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            _typeChip('For sale', 1),
            const SizedBox(width: 10),
            _typeChip('Wanted', 2),
          ],
        ),
        const SizedBox(height: 20),
        _label('Title'),
        TextField(
          controller: _titleCtrl,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 70,
          decoration: _dec('e.g. iPhone 14 Pro, 128GB, excellent condition'),
        ),
        const SizedBox(height: 8),
        _label('Price'),
        TextField(
          controller: _priceCtrl,
          enabled: !_poa,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: _dec('0.00').copyWith(
            prefixText: '£ ',
            hintText: _poa ? 'Contact for price' : '0.00',
          ),
        ),
        Row(
          children: [
            Checkbox(
              value: _poa,
              onChanged: (v) => setState(() => _poa = v ?? false),
            ),
            const Text('Price on application / negotiable'),
          ],
        ),
        const SizedBox(height: 8),
        _label('Description'),
        TextField(
          controller: _descCtrl,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 6,
          maxLength: 4000,
          decoration: _dec(
              'Describe what you\'re selling — condition, age, why you\'re selling, collection or delivery.'),
        ),
      ],
    );
  }

  Widget _typeChip(String label, int value) {
    final selected = _adType == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _adType = value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.line, width: 1.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.slate,
            ),
          ),
        ),
      ),
    );
  }

  // --- Step 2: Photos ------------------------------------------------------

  Widget _photosStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Add photos (up to $_maxPhotos)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          'The first photo is your main image. Clear, well-lit photos sell faster.',
          style: TextStyle(color: AppColors.slate, height: 1.35),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (var i = 0; i < _photos.length; i++) _photoTile(_photos[i], i),
            if (_photos.length < _maxPhotos) _addPhotoTile(),
          ],
        ),
      ],
    );
  }

  Widget _photoTile(_Photo p, int index) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(p.localPath), fit: BoxFit.cover),
          if (p.uploading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
          if (p.failed)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Icon(Icons.error_outline, color: Colors.white),
              ),
            ),
          if (index == 0 && !p.uploading)
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                color: AppColors.primary,
                child: const Text('Main',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: () => setState(() => _photos.removeAt(index)),
              child: Container(
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(3),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPhotoTile() {
    return InkWell(
      onTap: _pickPhotos,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line, width: 1.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
            SizedBox(height: 6),
            Text('Add', style: TextStyle(color: AppColors.slate, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) return;
    try {
      final picked = await picker.pickMultiImage(imageQuality: 82, limit: remaining);
      if (picked.isEmpty) return;
      for (final x in picked.take(remaining)) {
        final photo = _Photo(localPath: x.path);
        setState(() => _photos.add(photo));
        _uploadPhoto(photo, File(x.path));
      }
    } catch (e) {
      _toast('Could not open photos: $e');
    }
  }

  Future<void> _uploadPhoto(_Photo photo, File file) async {
    try {
      final url = await widget.api.uploadPhoto(file);
      if (!mounted) return;
      setState(() {
        photo.url = url;
        photo.uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        photo.uploading = false;
        photo.failed = true;
      });
      _toast('A photo failed to upload — tap it to remove and try again');
    }
  }

  // --- Step 3: Contact -----------------------------------------------------

  Widget _contactStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _label('Your name'),
        TextField(controller: _nameCtrl, decoration: _dec('Name buyers will see')),
        const SizedBox(height: 14),
        _label('Contact number'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _countryPicker(),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                ],
                decoration: _dec(_country.hint),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _label('Location'),
        DropdownButtonFormField<String>(
          initialValue: _location,
          isExpanded: true,
          decoration: _dec('Choose a town'),
          items: [
            for (final t in _imTowns)
              DropdownMenuItem(value: t, child: Text(t)),
          ],
          onChanged: (v) => setState(() => _location = v),
        ),
        const SizedBox(height: 20),
        const Text('How can buyers reach you?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _allowCall,
          onChanged: (v) => setState(() => _allowCall = v ?? false),
          title: const Text('Phone call'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _allowMessage,
          onChanged: (v) => setState(() => _allowMessage = v ?? false),
          title: const Text('Message through List it'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  // --- Step 4: Review ------------------------------------------------------

  Widget _reviewStep() {
    final price = _poa
        ? 'Contact for price'
        : (_priceCtrl.text.trim().isEmpty ? 'Free' : '£${_priceCtrl.text.trim()}');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (_photos.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: _photos.first.url.isNotEmpty
                  ? NetworkPhoto(url: _photos.first.url, fit: BoxFit.cover)
                  : Image.file(File(_photos.first.localPath), fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 14),
        Text(_titleCtrl.text.trim(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(price,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
        const SizedBox(height: 14),
        _reviewRow('Category', _catPath.map((c) => c.name).join(' › ')),
        _reviewRow('Type', _adType == 1 ? 'For sale' : 'Wanted'),
        _reviewRow('Location', _location ?? '—'),
        _reviewRow('Photos', '${_photos.length}'),
        _reviewRow('Contact', _nameCtrl.text.trim()),
        const SizedBox(height: 12),
        const Divider(),
        Text(_descCtrl.text.trim(),
            style: const TextStyle(color: AppColors.slate, height: 1.4)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_plan?.name ?? 'Lite'} plan — Free · live for ${_plan?.days ?? 360} days',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 92,
              child: Text(k,
                  style: const TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w600))),
          Expanded(
              child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // --- shared bits ---------------------------------------------------------

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  /// Flag + dial-code button that opens the country sheet. Isle of Man and the
  /// UK both dial +44, so the flag is how the seller (and buyers) tell them
  /// apart.
  Widget _countryPicker() => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _pickCountry,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              FlagBadge(iso: _country.iso),
              const SizedBox(width: 6),
              Text('+${_country.dial}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
              const Icon(Icons.arrow_drop_down, color: AppColors.slate),
            ],
          ),
        ),
      );

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<PhoneCountry>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Country',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            for (final c in kPhoneCountries)
              ListTile(
                leading: FlagBadge(iso: c.iso, width: 30, height: 21),
                title: Text(c.name),
                trailing: Text('+${c.dial}',
                    style: const TextStyle(color: AppColors.slate)),
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _country = picked);
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      );
}

/// A single photo being added: local file path plus its hosted URL once the
/// Cloudinary upload completes.
class _Photo {
  final String localPath;
  String url;
  bool uploading;
  bool failed;
  _Photo({required this.localPath})
      : url = '',
        uploading = true,
        failed = false;
}

class _StepBar extends StatelessWidget {
  final List<String> steps;
  final int current;
  const _StepBar({required this.steps, required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _dot(i),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: i < current ? AppColors.primary : AppColors.line,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _dot(int i) {
    final done = i < current;
    final active = i == current;
    final color = done || active ? AppColors.primary : AppColors.line;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 26,
          width: 26,
          decoration: BoxDecoration(
            color: done ? AppColors.primary : Colors.white,
            border: Border.all(color: color, width: 2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? AppColors.primary : AppColors.muted)),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 42, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
