import 'package:flutter/material.dart';

import '../widgets/network_photo.dart';

/// Full-screen photo viewer, DoneDeal-style: swipe through every photo with an
/// "Image X/N" counter, pinch to zoom, and a top-right button that flips to a
/// tile grid of all photos. Tapping a tile jumps straight to that photo.
class PhotoViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const PhotoViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pager =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _grid = false;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _openAt(int i) {
    setState(() {
      _index = i;
      _grid = false;
    });
    // Jump the pager once it's rebuilt into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pager.hasClients) _pager.jumpToPage(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.images;
    final n = photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: close, counter, grid toggle.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      _grid ? 'All photos ($n)' : 'Image ${_index + 1}/$n',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: _grid ? 'Single photo' : 'All photos',
                    icon: Icon(
                      _grid ? Icons.image_rounded : Icons.grid_view_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => setState(() => _grid = !_grid),
                  ),
                ],
              ),
            ),
            Expanded(child: _grid ? _gridView(photos) : _pagerView(photos)),
          ],
        ),
      ),
    );
  }

  Widget _pagerView(List<String> photos) {
    return PageView.builder(
      controller: _pager,
      itemCount: photos.length,
      onPageChanged: (i) => setState(() => _index = i),
      itemBuilder: (_, i) => InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        // Fill the viewport and let BoxFit.contain scale up to fit. Without an
        // expanded box a low-res photo would render at its tiny intrinsic size.
        child: SizedBox.expand(
          child: NetworkPhoto(url: photos[i], fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _gridView(List<String> photos) {
    return GridView.builder(
      padding: const EdgeInsets.all(3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: photos.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => _openAt(i),
        child: Container(
          color: const Color(0xFF111111),
          child: NetworkPhoto(url: photos[i], fit: BoxFit.cover),
        ),
      ),
    );
  }
}
