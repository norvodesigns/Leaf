"""Drops the alpha channel from the opaque app icons (App Store Connect rejects icons with transparency)."""
from PIL import Image

PATHS = [
    "Leaf/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "Leaf/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png",
    "Leaf/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png",
    "LeafWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
]
for path in PATHS:
    image = Image.open(path).convert("RGB")
    image.save(path, optimize=True)
    print("flattened", path, image.size)
