import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/vehicle_catalog.dart';
import '../theme.dart';
import '../utils/vehicle_names.dart';

/// What the picker hands back: the makes to filter on, plus any specific models
/// (base names) picked under them. The results screen turns these into the
/// backend's makeModel + model filter.
class MakeModelSelection {
  final List<String> makes;
  final List<String> models;
  const MakeModelSelection(this.makes, this.models);
}

/// A DoneDeal-style make & model picker: a searchable list of makes, each a
/// full-width checkbox row (tap anywhere to tick it), with an expand arrow to
/// reveal its models (also checkboxes). "Select all" is pinned at the top so
/// it's always reachable. Controls sit on the left by default, or on the right
/// in left-hand mode.
class MakeModelPickerScreen extends StatefulWidget {
  final List<String> initialMakes;
  final List<String> initialModels;

  /// The section's vehicle-type bucket (c=car, m=bike, v=van, ...). When set,
  /// only makes/models of that type are shown - so the Cars section lists cars,
  /// the Motorbikes section lists bikes, etc. Null shows everything.
  final String? bucket;

  const MakeModelPickerScreen({
    super.key,
    this.initialMakes = const [],
    this.initialModels = const [],
    this.bucket,
  });

  @override
  State<MakeModelPickerScreen> createState() => _MakeModelPickerScreenState();
}

class _MakeModelPickerScreenState extends State<MakeModelPickerScreen> {
  List<CatMake> _catalog = const [];
  bool _loading = true;
  String _q = '';

  // Make-level selections, and per-make model selections. A make is either
  // selected whole (in _makes) or narrowed to some models (in _models) - never
  // both, so picking one clears the other for that make.
  final Set<String> _makes = {};
  final Map<String, Set<String>> _models = {};
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _makes.addAll(widget.initialMakes);
    _load();
  }

  Future<void> _load() async {
    final all = await VehicleCatalog.load();
    if (!mounted) return;
    // Limit to the section's vehicle type (cars for the Cars section, etc.).
    final cat = VehicleCatalog.makesFor(all, widget.bucket);
    for (final m in widget.initialModels) {
      for (final make in cat) {
        if (make.models.any((x) => x.model == m)) {
          _models.putIfAbsent(make.make, () => {}).add(m);
          _makes.remove(make.make);
          _expanded.add(make.make); // open makes that have a model picked
          break;
        }
      }
    }
    setState(() {
      _catalog = cat;
      _loading = false;
    });
  }

  bool get _allSelected =>
      _catalog.isNotEmpty && _makes.length == _catalog.length && _models.isEmpty;

  void _toggleAll(bool on) {
    setState(() {
      _makes.clear();
      _models.clear();
      if (on) _makes.addAll(_catalog.map((m) => m.make));
    });
  }

  void _toggleMake(String make, bool on) {
    setState(() {
      _models.remove(make);
      on ? _makes.add(make) : _makes.remove(make);
    });
  }

  List<String> _modelsFor(String make) {
    for (final m in _catalog) {
      if (m.make == make) {
        return [for (final x in m.modelsFor(widget.bucket)) x.model];
      }
    }
    return const [];
  }

  void _toggleModel(String make, String model, bool on) {
    setState(() {
      if (_makes.remove(make)) {
        _models[make] = _modelsFor(make).toSet();
      }
      final set = _models.putIfAbsent(make, () => {});
      on ? set.add(model) : set.remove(model);
      if (set.isEmpty) _models.remove(make);
    });
  }

  int get _selectionCount =>
      _makes.length + _models.values.fold(0, (a, s) => a + s.length);

  void _apply() {
    final makes = <String>{..._makes, ..._models.keys}.toList();
    final models = <String>[for (final s in _models.values) ...s];
    Navigator.of(context).pop(MakeModelSelection(makes, models));
  }

  // Right-hand (default): tick boxes on the RIGHT, nearest the right thumb.
  // Left-hand mode: boxes move to the LEFT.
  bool get _leftHanded => AppSettings.leftHanded.value;

  /// One selectable row - a checkbox that sits on the thumb side (right by
  /// default, left in left-hand mode) with the label and any count/chevron
  /// filling the rest. Tapping anywhere on the row toggles it.
  Widget _selectRow({
    required Widget checkbox,
    required Widget label,
    List<Widget> middle = const [],
    required VoidCallback onTap,
    required EdgeInsets padding,
    Color? background,
  }) {
    return Material(
      color: background ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (_leftHanded) ...[checkbox, const SizedBox(width: 10)],
              Expanded(child: label),
              ...middle,
              if (!_leftHanded) ...[const SizedBox(width: 6), checkbox],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final visible = q.isEmpty
        ? _catalog
        : _catalog.where((m) => m.make.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Make & model'),
        actions: [
          if (_selectionCount > 0)
            TextButton(
              onPressed: () => setState(() {
                _makes.clear();
                _models.clear();
              }),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: 'Start typing a make',
                      prefixIcon:
                          const Icon(Icons.search, color: AppColors.slate),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                // "Select all" is pinned here, so it never scrolls out of reach.
                _selectRow(
                  background: AppColors.surface,
                  checkbox: Checkbox(
                    activeColor: AppColors.primary,
                    value: _allSelected,
                    onChanged: (v) => _toggleAll(v ?? false),
                  ),
                  label: const Text('Select all makes',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _toggleAll(!_allSelected),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _makeTile(visible[i]),
                  ),
                ),
                _bottomBar(),
              ],
            ),
    );
  }

  Widget _makeTile(CatMake m) {
    final selectedModels = _models[m.make] ?? const <String>{};
    final makeChecked = _makes.contains(m.make);
    final anyModel = selectedModels.isNotEmpty;
    final expanded = _expanded.contains(m.make);
    final models = m.modelsFor(widget.bucket);
    return Column(
      children: [
        _selectRow(
          checkbox: Checkbox(
            activeColor: AppColors.primary,
            tristate: true,
            value: makeChecked ? true : (anyModel ? null : false),
            onChanged: (_) => _toggleMake(m.make, !makeChecked),
          ),
          label: Text(prettyVehicleName(m.make),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
          middle: [
            if (m.count > 0)
              Text('${m.count}',
                  style: const TextStyle(color: AppColors.slate, fontSize: 13)),
            if (models.isNotEmpty)
              IconButton(
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.slate,
                ),
                onPressed: () => setState(() => expanded
                    ? _expanded.remove(m.make)
                    : _expanded.add(m.make)),
              )
            else
              const SizedBox(width: 12),
          ],
          onTap: () => _toggleMake(m.make, !makeChecked),
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        ),
        if (expanded)
          for (final md in models)
            _selectRow(
              checkbox: Checkbox(
                activeColor: AppColors.primary,
                value: makeChecked || selectedModels.contains(md.model),
                onChanged: (v) => _toggleModel(m.make, md.model, v ?? false),
              ),
              label: Text(prettyVehicleName(md.model)),
              middle: [
                if (md.count > 0)
                  Text('${md.count}',
                      style: const TextStyle(
                          color: AppColors.slate, fontSize: 13)),
              ],
              onTap: () => _toggleModel(m.make, md.model,
                  !(makeChecked || selectedModels.contains(md.model))),
              padding: const EdgeInsets.fromLTRB(36, 2, 16, 2),
            ),
      ],
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card)),
            ),
            child: Text(
              _selectionCount == 0 ? 'Done' : 'Apply ($_selectionCount)',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
