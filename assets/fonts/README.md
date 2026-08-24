# App typeface

The app bundles no font. It uses whichever typeface the phone itself uses -
Roboto on Android, San Francisco on iOS - which is what `lib/theme.dart` means
by having no `fontFamily` set at all.

That is deliberate. DoneDeal's app does the same, which is why it reads as a
plain utility rather than a designed thing; matching a screenshot of theirs
letter for letter turned out to mean using no font of our own. It also means the
app looks native on both platforms instead of native on neither, and carries
about 160 KB less.

To go back to a bundled face, drop four TTFs in this folder, declare them in
`pubspec.yaml` under `fonts:`, and set `fontFamily` in `lib/theme.dart`. Those
are the only two places in the app that name a typeface.
