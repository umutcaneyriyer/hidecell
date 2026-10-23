# Drag-to-Applications installer

`./package-dmg.sh` creates `Installers/Hidecell-1.5.<build>.dmg` from the signed
`Hidecell.app`. It does not rebuild or change the application.

One-time tooling setup:

```sh
python3 -m venv .build/dmg-tools
.build/dmg-tools/bin/pip install -r Packaging/requirements.txt
```

The Swift drawing source generates a 2× lavender background. `layout.py` places
real Finder icons in a 500 × 652 window; Applications is a symlink to the system
folder. The background TIFF carries 144 DPI metadata for Retina rendering.
The resulting image is compressed, read-only, and checked with `hdiutil verify`.

The app retains its existing development signature. Packaging does not add
Developer ID signing or notarization.
