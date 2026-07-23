/// Current conditions for the home-screen weather line. Small and display-only.
class Weather {
  final double tempC;
  final int code; // WMO weather-interpretation code
  final String place;

  const Weather({required this.tempC, required this.code, required this.place});

  int get tempRounded => tempC.round();

  /// A friendly label + emoji for the WMO code. Grouped so the ~30 codes map
  /// onto a handful of everyday conditions.
  String get description => _wmo(code).$1;
  String get emoji => _wmo(code).$2;

  static (String, String) _wmo(int c) {
    if (c == 0) return ('Clear', '☀️');
    if (c == 1 || c == 2) return ('Partly cloudy', '🌤️');
    if (c == 3) return ('Overcast', '☁️');
    if (c == 45 || c == 48) return ('Fog', '🌫️');
    if (c >= 51 && c <= 57) return ('Drizzle', '🌦️');
    if (c >= 61 && c <= 67) return ('Rain', '🌧️');
    if (c >= 71 && c <= 77) return ('Snow', '🌨️');
    if (c >= 80 && c <= 82) return ('Showers', '🌦️');
    if (c == 85 || c == 86) return ('Snow showers', '🌨️');
    if (c >= 95) return ('Thunderstorm', '⛈️');
    return ('', '🌡️');
  }
}
