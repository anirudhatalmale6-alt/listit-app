/// The set of filters applied to a category / search results screen. Maps
/// straight onto the parameters the website's `/search` endpoint understands
/// (price_from/price_to, location, ad_type, sellerType, sort_by/sort_order).
///
/// Vehicle categories (Cars For Sale, Campers, ...) also carry the make / year /
/// mileage / fuel / body / transmission / colour filters, which the backend
/// resolves through its `dynamic` object (makeModel + ranges + filter) exactly
/// as the website's car search does.
enum AdSort { newest, priceLow, priceHigh }

extension AdSortLabel on AdSort {
  String get label {
    switch (this) {
      case AdSort.newest:
        return 'Newest first';
      case AdSort.priceLow:
        return 'Price: low to high';
      case AdSort.priceHigh:
        return 'Price: high to low';
    }
  }
}

class AdFilters {
  final String? priceFrom;
  final String? priceTo;
  final String? location;
  final List<String> sellerTypes; // any of 'private','trader','agent'; empty = everyone
  final int? adType; // 1 = for sale, 2 = wanted, null = any
  final int? minRating; // e.g. 4 = "4+ rated sellers only"
  final bool priceOnly; // hide POA / price-less ads
  final AdSort sort;

  // --- Vehicle-only filters (ignored for non-vehicle categories) -----------
  final List<String> makes; // selected makes, e.g. ['FORD', 'BMW']
  final List<String> models; // base model names, e.g. ['FOCUS', 'GOLF']
  final String? yearFrom;
  final String? yearTo;
  final String? mileageTo; // "up to N miles"
  final List<String> fuelTypes;
  final List<String> bodyTypes;
  final List<String> transmissions;
  final List<String> colours;

  // --- Dynamic per-category attribute filters ------------------------------
  // key -> selected values, e.g. {'bedrooms': ['3','4'], 'property_type':
  // ['house']}. Built from the category's attributes and sent to the backend
  // in the same `dynamic.filter` list the website uses.
  final Map<String, List<String>> attributes;

  const AdFilters({
    this.priceFrom,
    this.priceTo,
    this.location,
    this.sellerTypes = const [],
    this.adType,
    this.minRating,
    this.priceOnly = false,
    this.sort = AdSort.newest,
    this.makes = const [],
    this.models = const [],
    this.yearFrom,
    this.yearTo,
    this.mileageTo,
    this.fuelTypes = const [],
    this.bodyTypes = const [],
    this.transmissions = const [],
    this.colours = const [],
    this.attributes = const {},
  });

  AdFilters copyWith({
    String? priceFrom,
    String? priceTo,
    String? location,
    List<String>? sellerTypes,
    int? adType,
    int? minRating,
    bool? priceOnly,
    AdSort? sort,
    List<String>? makes,
    List<String>? models,
    String? yearFrom,
    String? yearTo,
    String? mileageTo,
    List<String>? fuelTypes,
    List<String>? bodyTypes,
    List<String>? transmissions,
    List<String>? colours,
    Map<String, List<String>>? attributes,
    bool clearPriceFrom = false,
    bool clearPriceTo = false,
    bool clearLocation = false,
    bool clearSeller = false,
    bool clearAdType = false,
    bool clearMinRating = false,
    bool clearYearFrom = false,
    bool clearYearTo = false,
    bool clearMileageTo = false,
  }) {
    return AdFilters(
      priceFrom: clearPriceFrom ? null : (priceFrom ?? this.priceFrom),
      priceTo: clearPriceTo ? null : (priceTo ?? this.priceTo),
      location: clearLocation ? null : (location ?? this.location),
      sellerTypes: clearSeller ? const [] : (sellerTypes ?? this.sellerTypes),
      adType: clearAdType ? null : (adType ?? this.adType),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      priceOnly: priceOnly ?? this.priceOnly,
      sort: sort ?? this.sort,
      makes: makes ?? this.makes,
      models: models ?? this.models,
      yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
      yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
      mileageTo: clearMileageTo ? null : (mileageTo ?? this.mileageTo),
      fuelTypes: fuelTypes ?? this.fuelTypes,
      bodyTypes: bodyTypes ?? this.bodyTypes,
      transmissions: transmissions ?? this.transmissions,
      colours: colours ?? this.colours,
      attributes: attributes ?? this.attributes,
    );
  }

  /// Attribute filters that actually have a value picked.
  Map<String, List<String>> get _activeAttributes =>
      {for (final e in attributes.entries) if (e.value.isNotEmpty) e.key: e.value};
  bool get _hasAttributes => _activeAttributes.isNotEmpty;

  bool get _hasYear => (yearFrom ?? '').isNotEmpty || (yearTo ?? '').isNotEmpty;
  bool get _hasVehicle =>
      makes.isNotEmpty ||
      models.isNotEmpty ||
      _hasYear ||
      (mileageTo ?? '').isNotEmpty ||
      fuelTypes.isNotEmpty ||
      bodyTypes.isNotEmpty ||
      transmissions.isNotEmpty ||
      colours.isNotEmpty;

  /// How many filters are actively narrowing the results (sort doesn't count).
  int get activeCount {
    var n = 0;
    if ((priceFrom ?? '').isNotEmpty) n++;
    if ((priceTo ?? '').isNotEmpty) n++;
    if ((location ?? '').isNotEmpty) n++;
    if (sellerTypes.isNotEmpty) n++;
    if (adType != null) n++;
    if (minRating != null) n++;
    if (priceOnly) n++;
    if (makes.isNotEmpty || models.isNotEmpty) n++;
    if (_hasYear) n++;
    if ((mileageTo ?? '').isNotEmpty) n++;
    if (fuelTypes.isNotEmpty) n++;
    if (bodyTypes.isNotEmpty) n++;
    if (transmissions.isNotEmpty) n++;
    if (colours.isNotEmpty) n++;
    n += _activeAttributes.length;
    return n;
  }

  bool get hasAny => activeCount > 0 || sort != AdSort.newest;

  Map<String, dynamic> toQuery() {
    final m = <String, dynamic>{};
    if ((priceFrom ?? '').isNotEmpty) m['price_from'] = priceFrom;
    if ((priceTo ?? '').isNotEmpty) m['price_to'] = priceTo;
    if ((location ?? '').isNotEmpty) m['location'] = location;
    if (sellerTypes.isNotEmpty) m['seller_types'] = sellerTypes.join(',');
    if (adType != null) m['ad_type'] = adType;
    if (minRating != null) m['min_rating'] = minRating;
    if (priceOnly) m['price_only'] = 1;

    // Vehicle + category-attribute filters ride along in the backend's
    // `dynamic` object, exactly as the website's search does.
    if (_hasVehicle || _hasAttributes) {
      final makeModel = _hasVehicle ? [for (final mk in makes) {'make': mk}] : [];
      final ranges = <Map<String, dynamic>>[];
      final filter = <Map<String, dynamic>>[];

      if (_hasVehicle) {
        if (_hasYear) {
          ranges.add({'key': 'year', 'from': yearFrom ?? '', 'to': yearTo ?? ''});
        }
        if ((mileageTo ?? '').isNotEmpty) {
          ranges.add({'key': 'milage', 'from': '', 'to': mileageTo});
        }
        // Models match loosely (LIKE) so a base name like "FOCUS" still catches
        // the trim-level values ("FOCUS T ECOBOOST ST-3") stored against ads.
        if (models.isNotEmpty) filter.add({'key': 'model', 'values': models});
        if (fuelTypes.isNotEmpty) filter.add({'key': 'fuel_type', 'values': fuelTypes});
        if (bodyTypes.isNotEmpty) filter.add({'key': 'body_type', 'values': bodyTypes});
        if (transmissions.isNotEmpty) {
          filter.add({'key': 'transmission', 'values': transmissions});
        }
        if (colours.isNotEmpty) filter.add({'key': 'colour', 'values': colours});
        m['is_vehicle'] = 1;
      }

      // Dynamic per-category attribute filters (bedrooms, storage, ...).
      for (final e in _activeAttributes.entries) {
        filter.add({'key': e.key, 'values': e.value});
      }

      m['dynamic'] = {
        'makeModel': makeModel,
        'ranges': ranges,
        'filter': filter,
      };
    }

    switch (sort) {
      case AdSort.newest:
        // Match the website, which orders by when an ad was last bumped/
        // published (`last_bump_at`) rather than raw id, so the app and site
        // show listings in the same chronological order.
        m['sort_by'] = 'last_bump_at';
        m['sort_order'] = 'DESC';
        break;
      case AdSort.priceLow:
        m['sort_by'] = 'price';
        m['sort_order'] = 'ASC';
        break;
      case AdSort.priceHigh:
        m['sort_by'] = 'price';
        m['sort_order'] = 'DESC';
        break;
    }
    return m;
  }
}
