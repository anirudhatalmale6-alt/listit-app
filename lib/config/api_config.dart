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
  static const String search = '$userBase/search';
  static String adDetail(int id) => '$userBase/ads/$id';
  static const String similarAds = '$userBase/similar-ads';

  // --- Phase 2 endpoints (auth) --------------------------------------------
  static const String saveAd = '$userBase/save-ad';
  static const String profile = '$userBase/profile';
  static const String login = '$authBase/login';
  static const String register = '$authBase/register';
  static const String socialLogin = '$authBase/social-login';

  /// Resolve a stored image path to a fully-qualified URL. Absolute URLs
  /// (Cloudinary, https://...) are returned untouched.
  static String resolveImage(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return '$assetBase/$clean';
  }
}
