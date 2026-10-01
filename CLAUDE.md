# Viji

macOS menu bar app (Swift, AppKit, no dependencies): a single eye icon that lists every menu bar icon, including those hidden behind the MacBook notch, and opens the one you click. Open source at github.com/dalex160/Viji (MIT).

## Layout

- `main.swift`: the whole app. AX scanning (`collectExtras`, `extras(of:)`), user order (`Prefs`, `applyUserOrder`), the order window (`OrderWindowController`), eye icons (`openEyeImage`, `closedEyeImage`), and `AppDelegate`.
- `build.sh`: compiles with `swiftc`, assembles `Viji.app`, signs and installs to `~/Applications`. Flags: `UNIVERSAL=1` (arm64 + x86_64), `INSTALL=0` (build into `./build` only), `VERSION=x.y.z`.
- `scripts/setup-signing.sh`: creates the self-signed "Viji Local Signing" certificate once; `build.sh` calls it for local installs.
- `scripts/make-icon.swift`: draws the app icon, writes `Resources/AppIcon.icns` and `docs/logo.png`. Run with `swift scripts/make-icon.swift` after changing the design.
- `install.sh`: the `curl … | zsh` one-liner; downloads `main` and runs `build.sh`.
- `.github/workflows/release.yml`: on a `v*` tag, builds a universal app and publishes `Viji.zip` as a GitHub release.

## Commands

- Build and run locally: `./build.sh`
- Compile check without installing: `swiftc -O -swift-version 5 main.swift -o /tmp/viji-check`
- Release: commit, push, then `git tag vX.Y.Z && git push origin vX.Y.Z`; watch with `gh run watch`.

## Things learned the hard way (macOS 26)

- Status items are read via `AXExtrasMenuBar` on each app's AX element. `CGWindowListCopyWindowInfo` does not reveal which app owns an icon (Control Center owns the status windows), so it can't be used to find host apps.
- Control Center exposes unused modules as 0×0 AX elements; skip anything with zero size.
- Icons hidden behind the notch report an off-screen position (x ≈ 0, y ≈ screen height). Their menus open where macOS placed them.
- `NSStatusItem Preferred Position <name>` in each app's defaults only orders visible icons. Changing it does not make a hidden icon visible (tested with NordPass), so reordering the real menu bar was dropped.
- The Accessibility permission is tied to the code signature. Ad-hoc signing changes it every build; the local certificate keeps it stable. `build.sh` only resets the TCC entry when the previous install wasn't certificate-signed.
- With `set -o pipefail`, `cmd | grep -q` can fail spuriously (SIGPIPE). Capture output into a variable first.

## Conventions

- UI strings go through `tr(english, french)`; the UI is French when the system language is French.
- Every rebuild relaunches the app; with the local certificate, no re-authorization is needed.
- Test UI changes in the real menu bar (`screencapture -x -R …` to check the icon). Rendering icons to a PNG is a quick way to inspect them.
