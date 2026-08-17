import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/ad.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/listing_specs.dart';
import '../widgets/network_photo.dart';
import 'ad_detail_screen.dart';

/// A DoneDeal/Zoopla-style map of the current property results: every listing
/// with coordinates drops a price pin over the Isle of Man. Tap a pin to see a
/// mini preview at the bottom, tap the preview to open the full ad.
class PropertyMapScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  final List<Ad> ads;
  final String title;

  const PropertyMapScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.ads,
    this.title = 'Property map',
  });

  @override
  State<PropertyMapScreen> createState() => _PropertyMapScreenState();
}

class _PropertyMapScreenState extends State<PropertyMapScreen> {
  late final List<_Pin> _pins;
  Ad? _selected;

  @override
  void initState() {
    super.initState();
    _pins = [
      for (final ad in widget.ads)
        if (_coord(ad) != null) _Pin(ad, _coord(ad)!),
    ];
  }

  static LatLng? _coord(Ad ad) {
    final lat = double.tryParse('${ad.raw['property_lat'] ?? ''}');
    final lng = double.tryParse('${ad.raw['property_lng'] ?? ''}');
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    // Sanity-bound to roughly the Isle of Man so a stray 0/garbage coordinate
    // can't throw the map out to the ocean.
    if (lat < 53.9 || lat > 54.5 || lng < -5.0 || lng > -4.2) return null;
    return LatLng(lat, lng);
  }

  String _price(Ad ad) {
    if (ad.price <= 0) return 'POA';
    final s = ad.price.round().toString();
    final b = StringBuffer('£');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Centre on Douglas; fit to the pins when we have some.
    const iom = LatLng(54.2361, -4.5481);
    final fit = _pins.length >= 2
        ? CameraFit.coordinates(
            coordinates: [for (final p in _pins) p.at],
            padding: const EdgeInsets.all(60),
            maxZoom: 14,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _pins.isEmpty
          ? _emptyState()
          : Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: _pins.isNotEmpty ? _pins.first.at : iom,
                    initialZoom: 10,
                    initialCameraFit: fit,
                    minZoom: 8,
                    maxZoom: 17,
                    onTap: (_, _) => setState(() => _selected = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'im.listit.listit_app',
                      maxZoom: 19,
                    ),
                    MarkerLayer(
                      markers: [
                        for (final p in _pins)
                          Marker(
                            point: p.at,
                            width: 96,
                            height: 34,
                            child: _pill(p.ad),
                          ),
                      ],
                    ),
                  ],
                ),
                // Attribution (OpenStreetMap requires it).
                const Positioned(
                  right: 6,
                  bottom: 4,
                  child: Text('© OpenStreetMap',
                      style:
                          TextStyle(fontSize: 9, color: AppColors.slate)),
                ),
                if (_selected != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: _previewCard(_selected!),
                  ),
              ],
            ),
    );
  }

  Widget _pill(Ad ad) {
    final selected = identical(ad, _selected);
    return GestureDetector(
      onTap: () => setState(() => _selected = ad),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
          child: Text(_price(ad),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _previewCard(Ad ad) {
    final chips = specChipsFor(ad);
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AdDetailScreen(
                adId: ad.id,
                api: widget.api,
                preview: ad,
                auth: widget.auth),
          ));
        },
        child: SizedBox(
          height: 96,
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 96,
                child: NetworkPhoto(url: ad.coverImage, fit: BoxFit.cover),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_price(ad),
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                      const SizedBox(height: 2),
                      Text(ad.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink)),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(chips.join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.slate)),
                      ],
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.chevron_right_rounded,
                    color: AppColors.slate),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.map_outlined, size: 56, color: AppColors.muted),
            SizedBox(height: 12),
            Text('No map locations for these listings yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            SizedBox(height: 6),
            Text(
                'These properties don\'t have map coordinates. Try widening your filters.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.slate)),
          ],
        ),
      ),
    );
  }
}

class _Pin {
  final Ad ad;
  final LatLng at;
  const _Pin(this.ad, this.at);
}
