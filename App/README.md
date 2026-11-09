# App

**English** · [한국어](README.ko.md)

App bundle configuration files. `scripts/build-app.sh` assembles and signs the bundle.

- `Info.plist` — bundle info template (`__VERSION__` and the like are filled in from the `VERSION` file at build time), menu bar only (LSUIElement), permission prompt texts
- `PolyMac.entitlements` — lets the app send Apple Events to Finder under the Hardened Runtime

The Finder right-click menu (Finder Sync extension) needs an app extension build, so it will be added here once there is an Xcode project.
