/// Central place for every backend endpoint the app talks to.
///
/// The live Listit API is the same one the website uses. Routes are mounted
/// under two prefixes on the server:
///   /api/user/*  -> the public marketplace routes (search, ad detail, ...)
///   /admin/*     -> read-only reference data the site also consumes
///                   (the category tree lives here)
/// Uploaded images (category icons, verification badges) are served from
/// `${host}/assets/...`. Ad photos already come back as absolute Cloudinary
/// URLs, so they never need the asset base.
class ApiConfig {
  ApiConfig._();

  /// Backend host. Defaults to production; override at build time with
  /// `--dart-define=API_HOST=https://staging-api.listit.im` for staging, or an
  /// empty value to make every URL relative (used for the same-origin web
  /// preview that sits behind a proxy).
  static const String host =
      String.fromEnvironment('API_HOST', defaultValue: 'https://api.listit.im');

  static const String userBase = '$host/api/user';
  static const String authBase = '$host/api/auth';
  static const String assetBase = '$host/assets';

  // --- Phase 1 endpoints ---------------------------------------------------
  static const String categories = '$host/admin/category-new';

  /// Per-category attribute definitions (Bedrooms, Storage, ...) used to build
  /// dynamic filters and the Sell form's extra fields, exactly like the site.
  static const String attributes = '$host/admin/attribute';

  /// Site-wide settings the website also reads (social links, banner images,
  /// contact details) as `{ col, value }` rows. Same source as the website
  /// footer, so the app stays in step with whatever is set on the site.
  static const String settings = '$host/admin/setting';
  static const String search = '$userBase/search';
  static String featuredDealers(String sector) =>
      '$userBase/featured-dealers?sector=$sector';
  static String adDetail(int id) => '$userBase/ads/$id';
  static const String similarAds = '$userBase/similar-ads';

  /// Distinct vehicle attribute values (makes, fuel types, body types,
  /// colours) with live counts - drives the car-search make list and filters.
  static const String popularSearches = '$userBase/popular_searches';

  // --- Phase 2 endpoints (auth) --------------------------------------------
  static const String saveAd = '$userBase/save-ad';
  static const String reportAd = '$userBase/ad-report';
  static const String supportEmail = 'hello@listit.im';

  // --- Saved searches ------------------------------------------------------
  static const String saveSearch = '$userBase/save-search';

  // --- Messaging + offers --------------------------------------------------
  static const String conversation = '$userBase/conversation';
  static const String message = '$userBase/message';
  static const String makeOffer = '$userBase/make-offer';
  static const String respondOffer = '$userBase/respond-offer';
  static const String unreadCount = '$userBase/unread-count';
  static const String profile = '$userBase/profile';
  static const String updateBasicProfile = '$userBase/update-basic-profile';
  static const String login = '$authBase/login';
  static const String register = '$authBase/register';
  static const String socialLogin = '$authBase/social-login';
  static const String facebookLogin = '$authBase/facebook';
  static const String googleLogin = '$authBase/google';

  /// Google "Web application" OAuth client ID (Google Cloud > "Listit Web").
  /// Passed as google_sign_in's serverClientId so the returned idToken is
  /// audienced to us and the backend can verify it.
  static const String googleServerClientId =
      '743666985512-7ldqjbh080t04kko1660q199no51p8dj.apps.googleusercontent.com';

  // --- Verification (email + phone OTP) ------------------------------------
  static const String sendOtp = '$authBase/resend-otp';
  static const String verifyOtp = '$authBase/verify-user';

  // Reveal a dealer's main contact number (no login required).
  static const String dealerPhone = '$userBase/dealer-phone';
  static const String sellerPhone = '$userBase/seller-phone';

  // --- Selling (place an ad) -----------------------------------------------
  static const String createAd = '$userBase/ads';
  static const String plans = '$userBase/plan';
  static const String uploadImage = '$host/api/upload-image-cloudinary';

  /// Larry's photo scan — send an uploaded image URL, get a drafted
  /// title / description / rough price back.
  static const String scanItem = '$userBase/ai/scan-item';

  /// Registration lookup for the Sell form's Vehicle Details (the "Find"
  /// button). Same endpoint the website uses to fetch DVLA-style details.
  static const String vehicleLookup = '$userBase/vehicles';

  /// Ownership check against the log book (V5C/VRC) number - a match earns the
  /// free Greenlight badge on the ad.
  static const String verifyOwnership = '$userBase/verify-ownership';

  /// Resolve a stored image path to a fully-qualified URL. Absolute URLs
  /// (Cloudinary, https://...) are returned untouched.
  static String resolveImage(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return '$assetBase/$clean';
  }
}
