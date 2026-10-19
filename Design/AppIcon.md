# CoffeeCup app icon

The app icon source is `CoffeeCup/AppIcon.icon`. Open that document in Apple's
Icon Composer to edit the appearance. The Xcode target already selects `AppIcon`
as its app icon; the synchronized `CoffeeCup` group includes the document in builds.

The coffee cup is a separate PNG layer with real alpha transparency. It does not
contain a black background, rounded tile, or baked-in shadow. Icon Composer supplies
the system background, mask, and Liquid Glass effects:

- Default: dark cup on the system light background.
- Dark: light cup on the system dark background.
- Mono: system-rendered clear/tinted appearance from the same layered design.

Xcode compiles the layered icon for recent macOS versions and generates a legacy
`AppIcon.icns` fallback for the app's macOS 13 minimum deployment target. Do not add
another flattened `AppIcon.appiconset` alongside this document; the opaque black
square in the old catalog caused the square-inside-a-tile appearance.

The menu bar's template symbol is independent and is intentionally unchanged.

## Foreground artwork provenance

The foreground was prepared with the built-in image-generation tool using the
previous CoffeeCup icon as the edit target. Two white-foreground extraction drafts
were rejected for rough edges; the selected black foreground is recolored in the
dark appearance by Icon Composer. The resulting alpha and native renders were
inspected before integration.

Final generation prompt:

> Use case: background-extraction
> Asset type: a macOS Icon Composer foreground mask.
> Edit target: existing white coffee-cup icon on black.
> Produce a PERFECTLY CLEAN BLACK silhouette of the same coffee cup with right handle, separate saucer, and separate S-shaped steam curl, on a GENUINELY TRANSPARENT background (RGBA alpha). Invert the white cup to solid black; REMOVE its black background completely to transparent. Preserve the original proportions and placement. This is flat logo artwork, smooth solid shapes, not a photo. Keep the gap below steam, gap above saucer, and handle hole fully clear. Absolutely NO texture, speckles, outlines, shadow, noise, blur, or leftover pixels outside the 3 crisp black shapes. No white or black background and no checkerboard texture. Black artwork only, with smooth antialiased edges against actual alpha transparency. Do not draw a rounded square.
