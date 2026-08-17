import 'dart:async';
import 'package:flutter/material.dart';

import '../models/ad_filters.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/vehicle_catalog.dart';
import '../theme.dart';
import '../utils/vehicle_names.dart';
import '../screens/make_model_picker_screen.dart';
import '../screens/results_screen.dart';

/// The DoneDeal-style car-search block that leads the Cars & Motors tab: pick a
/// make, a year range and a price range, and the button shows how many cars
/// match before you even tap it. Runs the search against the Cars For Sale
/// section so make/year/price all resolve through the backend's vehicle filter.
class VehicleSearchPanel extends StatefulWidget {
  final ApiService api;
  final AuthService auth;

  /// The Cars For Sale category (a vehicle section) to search within.
  final Category carsCategory;

  const VehicleSearchPanel({
    super.key,
    required this.api,
    required this.auth,
    required this.carsCategory,
  });

  @override
  State<VehicleSearchPanel> createState() => _VehicleSearchPanelState();
}

class _VehicleSearchPanelState extends State<VehicleSearchPanel> {
  static final List<int> _years = [
    for (var y = DateTime.now().year; y >= 1990; y--) y
  ];
  static const List<int> _prices = [
    500, 1000, 1500, 2000, 3000, 5000, 7500, 10000,
    15000, 20000, 30000, 40000, 50000, 75000, 100000,
  ];

  List<String> _makes = [];
  List<String> _models = [];
  int? _yearFrom;
  int? _yearTo;
  int? _priceFrom;
  int? _priceTo;

  int? _count;
  bool _counting = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  AdFilters _buildFilters() {
    return AdFilters(
      makes: _makes,
      models: _models,
      yearFrom: _yearFrom?.toString(),
      yearTo: _yearTo?.toString(),
      priceFrom: _priceFrom?.toString(),
      priceTo: _priceTo?.toString(),
    );
  }

  /// A short summary of the make/model choice for the field and results title -
  /// "Ford", "Ford · 2 models", "3 makes · 4 models", or empty for all.
  String get _selectionSummary {
    if (_makes.isEmpty && _models.isEmpty) return '';
    final parts = <String>[];
    if (_makes.length == 1) {
      parts.add(prettyVehicleName(_makes.first));
    } else if (_makes.isNotEmpty) {
      parts.add('${_makes.length} makes');
    }
    if (_models.isNotEmpty) {
      parts.add('${_models.length} model${_models.length == 1 ? '' : 's'}');
    }
    return parts.join(' · ');
  }

  void _refreshCount() {
    _debounce?.cancel();
    setState(() => _counting = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final res = await widget.api.search(
          categoryId: widget.carsCategory.id,
          isVehicle: true,
          limit: 1,
          filters: _buildFilters().toQuery(),
        );
        if (mounted) {
          setState(() {
            _count = res.total;
            _counting = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _count = null;
            _counting = false;
          });
        }
      }
    });
  }

  void _runSearch() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        api: widget.api,
        auth: widget.auth,
        category: widget.carsCategory,
        initialFilters: _buildFilters(),
        titleOverride:
            _selectionSummary.isEmpty ? 'Cars For Sale' : _selectionSummary,
      ),
    ));
  }

  Future<void> _pickMake() async {
    // The full make + model picker (cars), so buyers can drill into models -
    // pick a make and its whole model range pops up to choose from.
    final res = await Navigator.of(context).push<MakeModelSelection>(
      MaterialPageRoute(
        builder: (_) => MakeModelPickerScreen(
          initialMakes: _makes,
          initialModels: _models,
          bucket: vehicleBucketForCategory(widget.carsCategory.id),
        ),
      ),
    );
    if (res != null) {
      setState(() {
        _makes = res.makes;
        _models = res.models;
      });
      _refreshCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Find your next car',
                  style: TextStyle(
                    fontSize: AppText.section,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Make & model picker (full width).
            _fieldButton(
              label: _selectionSummary.isEmpty
                  ? 'All makes & models'
                  : _selectionSummary,
              placeholder: _selectionSummary.isEmpty,
              onTap: _pickMake,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _dropdown<int>(
                    hint: 'Min year',
                    value: _yearFrom,
                    items: _years,
                    label: (y) => '$y',
                    onChanged: (v) {
                      setState(() {
                        _yearFrom = v;
                        if (_yearTo != null && v != null && _yearTo! < v) {
                          _yearTo = v;
                        }
                      });
                      _refreshCount();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dropdown<int>(
                    hint: 'Max year',
                    value: _yearTo,
                    items: _years,
                    label: (y) => '$y',
                    onChanged: (v) {
                      setState(() {
                        _yearTo = v;
                        if (_yearFrom != null && v != null && _yearFrom! > v) {
                          _yearFrom = v;
                        }
                      });
                      _refreshCount();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _dropdown<int>(
                    hint: 'Min price',
                    value: _priceFrom,
                    items: _prices,
                    label: _money,
                    onChanged: (v) {
                      setState(() => _priceFrom = v);
                      _refreshCount();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dropdown<int>(
                    hint: 'Max price',
                    value: _priceTo,
                    items: _prices,
                    label: _money,
                    onChanged: (v) {
                      setState(() => _priceTo = v);
                      _refreshCount();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _runSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.control)),
                ),
                icon: const Icon(Icons.search_rounded, size: 19),
                label: Text(
                  _counting || _count == null
                      ? 'Search cars'
                      : 'Search ${_grouped(_count!)} ${_count == 1 ? 'car' : 'cars'}',
                  style: const TextStyle(
                      fontSize: AppText.listing, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _money(int v) => '£${_grouped(v)}';

  /// A tappable field that looks like the dropdowns but opens a picker sheet.
  Widget _fieldButton({
    required String label,
    required bool placeholder,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.body,
                  color: placeholder ? AppColors.muted : AppColors.ink,
                  fontWeight: placeholder ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.slate),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint,
              style: const TextStyle(
                  fontSize: AppText.body, color: AppColors.muted)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.slate),
          style: const TextStyle(
              fontSize: AppText.body,
              color: AppColors.ink,
              fontWeight: FontWeight.w600),
          items: [
            DropdownMenuItem<T>(
                value: null,
                child: Text(hint,
                    style: const TextStyle(color: AppColors.muted))),
            for (final it in items)
              DropdownMenuItem<T>(value: it, child: Text(label(it))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}


String _grouped(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
