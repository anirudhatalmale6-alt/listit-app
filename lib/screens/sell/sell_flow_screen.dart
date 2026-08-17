import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/vehicle_options.dart';
import '../../models/ad_attribute.dart';
import '../../models/category.dart';
import '../../models/country.dart';
import '../../models/plan.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/flag_badge.dart';
import '../auth/auth_screen.dart';
import '../auth/verify_screen.dart';
import 'ad_live_screen.dart';

/// The Sell tab. Gates on a signed-in session, then shows the "place an ad"
/// form - a single scrollable page modelled on DoneDeal: title, section /
/// subsection, ad type, photos, description, price, contact details and how
/// buyers can reach you. Required fields turn red inline if you try to publish
/// with them missing. Rebuilds itself when auth flips so signing in drops
/// straight into the form.
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
    // A fresh form per session so leaving and returning starts clean.
    return _PlaceAdForm(
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
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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

// --- The form ---------------------------------------------------------------

class _PlaceAdForm extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const _PlaceAdForm({super.key, required this.api, required this.auth});

  @override
  State<_PlaceAdForm> createState() => _PlaceAdFormState();
}

class _PlaceAdFormState extends State<_PlaceAdForm> {
  static const _imTowns = [
    'Douglas', 'Onchan', 'Ramsey', 'Peel', 'Castletown', 'Port Erin',
    'Port St Mary', 'Ballasalla', 'Laxey', 'Kirk Michael', 'Ballaugh',
    'Sulby', 'Andreas', 'Foxdale', 'Colby', 'Crosby', 'Glen Vine', 'Santon',
  ];

  // Reference data
  List<Category>? _allCats;
  Plan? _plan; // the free "Lite" tier (or cheapest available)
  String? _loadError;

  // Plans available for the chosen category (Lite / Standard / Premium ...),
  // fetched per-category like the website. _selectedPlan is what the user picks.
  List<Plan> _catPlans = const [];
  Plan? _selectedPlan;
  bool _plansLoading = false;

  /// The plan actually driving photo limits, expiry and payload - the user's
  /// pick if they've chosen one, otherwise the free default.
  Plan? get _activePlan => _selectedPlan ?? _plan;

  /// Whole-pound price of the active plan (the website bills in whole pounds).
  int get _planPrice => (_activePlan?.price ?? 0).round();

  // Draft
  final List<Category> _catPath = []; // section ... leaf
  int _adType = 1; // 1 = For sale, 2 = Wanted
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _poa = false; // price on application / negotiable
  final List<_Photo> _photos = [];
  bool _scanning = false; // Larry is looking at a scanned photo
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  PhoneCountry _country = kDefaultCountry;
  bool _flagLocked = false; // true once the user picks a country by hand
  String? _location;
  bool _allowCall = true;
  bool _allowMessage = true;

  // Vehicle Details (only shown when the chosen category is a vehicle) - the
  // same registration lookup + structured fields the website collects.
  final _regCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _variantCtrl = TextEditingController();
  final _engineCtrl = TextEditingController();
  final _seatsCtrl = TextEditingController();
  final _batteryCtrl = TextEditingController();
  final _logbookCtrl = TextEditingController();
  String _mileageUnit = 'Miles';
  String? _bodyType, _fuelType, _colour, _vYear, _transmission, _doors;
  bool _vehLoading = false;
  bool? _vehFound; // null = not searched yet, true = found, false = no match
  Map<String, dynamic>? _vehRaw; // full lookup result, so tax/co2/nct persist
  bool _verifying = false;
  bool? _verified; // null = not tried, true = Greenlight earned, false = no match

  // Dynamic per-category attributes (non-vehicle categories), e.g. Property ->
  // Bedrooms/Property Type. Mirrors what the website collects for the category.
  List<AdAttribute> _catAttrs = const [];
  final Map<int, String> _attrValues = {}; // attribute id -> chosen value
  bool _catAttrsLoading = false;

  bool _publishing = false;

  // Inline validation errors (null = no error). Mirror DoneDeal's red-field
  // treatment - each is shown under its field and the border turns red.
  String? _errTitle;
  String? _errCat;
  String? _errPhotos;
  String? _errDesc;
  String? _errPrice;
  String? _errName;
  String? _errPhone;
  String? _errLocation;
  String? _errContact;
  String? _errReg;
  String? _errMileage;
  String? _errMake;
  String? _errModel;
  String? _errVYear;
  String? _errFuel;

  // Keys used to scroll to the first field that's still missing.
  final _scroll = ScrollController();
  final _kTitle = GlobalKey();
  final _kCat = GlobalKey();
  final _kPhotos = GlobalKey();
  final _kDesc = GlobalKey();
  final _kPrice = GlobalKey();
  final _kName = GlobalKey();
  final _kPhone = GlobalKey();
  final _kLocation = GlobalKey();
  final _kContact = GlobalKey();
  final _kVehicle = GlobalKey();

  Category? get _leaf => _catPath.isNotEmpty ? _catPath.last : null;
  bool get _isVehicleAd => _leaf?.isVehicle ?? false;
  bool _wantsField(String key) => _leaf?.wantsVehicleField(key) ?? false;
  int get _maxPhotos => _activePlan?.photos ?? 4;

  /// The cheapest plan for this category that offers more photos than the
  /// current allowance — used to nudge an upgrade once the free photos are
  /// used up (e.g. "Upgrade to Excel — £2 for up to 15 photos").
  Plan? get _photoUpgradePlan {
    final current = _maxPhotos;
    Plan? best;
    for (final p in _catPlans) {
      if (p.photos > current && (best == null || p.price < best.price)) {
        best = p;
      }
    }
    return best;
  }
  bool get _phoneVerified => widget.auth.user?.phoneVerified ?? false;

  @override
  void initState() {
    super.initState();
    final u = widget.auth.user;
    _nameCtrl.text = u?.name ?? '';
    _phoneCtrl.text = u?.phone ?? '';
    _country = countryFor(iso: u?.countryCode, dial: u?.flag);
    _location = (u?.location != null && _imTowns.contains(u!.location)) ? u.location : null;
    _restoreLastLocation();
    _load();
  }

  static const _kLastLocationPref = 'listit_last_ad_location';

  /// Remember the town picked last time, so sellers don't reselect it on every
  /// ad. Overrides the profile default with the most recent choice.
  Future<void> _restoreLastLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kLastLocationPref);
      if (mounted && saved != null && _imTowns.contains(saved)) {
        setState(() => _location = saved);
      }
    } catch (_) {}
  }

  Future<void> _saveLastLocation(String? v) async {
    if (v == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastLocationPref, v);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scroll.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _regCtrl.dispose();
    _mileageCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _variantCtrl.dispose();
    _engineCtrl.dispose();
    _seatsCtrl.dispose();
    _batteryCtrl.dispose();
    _logbookCtrl.dispose();
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

  // --- Validation ----------------------------------------------------------

  /// Validate the whole form, set the inline errors and return the key of the
  /// first field that failed (null if everything passed).
  GlobalKey? _validate() {
    GlobalKey? first;
    void fail(GlobalKey k) => first ??= k;

    _errTitle = _titleCtrl.text.trim().length < 3
        ? 'Please enter an ad title (at least 3 characters).'
        : null;
    if (_errTitle != null) fail(_kTitle);

    if (_catPath.isEmpty) {
      _errCat = 'Please select a section.';
    } else if (!_isLeaf(_leaf!)) {
      _errCat = 'Please choose a subsection.';
    } else {
      _errCat = null;
    }
    if (_errCat != null) fail(_kCat);

    // Vehicle Details - required for a vehicle category, matching the website.
    _errReg = _errMileage = _errMake = _errModel = _errVYear = _errFuel = null;
    if (_isVehicleAd) {
      if (_regCtrl.text.trim().isEmpty) {
        _errReg = 'Enter the registration, or fill the details in below.';
      }
      if (_mileageCtrl.text.trim().isEmpty) {
        _errMileage = 'Please enter the mileage.';
      }
      if (_wantsField('make') && _makeCtrl.text.trim().isEmpty) {
        _errMake = 'Make is required.';
      }
      if (_wantsField('model') && _modelCtrl.text.trim().isEmpty) {
        _errModel = 'Model is required.';
      }
      if (_wantsField('year') && (_vYear == null || _vYear!.isEmpty)) {
        _errVYear = 'Year is required.';
      }
      if (_wantsField('fuel_type') && (_fuelType == null || _fuelType!.isEmpty)) {
        _errFuel = 'Fuel type is required.';
      }
      if (_errReg != null ||
          _errMileage != null ||
          _errMake != null ||
          _errModel != null ||
          _errVYear != null ||
          _errFuel != null) {
        fail(_kVehicle);
      }
    }

    _errPhotos = _photos.isEmpty
        ? 'Please add at least one photo.'
        : (_photos.any((p) => p.uploading)
            ? 'Please wait for your photos to finish uploading.'
            : null);
    if (_errPhotos != null) fail(_kPhotos);

    _errDesc = _descCtrl.text.trim().length < 10
        ? 'Please add a description (at least 10 characters).'
        : null;
    if (_errDesc != null) fail(_kDesc);

    // Price is required for a For-sale ad unless it's marked negotiable / POA.
    _errPrice = (_adType == 1 && !_poa && _priceCtrl.text.trim().isEmpty)
        ? 'Please enter a price, or tick negotiable.'
        : null;
    if (_errPrice != null) fail(_kPrice);

    _errName = _nameCtrl.text.trim().isEmpty ? 'Please enter your name.' : null;
    if (_errName != null) fail(_kName);

    _errPhone = _phoneCtrl.text.trim().length < 6
        ? 'Please enter a contact number.'
        : null;
    if (_errPhone != null) fail(_kPhone);

    _errLocation = _location == null ? 'Please select your town.' : null;
    if (_errLocation != null) fail(_kLocation);

    _errContact = (!_allowCall && !_allowMessage)
        ? 'Please pick at least one way for buyers to reach you.'
        : null;
    if (_errContact != null) fail(_kContact);

    return first;
  }

  void _submit() {
    final firstError = _validate();
    setState(() {});
    if (firstError != null) {
      _toast('Please finish creating your ad.');
      // Scroll the first missing field into view, like DoneDeal does.
      final ctx = firstError.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 350),
            alignment: 0.15,
            curve: Curves.easeOut);
      }
      return;
    }
    _publish();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // --- Publish -------------------------------------------------------------

  String _expiryString() {
    final now = DateTime.now();
    final exp = now.add(Duration(days: _activePlan?.days ?? 360));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${exp.year}-${two(exp.month)}-${two(exp.day)} 00:00:00';
  }

  Future<void> _publish() async {
    final u = widget.auth.user;
    if (u == null) return;
    setState(() => _publishing = true);
    // Matches the website's `allow_contact` codes: "1" = Message, "2" =
    // Phone/Text. (These were previously the wrong way round here, so app-posted
    // ads had call/message swapped versus how the site reads them.)
    final contact = <String>[];
    if (_allowMessage) contact.add('1');
    if (_allowCall) contact.add('2');
    final categoriesCsv = _catPath.map((c) => c.id).join(',');
    final price = _poa ? 0 : (double.tryParse(_priceCtrl.text.trim()) ?? 0);

    // Category-specific attributes (non-vehicle), in the website's shape:
    // { "<attrId>": {value, key, category} }.
    final attribute = <String, dynamic>{};
    if (!_isVehicleAd && _leaf != null) {
      for (final a in _catAttrs) {
        final v = (_attrValues[a.id] ?? '').trim();
        if (v.isNotEmpty) {
          attribute['${a.id}'] = {
            'value': v,
            'key': a.key,
            'category': _leaf!.id,
          };
        }
      }
    }

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
      'plan_id': _activePlan?.id ?? 11,
      'plan_name': _activePlan?.name ?? 'Lite',
      'days_of_listing': _activePlan?.days ?? 360,
      'plan_price': _planPrice,
      'total_price': _planPrice,
      // Free plans are considered settled; paid plans are billed like the
      // website (created unpaid, then paid on the summary/manage flow).
      'amount_paid': _planPrice == 0 ? 1 : 0,
      'spotlight_days': 0,
      'spotlight_price': 0,
      'bump': _activePlan?.bump ?? 0,
      'bump_week': _activePlan?.bumpWeek ?? 0,
      'priority_placement': _activePlan?.priorityPlacement ?? 0,
      'status': 1,
      'is_vehicle': _isVehicleAd ? 1 : 0,
      'phone_verified': 1,
      'images': _photos.map((p) => p.url).toList(),
      'attribute': attribute,
      'vehicle_details': _isVehicleAd ? _buildVehicleDetails() : <String, dynamic>{},
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

  Future<void> _showSuccess(int? adId) async {
    // Full "Your ad is live!" celebration (illustration + share + View ad),
    // mirroring the website. Returning from it starts a fresh form.
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AdLiveScreen(
        adId: adId,
        title: _titleCtrl.text.trim(),
        api: widget.api,
        auth: widget.auth,
      ),
    ));
    if (mounted) _reset();
  }

  void _reset() {
    setState(() {
      _catPath.clear();
      _adType = 1;
      _titleCtrl.clear();
      _descCtrl.clear();
      _priceCtrl.clear();
      _poa = false;
      _photos.clear();
      _publishing = false;
      _regCtrl.clear();
      _mileageCtrl.clear();
      _makeCtrl.clear();
      _modelCtrl.clear();
      _variantCtrl.clear();
      _engineCtrl.clear();
      _seatsCtrl.clear();
      _batteryCtrl.clear();
      _logbookCtrl.clear();
      _mileageUnit = 'Miles';
      _bodyType = _fuelType = _colour = _vYear = _transmission = _doors = null;
      _vehLoading = false;
      _vehFound = null;
      _vehRaw = null;
      _verifying = false;
      _verified = null;
      _catAttrs = const [];
      _attrValues.clear();
      _catAttrsLoading = false;
      _catPlans = const [];
      _selectedPlan = null;
      _plansLoading = false;
      _errTitle = _errCat = _errPhotos = _errDesc = _errPrice =
          _errName = _errPhone = _errLocation = _errContact = null;
      _errReg = _errMileage = _errMake = _errModel = _errVYear = _errFuel = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Place an ad')),
      body: _loadError != null
          ? _ErrorState(message: _loadError!, onRetry: _load)
          : _allCats == null
              ? const Center(child: CircularProgressIndicator())
              : _form(),
    );
  }

  Widget _form() {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        // Scan with Larry - snap a photo, let the AI draft the listing.
        _scanCard(),
        const SizedBox(height: 18),

        // Ad Title
        KeyedSubtree(
          key: _kTitle,
          child: _field(
            'Ad Title',
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 70,
              onChanged: (_) => _clear(() => _errTitle = null),
              decoration:
                  _dec('e.g. VW Golf, iPhone 14 Pro, 3-seater sofa',
                      error: _errTitle,
                      filled: _titleCtrl.text.trim().isNotEmpty),
            ),
          ),
        ),

        // Section / Subsection dropdowns
        KeyedSubtree(key: _kCat, child: Column(children: _categoryDropdowns())),

        // Vehicle Details - registration lookup + structured specs, shown only
        // for vehicle categories, exactly like the website.
        if (_isVehicleAd)
          KeyedSubtree(key: _kVehicle, child: _vehicleSection()),

        // Category-specific details for non-vehicle categories (Property ->
        // Bedrooms, etc.), pulled dynamically to match the website.
        if (!_isVehicleAd) ..._attributeFields(),

        // Ad Type
        _sectionLabel('Ad Type'),
        Row(
          children: [
            _radio('For Sale', 1),
            const SizedBox(width: 8),
            _radio('Wanted', 2),
          ],
        ),
        const SizedBox(height: 20),

        // Photos
        KeyedSubtree(key: _kPhotos, child: _photosSection()),

        // Description
        KeyedSubtree(
          key: _kDesc,
          child: _field(
            'Description',
            TextField(
              controller: _descCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 6,
              maxLength: 4000,
              onChanged: (_) => _clear(() => _errDesc = null),
              decoration: _dec(
                  'Tell buyers about your ad — condition, age, why you\'re selling, collection or delivery.',
                  error: _errDesc,
                  filled: _descCtrl.text.trim().isNotEmpty),
            ),
          ),
        ),

        // Price
        KeyedSubtree(
          key: _kPrice,
          child: _field(
            'Price',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _priceCtrl,
                  enabled: !_poa,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => _clear(() => _errPrice = null),
                  decoration: _dec(_poa ? 'Contact for price' : '',
                          error: _errPrice,
                          filled: _poa || _priceCtrl.text.trim().isNotEmpty)
                      .copyWith(
                    // Always-visible £ so the field reads "£" with no 0.00,
                    // exactly as the website shows it.
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 14, right: 8),
                      child: Text('£',
                          style: TextStyle(
                              fontSize: 16,
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600)),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: _poa,
                      onChanged: (v) => setState(() {
                        _poa = v ?? false;
                        if (_poa) _errPrice = null;
                      }),
                    ),
                    const Expanded(
                      child: Text('Price on application / negotiable'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        const Text('Contact Preferences',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),

        // Full name
        KeyedSubtree(
          key: _kName,
          child: _field(
            'Full Name',
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => _clear(() => _errName = null),
              decoration: _dec('Name buyers will see',
                  error: _errName, filled: _nameCtrl.text.trim().isNotEmpty),
            ),
          ),
        ),

        // Phone (with Verified badge)
        KeyedSubtree(
          key: _kPhone,
          child: _field(
            'Phone',
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
                    onChanged: (v) {
                      _clear(() => _errPhone = null);
                      if (_flagLocked || _country.dial == '353') return;
                      final c = detectUkOrManx(v);
                      if (c != null && c.iso != _country.iso) {
                        setState(() => _country = c);
                      }
                    },
                    decoration: _dec(_country.hint,
                        error: _errPhone,
                        filled: _phoneCtrl.text.trim().isNotEmpty),
                  ),
                ),
              ],
            ),
            trailing: _phoneVerified
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 16, color: AppColors.success),
                      SizedBox(width: 4),
                      Text('Verified',
                          style: TextStyle(
                              color: AppColors.slate,
                              fontWeight: FontWeight.w600)),
                    ],
                  )
                : null,
          ),
        ),

        // Email (read-only, from the account)
        _field(
          'Email',
          TextField(
            enabled: false,
            decoration: _dec(widget.auth.user?.email ?? '',
                    filled: (widget.auth.user?.email ?? '').isNotEmpty)
                .copyWith(
              hintStyle: const TextStyle(color: AppColors.slate),
            ),
          ),
        ),

        // Town / area
        KeyedSubtree(
          key: _kLocation,
          child: _field(
            'Town / Area',
            DropdownButtonFormField<String>(
              initialValue: _location,
              isExpanded: true,
              decoration: _dec('Please select…',
                  error: _errLocation, filled: _location != null),
              items: [
                for (final t in _imTowns)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                setState(() {
                  _location = v;
                  _errLocation = null;
                });
                _saveLastLocation(v);
              },
            ),
          ),
        ),

        // Allow contact by
        KeyedSubtree(
          key: _kContact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Allow contact by',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text('Choose how buyers can reach you about this ad',
                  style: TextStyle(color: AppColors.slate, fontSize: 13)),
              const SizedBox(height: 12),
              _contactCard('Phone and text', _allowCall,
                  (v) => setState(() { _allowCall = v; _errContact = null; })),
              const SizedBox(height: 10),
              _contactCard('Message through List it', _allowMessage,
                  (v) => setState(() { _allowMessage = v; _errContact = null; })),
              if (_errContact != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_errContact!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12.5)),
                ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        ..._planSection(),

        // The Place-ad button lives at the very end of the form (not pinned to
        // the bottom), so sellers scroll past every field before they can post
        // — fewer half-finished ads, less back-and-forth.
        const SizedBox(height: 24),
        _publishBar(),
      ],
    );
  }

  /// The "Select Your Plan" picker - the same Lite / Standard / Premium plans
  /// the website offers for this category, as tappable cards. Falls back to the
  /// simple free-plan confirmation when plans aren't loaded (e.g. before a
  /// category is chosen, or if the plans call is unavailable).
  List<Widget> _planSection() {
    if (_plansLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_catPlans.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_activePlan?.name ?? 'Lite'} plan — Free · live for '
                  '${_activePlan?.days ?? 360} days',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      const Text('Select your plan',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      const Text('Choose how your ad is promoted',
          style: TextStyle(color: AppColors.slate, fontSize: 13)),
      const SizedBox(height: 12),
      for (var i = 0; i < _catPlans.length; i++) ...[
        _planCard(_catPlans[i], i),
        if (i != _catPlans.length - 1) const SizedBox(height: 10),
      ],
    ];
  }

  Widget _planCard(Plan plan, int index) {
    final selected = _selectedPlan?.id == plan.id;
    // Ad-views strength bar, mirroring the website (1 / 3 / 5 of 5 blocks).
    final filled = index == 0 ? 1 : (index == 1 ? 3 : 5);
    final barColor = index >= 1 ? AppColors.success : const Color(0xFFFD7E14);
    final priceText = plan.price <= 0 ? 'Free' : '£${_money(plan.price)}';
    return InkWell(
      onTap: () => _selectPlan(plan),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (plan.recommended)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.image),
                    ),
                    child: const Text('Recommended',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(priceText,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Ad views',
                    style: TextStyle(fontSize: 12, color: AppColors.slate)),
                const SizedBox(width: 8),
                for (var b = 0; b < 5; b++)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: b < filled ? barColor : const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _planFeature('${plan.days} days listing'),
            if (plan.bump > 0)
              _planFeature('${plan.bump} x Bump ${plan.bumpWeek} per week'),
            _planFeature('Up to ${plan.photos} photos'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _selectPlan(plan),
                style: OutlinedButton.styleFrom(
                  backgroundColor: selected ? AppColors.primary : Colors.white,
                  foregroundColor: selected ? Colors.white : AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(selected ? 'Selected' : 'Choose',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planFeature(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            const Icon(Icons.check_rounded, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );

  /// £5.00 -> "5", £5.50 -> "5.50" - drop trailing ".00" like the website.
  String _money(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  /// Run [fn] (which clears an error) and rebuild only if it actually changed
  /// something, so typing in a valid field doesn't thrash setState.
  void _clear(VoidCallback fn) {
    setState(fn);
  }

  // Section + subsection dropdowns, one per level of the category tree, so the
  // common two-level case reads exactly like DoneDeal's Section / Subsection.
  List<Widget> _categoryDropdowns() {
    final widgets = <Widget>[];
    var parentId = 0;
    var errorAttached = false;
    for (var level = 0;; level++) {
      final options = _childrenOf(parentId);
      if (options.isEmpty) break;
      final selected = level < _catPath.length ? _catPath[level] : null;
      // Show the category error on the first dropdown still awaiting a choice.
      String? err;
      if (!errorAttached && selected == null && _errCat != null) {
        err = _errCat;
        errorAttached = true;
      }
      widgets.add(_field(
        level == 0 ? 'Section' : 'Subsection',
        DropdownButtonFormField<int>(
          initialValue: selected?.id,
          isExpanded: true,
          decoration: _dec('Please select…', error: err, filled: selected != null),
          items: [
            for (final c in options)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (id) {
            if (id == null) return;
            setState(() {
              if (level < _catPath.length) {
                _catPath.removeRange(level, _catPath.length);
              }
              _catPath.add(options.firstWhere((c) => c.id == id));
              _errCat = null;
            });
            _loadCatAttrs();
            _loadCatPlans();
          },
        ),
      ));
      if (selected == null) break; // wait for this level before showing deeper
      parentId = selected.id;
    }
    return widgets;
  }

  // --- Category-specific attributes (non-vehicle) --------------------------

  /// Fetch the selected category's attributes (and its ancestors', since the
  /// website defines most on the top-level category) so the Sell form collects
  /// the same extra details the website does for that category.
  Future<void> _loadCatAttrs() async {
    final leaf = _leaf;
    if (leaf == null || leaf.isVehicle) {
      setState(() {
        _catAttrs = const [];
        _attrValues.clear();
        _catAttrsLoading = false;
      });
      return;
    }
    setState(() {
      _catAttrsLoading = true;
      _catAttrs = const [];
      _attrValues.clear();
    });
    try {
      final ids = _catPath.map((c) => c.id).toSet();
      final lists =
          await Future.wait(ids.map((id) => widget.api.fetchAttributes(id)));
      final seen = <int>{};
      final merged = <AdAttribute>[];
      for (final l in lists) {
        for (final a in l) {
          if (seen.add(a.id)) merged.add(a);
        }
      }
      if (mounted) {
        setState(() {
          _catAttrs = merged;
          _catAttrsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _catAttrsLoading = false);
    }
  }

  /// Load the plans that apply to the chosen leaf category (Lite / Standard /
  /// Premium ...), exactly like the website's Place-an-ad plan picker. Defaults
  /// the selection to the free tier so publishing stays free unless upgraded.
  Future<void> _loadCatPlans() async {
    final leaf = _leaf;
    if (leaf == null) {
      setState(() {
        _catPlans = const [];
        _selectedPlan = null;
        _plansLoading = false;
      });
      return;
    }
    setState(() {
      _plansLoading = true;
    });
    try {
      final plans = await widget.api.fetchPlans(leaf.id);
      if (!mounted) return;
      Plan? def;
      for (final p in plans) {
        if (p.isFree) {
          def = p;
          break;
        }
      }
      def ??= plans.isNotEmpty ? plans.first : null;
      setState(() {
        _catPlans = plans;
        _selectedPlan = def;
        _plansLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _catPlans = const [];
          _plansLoading = false;
        });
      }
    }
  }

  List<Widget> _attributeFields() {
    if (_leaf == null || _leaf!.isVehicle) return const [];
    if (_catAttrsLoading) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    if (_catAttrs.isEmpty) return const [];
    final w = <Widget>[
      const SizedBox(height: 4),
      Text('${_leaf!.name} details',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
    ];
    for (final a in _catAttrs) {
      if (a.hasOptions) {
        w.add(_field(
          a.label,
          DropdownButtonFormField<String>(
            initialValue: (_attrValues[a.id] ?? '').isEmpty
                ? null
                : _attrValues[a.id],
            isExpanded: true,
            decoration: _dec('Please select…',
                filled: (_attrValues[a.id] ?? '').isNotEmpty),
            items: [
              for (final o in a.options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) => setState(() => _attrValues[a.id] = v ?? ''),
          ),
        ));
      } else {
        final isNum = a.inputType == 'number';
        w.add(_field(
          a.label,
          TextField(
            keyboardType: isNum ? TextInputType.number : TextInputType.text,
            inputFormatters:
                isNum ? [FilteringTextInputFormatter.digitsOnly] : null,
            onChanged: (v) => setState(() => _attrValues[a.id] = v),
            decoration: _dec('Enter ${a.label.toLowerCase()}',
                filled: (_attrValues[a.id] ?? '').isNotEmpty),
          ),
        ));
      }
    }
    return w;
  }

  // --- Vehicle Details -----------------------------------------------------

  /// The "Vehicle Details" block for vehicle categories: registration lookup
  /// (the Greenlight-style "Find"), mileage, then the structured spec fields
  /// the category asks for. Mirrors the website's CarValue section.
  Widget _vehicleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        const Text('Vehicle Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_rounded, size: 16, color: AppColors.success),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Pop in your reg and we\'ll fill in the details. Verify your log '
                'book below to earn a free Greenlight badge on your ad.',
                style: TextStyle(
                    color: AppColors.slate, fontSize: 13, height: 1.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Registration + Find
        _sectionLabel('Vehicle registration'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _regCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseTextFormatter()],
                onChanged: (_) => _clear(() => _errReg = null),
                decoration: _dec('e.g. MN12 ABC',
                    error: _errReg, filled: _regCtrl.text.trim().isNotEmpty),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 54,
              width: 92,
              child: ElevatedButton(
                onPressed: _vehLoading ? null : _findVehicle,
                child: _vehLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Find'),
              ),
            ),
          ],
        ),
        if (_vehFound == true) ...[
          const SizedBox(height: 10),
          _vehBanner(true,
              'Vehicle found — details filled in below. Check them over and add your mileage.'),
        ] else if (_vehFound == false) ...[
          const SizedBox(height: 10),
          _vehBanner(false,
              'We couldn\'t find that reg. No problem — just fill the details in below.'),
        ],
        const SizedBox(height: 18),

        // Mileage + unit
        _sectionLabel('Mileage'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _mileageCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _clear(() => _errMileage = null),
                decoration: _dec('e.g. 45000',
                    error: _errMileage,
                    filled: _mileageCtrl.text.trim().isNotEmpty),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              child: DropdownButtonFormField<String>(
                initialValue: _mileageUnit,
                decoration: _dec('', filled: true),
                items: const [
                  DropdownMenuItem(value: 'Miles', child: Text('Miles')),
                  DropdownMenuItem(value: 'KM', child: Text('KM')),
                ],
                onChanged: (v) => setState(() => _mileageUnit = v ?? 'Miles'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Structured spec fields, gated by the category's vehicle_data flags.
        ..._vehicleFields(),

        const SizedBox(height: 6),
        _verifyBlock(),
        const Divider(height: 30),
      ],
    );
  }

  /// The Greenlight ownership check: enter the log book (V5C/VRC) number and
  /// we confirm it against the reg. A match earns the free Greenlight badge.
  Widget _verifyBlock() {
    if (_verified == true) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.success, size: 30),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Greenlight badge earned',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          color: AppColors.success)),
                  SizedBox(height: 2),
                  Text('Your ownership is verified — buyers will see the green '
                      'Greenlight tick on your ad.',
                      style: TextStyle(color: AppColors.slate, fontSize: 12.8)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_outlined,
                size: 30, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Verify ownership (optional)',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Enter your log book number to earn a free Greenlight badge '
                    '— it shows buyers your vehicle is genuine.',
                    style: const TextStyle(
                        color: AppColors.slate, fontSize: 12.8, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _logbookCtrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_verified == false) setState(() => _verified = null);
                },
                decoration: _dec('Log book (V5C) number',
                    filled: _logbookCtrl.text.trim().isNotEmpty),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 54,
              width: 92,
              child: OutlinedButton(
                onPressed: _verifying ? null : _verifyOwnership,
                child: _verifying
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Check'),
              ),
            ),
          ],
        ),
        if (_verified == false)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'That log book number didn\'t match this reg. Double-check the '
              '10-character code on the top-right of your log book.',
              style: TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Future<void> _verifyOwnership() async {
    final reg = _regCtrl.text.trim().toUpperCase();
    final vrc = _logbookCtrl.text.trim();
    if (reg.isEmpty) {
      _toast('Enter your registration and tap Find first.');
      return;
    }
    if (vrc.isEmpty) {
      _toast('Enter your log book (V5C) number to verify.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _verifying = true);
    try {
      final ok = await widget.api.verifyVehicleOwnership(reg, vrc);
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verified = ok;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verified = false;
      });
      _toast('Couldn\'t reach the verification service — try again in a moment.');
    }
  }

  List<Widget> _vehicleFields() {
    final w = <Widget>[];
    if (_wantsField('make')) {
      w.add(_vehText('Make', _makeCtrl,
          hint: 'e.g. Volkswagen', error: _errMake, onCleared: () => _errMake = null));
    }
    if (_wantsField('model')) {
      w.add(_vehText('Model', _modelCtrl,
          hint: 'e.g. Golf', error: _errModel, onCleared: () => _errModel = null));
    }
    if (_wantsField('variant')) {
      w.add(_vehText('Variant', _variantCtrl, hint: 'e.g. GT TSI'));
    }
    if (_wantsField('year')) {
      w.add(_vehDrop('Year', _vYear, vehicleYears(),
          (v) => setState(() { _vYear = v; _errVYear = null; }), error: _errVYear));
    }
    if (_wantsField('fuel_type')) {
      w.add(_vehDrop('Fuel type', _fuelType, kFuelTypes,
          (v) => setState(() { _fuelType = v; _errFuel = null; }),
          error: _errFuel, titleCaseLabels: true));
    }
    if (_wantsField('transmission')) {
      w.add(_vehDrop('Transmission', _transmission, kTransmissions,
          (v) => setState(() => _transmission = v)));
    }
    if (_wantsField('body_type')) {
      w.add(_vehDrop('Body type', _bodyType, kBodyTypes,
          (v) => setState(() => _bodyType = v)));
    }
    if (_wantsField('colour')) {
      w.add(_vehDrop('Colour', _colour, kColours,
          (v) => setState(() => _colour = v), titleCaseLabels: true));
    }
    if (_wantsField('engine_size')) {
      w.add(_vehText('Engine size (cc)', _engineCtrl,
          hint: 'e.g. 1400', number: true));
    }
    if (_wantsField('number_of_doors')) {
      w.add(_vehDrop('Doors', _doors, kDoorOptions,
          (v) => setState(() => _doors = v)));
    }
    if (_wantsField('number_of_seats')) {
      w.add(_vehText('Seats', _seatsCtrl, hint: 'e.g. 5', number: true));
    }
    if (_wantsField('battery_range') &&
        _fuelType != null &&
        isBatteryFuel(_fuelType!)) {
      w.add(_vehText('Battery range', _batteryCtrl, hint: 'e.g. 250 miles'));
    }
    return w;
  }

  Widget _vehText(String label, TextEditingController c,
      {String? hint, String? error, bool number = false, VoidCallback? onCleared}) {
    return _field(
      label,
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        textCapitalization:
            number ? TextCapitalization.none : TextCapitalization.words,
        inputFormatters:
            number ? [FilteringTextInputFormatter.digitsOnly] : null,
        onChanged: (_) => setState(() {
          if (onCleared != null) onCleared();
        }),
        decoration:
            _dec(hint ?? '', error: error, filled: c.text.trim().isNotEmpty),
      ),
    );
  }

  Widget _vehDrop(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged,
      {String? error, bool titleCaseLabels = false}) {
    String lbl(String o) => titleCaseLabels ? _titleCase(o) : o;
    // If a lookup returned a value that isn't in our list, keep it selectable
    // rather than silently dropping it.
    final items = (value == null || options.contains(value))
        ? options
        : [value, ...options];
    return _field(
      label,
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: _dec('Please select…',
            error: error, filled: (value ?? '').isNotEmpty),
        items: [
          for (final o in items)
            DropdownMenuItem(value: o, child: Text(lbl(o))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _vehBanner(bool ok, String text) {
    final color = ok ? AppColors.success : const Color(0xFFB45309);
    final bg = (ok ? AppColors.success : const Color(0xFFF59E0B))
        .withValues(alpha: 0.10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.info_rounded,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color,
                    fontSize: 12.8,
                    height: 1.3,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _titleCase(String t) => t.isEmpty
      ? t
      : t
          .toLowerCase()
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

  String? _matchOption(List<String> options, String value) {
    if (value.isEmpty) return null;
    for (final o in options) {
      if (o.toLowerCase() == value.toLowerCase()) return o;
    }
    return null;
  }

  Future<void> _findVehicle() async {
    final reg = _regCtrl.text.trim().toUpperCase();
    if (reg.isEmpty) {
      setState(() => _errReg = 'Enter a registration to search.');
      return;
    }
    _regCtrl.text = reg;
    FocusScope.of(context).unfocus();
    setState(() {
      _vehLoading = true;
      _errReg = null;
    });
    try {
      final v = await widget.api.lookupVehicle(reg);
      if (!mounted) return;
      setState(() {
        _vehLoading = false;
        _verified = null; // different vehicle - any prior Greenlight is stale
        _logbookCtrl.clear();
        if (v == null || v.isEmpty) {
          _vehFound = false;
          _vehRaw = null;
        } else {
          _vehFound = true;
          _applyLookup(v);
        }
      });
    } catch (_) {
      // lookupVehicle already swallows errors, but stay safe: just invite
      // manual entry via the amber banner rather than a scary error.
      if (!mounted) return;
      setState(() {
        _vehLoading = false;
        _vehFound = false;
        _vehRaw = null;
      });
    }
  }

  /// Fill the spec fields from a lookup result (call inside setState).
  void _applyLookup(Map<String, dynamic> v) {
    _vehRaw = v;
    String s(dynamic x) => (x ?? '').toString().trim();
    void put(TextEditingController c, dynamic val) {
      final t = s(val);
      if (t.isNotEmpty && t != '-') c.text = t;
    }
    put(_makeCtrl, v['make']);
    put(_modelCtrl, v['model']);
    final variant = (s(v['variant']).isNotEmpty && s(v['variant']) != '-')
        ? s(v['variant'])
        : (s(v['title']) == '-' ? '' : s(v['title']));
    if (variant.isNotEmpty) _variantCtrl.text = variant;
    put(_engineCtrl, v['engine_size']);
    put(_seatsCtrl, v['number_of_seats']);
    put(_batteryCtrl, v['battery_range']);
    _bodyType = _matchOption(kBodyTypes, s(v['body_type'])) ?? _bodyType;
    _fuelType = _matchOption(kFuelTypes, s(v['fuel_type'])) ?? _fuelType;
    _colour = _matchOption(kColours, s(v['colour'])) ?? _colour;
    _transmission =
        _matchOption(kTransmissions, s(v['transmission'])) ?? _transmission;
    final yr = s(v['year']);
    if (yr.isNotEmpty) _vYear = yr;
    final d = s(v['number_of_doors']);
    if (d.isNotEmpty) _doors = d;
    final ml = s(v['milage']);
    if (ml.isNotEmpty && _mileageCtrl.text.trim().isEmpty) _mileageCtrl.text = ml;
    final mu = s(v['milage_unit']);
    if (mu.isNotEmpty) {
      _mileageUnit = mu.toUpperCase().startsWith('K') ? 'KM' : 'Miles';
    }
    _maybeAutoTitle();
  }

  /// Build a sensible ad title from the vehicle if the seller hasn't typed one.
  void _maybeAutoTitle() {
    if (_titleCtrl.text.trim().isNotEmpty) return;
    final parts = [
      _vYear ?? '',
      _makeCtrl.text.trim(),
      _modelCtrl.text.trim(),
      _variantCtrl.text.trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      _titleCtrl.text = _titleCase(parts.join(' '));
      _errTitle = null;
    }
  }

  /// The `vehicle_details` object sent with the ad. Starts from the raw lookup
  /// (so tax/CO2/NCT etc. persist) and lets the on-screen fields win.
  Map<String, dynamic> _buildVehicleDetails() {
    final m = <String, dynamic>{...?_vehRaw};
    void put(String k, String? val) {
      final t = (val ?? '').trim();
      if (t.isNotEmpty) m[k] = t;
    }
    put('registration_number', _regCtrl.text);
    put('milage', _mileageCtrl.text);
    m['milage_unit'] = _mileageUnit;
    put('make', _makeCtrl.text);
    put('model', _modelCtrl.text);
    put('variant', _variantCtrl.text);
    put('body_type', _bodyType);
    put('fuel_type', _fuelType);
    put('colour', _colour);
    put('year', _vYear);
    put('transmission', _transmission);
    put('engine_size', _engineCtrl.text);
    put('number_of_seats', _seatsCtrl.text);
    put('number_of_doors', _doors);
    put('battery_range', _batteryCtrl.text);
    m['found'] = _vehFound == true ? 1 : 0;
    // Greenlight badge: set only when the log book actually verified.
    m['is_vefied'] = _verified == true ? 1 : 0;
    return m;
  }

  // --- Photos --------------------------------------------------------------

  Widget _photosSection() {
    final hasError = _errPhotos != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos (up to $_maxPhotos)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_photos.isEmpty)
          InkWell(
            onTap: _pickPhotos,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 34),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: hasError ? AppColors.danger : AppColors.line,
                  width: 1.4,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 46,
                      color: hasError ? AppColors.danger : AppColors.primary),
                  const SizedBox(height: 10),
                  const Text('Add Photos',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Up to $_maxPhotos photos · .jpg, .png',
                      style: const TextStyle(color: AppColors.slate)),
                ],
              ),
            ),
          )
        else
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
        if (_photos.length >= _maxPhotos && _photoUpgradePlan != null)
          _photoUpgradeCard(_photoUpgradePlan!),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_errPhotos!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _photoTile(_Photo p, int index) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
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

  /// DoneDeal-style upsell shown when the current photo allowance is full and a
  /// plan with more photos exists. Tapping it selects that plan.
  Widget _photoUpgradeCard(Plan plan) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: () => _upgradeForPhotos(plan),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.add_photo_alternate_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Need more photos?',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(
                        'Upgrade to ${plan.name} — £${_money(plan.price)} for up to ${plan.photos} photos',
                        style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12.5,
                            height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  void _upgradeForPhotos(Plan plan) {
    setState(() => _selectedPlan = plan);
    _toast(
        'Upgraded to ${plan.name} — you can now add up to ${plan.photos} photos');
  }

  /// Select a plan. If it allows fewer photos than the seller has already
  /// added, trim the extras straight away and tell them — so downgrading to a
  /// smaller plan can never leave photos on the ad that wouldn't publish.
  void _selectPlan(Plan plan) {
    final newMax = plan.photos;
    final removed = _photos.length > newMax ? _photos.length - newMax : 0;
    setState(() {
      _selectedPlan = plan;
      if (removed > 0) _photos.removeRange(newMax, _photos.length);
    });
    if (removed > 0) {
      _toast('${plan.name} allows up to $newMax photos — removed the last '
          '$removed photo${removed == 1 ? '' : 's'}.');
    }
  }

  Widget _addPhotoTile() {
    return InkWell(
      onTap: _pickPhotos,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line, width: 1.4),
          borderRadius: BorderRadius.circular(AppRadius.control),
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

  /// The "Scan with Larry" card at the top of the form: snap a photo and the
  /// AI drafts the title, description and a rough price to edit before posting.
  Widget _scanCard() {
    return InkWell(
      onTap: _scanning ? null : _startScan,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: _scanning
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_scanning ? 'Larry is taking a look…' : 'Scan with Larry',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      _scanning
                          ? 'Reading your photo and drafting the details.'
                          : 'Snap a photo and I\'ll draft the title, description and a rough price for you.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          height: 1.3)),
                ],
              ),
            ),
            if (!_scanning) ...[
              const SizedBox(width: 8),
              const Icon(Icons.photo_camera_rounded, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }

  void _startScan() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _runScan(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _runScan(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Pick one photo, upload it (also adding it as the ad's photo) and let Larry
  /// draft the listing from it. Fails softly — the seller can always type it in.
  Future<void> _runScan(ImageSource source) async {
    final picker = ImagePicker();
    XFile? x;
    try {
      x = await picker.pickImage(
          source: source, imageQuality: 82, maxWidth: 1600);
    } catch (e) {
      _toast('Could not open that — try the other option.');
      return;
    }
    if (x == null) return;
    final file = File(x.path);
    setState(() => _scanning = true);
    try {
      final url = await widget.api.uploadPhoto(file);
      // Reuse the same photo on the ad (already uploaded) if there's room.
      if (_photos.length < _maxPhotos) {
        final p = _Photo(localPath: x.path)
          ..uploading = false
          ..url = url;
        setState(() {
          _photos.add(p);
          _errPhotos = null;
        });
      }
      final result = await widget.api.scanItem(url);
      if (!mounted) return;
      if (result == null) {
        _toast('Larry couldn\'t reach the scanner — just fill it in below.');
      } else if (result.isEmpty) {
        _toast(
            'Larry couldn\'t quite make that out — try a clearer photo, or fill it in below.');
      } else {
        setState(() {
          // A scan is an explicit request for Larry's draft, so refresh the
          // fields with the latest result (this is what lets a re-scan of a
          // different photo update the title/description). Only skip a field
          // when the new scan didn't return that piece, so we never blank one.
          if (result.title.trim().isNotEmpty) _titleCtrl.text = result.title;
          if (result.description.trim().isNotEmpty) {
            _descCtrl.text = result.description;
          }
          if (result.price != null) {
            _priceCtrl.text = '${result.price}';
            _poa = false;
          }
          _errTitle = _errDesc = _errPrice = null;
        });
        final note = result.priceNote.trim();
        _toast(
            'Larry filled in the details — have a read and tweak anything.${note.isEmpty ? '' : ' $note'}');
      }
    } catch (e) {
      if (mounted) {
        _toast('Larry couldn\'t scan that — just fill it in below.');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
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
        setState(() {
          _photos.add(photo);
          _errPhotos = null;
        });
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

  // --- Publish bar ---------------------------------------------------------

  Widget _publishBar() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _publishing ? null : _submit,
        child: _publishing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(_planPrice == 0
                ? 'Place ad'
                : 'Place ad — £${_money(_activePlan!.price)}'),
      ),
    );
  }

  // --- shared bits ---------------------------------------------------------

  /// A labelled form block: a bold label (with an optional trailing widget such
  /// as the "Verified" badge) above the field, then 14px of breathing room.
  Widget _field(String label, Widget child, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        child,
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _radio(String label, int value) {
    final selected = _adType == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _adType = value),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.white,
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.line,
                width: 1.4),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.muted,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.primary : AppColors.slate)),
            ],
          ),
        ),
      ),
    );
  }

  /// A bordered "allow contact by" row: label on the left, a blue tick box on
  /// the right, matching DoneDeal's contact cards.
  Widget _contactCard(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: value ? AppColors.primary : AppColors.muted,
                    width: 1.6),
              ),
              child: value
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Flag + dial-code button that opens the country sheet. Isle of Man and the
  /// UK both dial +44, so the flag is how the seller (and buyers) tell them
  /// apart.
  Widget _countryPicker() => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: _pickCountry,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppRadius.control),
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
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
    if (picked != null) {
      setState(() {
        _country = picked;
        _flagLocked = true;
      });
    }
  }

  InputDecoration _dec(String hint, {String? error, bool filled = false}) {
    // As a field is completed its outline darkens from light grey to a clear
    // dark grey, so a seller can see at a glance what's still to fill in.
    final restColor = filled ? AppColors.muted : AppColors.line;
    final restWidth = filled ? 1.4 : 1.0;
    return InputDecoration(
        hintText: hint,
        errorText: error,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: restColor, width: restWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: restColor, width: restWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      );
  }
}

/// A single photo being added: local file path plus its hosted URL once the
/// Cloudinary upload completes.
/// Forces a field to upper case as the user types (number plates are always
/// capitals). Keeps the caret where it was so typing feels natural.
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

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
