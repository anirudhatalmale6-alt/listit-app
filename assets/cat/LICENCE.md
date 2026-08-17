# Section artwork

The section illustrations in this folder come from Microsoft's Fluent Emoji set
(the 3D style), which is published under the MIT licence: free to use in a
commercial product, modify and redistribute, with no attribution required in the
app itself.

    https://github.com/microsoft/fluentui-emoji
    Copyright (c) Microsoft Corporation — MIT Licence

One file per category slug (`property.png`, `cars-and-motors.png`, ...), which is
how `_catArtFor` in `lib/screens/browse_screen.dart` finds them. A section with no
file here falls back to the category image from the website, then to a flat icon,
so adding a new section never leaves an empty tile.

Swapping in bespoke artwork later means dropping in PNGs with the same names —
no code change.
