# Lokalweb

Lokalweb is a native macOS environment for local PHP and WordPress development. It manages app-owned nginx, Apache, PHP-FPM, and MariaDB processes while leaving MAMP and globally managed Homebrew services alone.

> **Public source release:** Lokalweb is usable from source today. A Developer
> ID-signed and notarized binary has not been published yet, so GitHub downloads
> should not be treated as a finished installer release.

## Requirements

- macOS 14 or newer
- Xcode
- [Homebrew](https://brew.sh/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Lokalweb can install missing runtime formulae after it launches. The core stack
uses `nginx`, `php@8.3` and `mariadb`. Apache, PHP 8.4, PHP 8.5, WP-CLI and
mkcert are installed only when their related features are requested.

## Build and run from source

```sh
git clone https://github.com/sensahin/lokalweb.git
cd lokalweb
brew install xcodegen
xcodegen generate
open Lokalweb.xcodeproj
```

Select the **Lokalweb** scheme in Xcode and click **Run**. On first launch, open
**Services** and install the missing core runtimes before starting the stack.

## Version 1.2.0 features

- Keep Lokalweb available as a native macOS menu-bar app while its dashboard is closed.
- See running, stopped, working, partial, and attention states through distinct menu-bar labels and symbols.
- Start or stop the stack, refresh status, open sites and WordPress Admin, or begin a WordPress setup from the menu bar.
- Hide the Dock icon when the dashboard closes and restore it when the dashboard reopens.
- Confirm whether app-owned services should stop or remain running when Lokalweb explicitly quits.
- Start, stop, inspect, and diagnose an isolated local web stack.
- Register existing PHP or WordPress folders without copying or rewriting source files.
- Detect WordPress structure and report `wp-config.php` connection mismatches without exposing its password.
- Edit site hostname, root, database, and per-site PHP runtime.
- Run PHP 8.3, 8.4, and 8.5 pools side by side when their Homebrew formulae are installed.
- Select nginx or Apache independently for each site while both server types run side by side.
- Apply server changes automatically with configuration validation, service restart, and rollback if the new configuration fails.
- Support WordPress `.htaccess` permalinks through an isolated Apache backend without changing the site's public URL.
- Create databases and import `.sql` or `.sql.gz` dumps with streaming I/O.
- Export databases atomically and create app-owned snapshots with confirmed restore/delete actions.
- Optional trusted `.localhost` HTTPS through mkcert; HTTP remains the zero-configuration default.
- Install fresh WordPress projects transactionally with WP-CLI, a scoped 512 MB CLI memory limit, and automatic failed-attempt cleanup.
- Retry an earlier empty WordPress setup without losing its Lokalweb site entry.
- Link plugin development folders without overwriting existing plugins.
- Export a diagnostic report that excludes WordPress passwords and database content.
- Recommend stopping app-owned services on quit by default and remove only stale Lokalweb PID files during recovery.

## Safety boundary

Lokalweb does not call `brew services`, reuse MAMP binaries, edit `/etc/hosts`, or target MAMP PID/configuration/database paths. Default ports are HTTP `8090`, HTTPS `8443`, PHP-FPM `9083+`, MariaDB `3307`, and a private Apache backend on `10080`.

Existing-site inspection is read-only. Database import, snapshot restore, fresh WordPress installation, HTTPS trust setup, and plugin linking happen only after an explicit user action.

## Test

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Lokalweb.xcodeproj \
  -scheme Lokalweb \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  test CODE_SIGNING_ALLOWED=NO
```

Build an ad-hoc-signed application and local ZIP archive with:

```sh
./scripts/build-local.sh
```

The script writes the application to `.build/ReleaseDerived/Build/Products/Release/Lokalweb.app` and a versioned `*-local.zip` archive under `.build`. This local archive is not notarized for redistribution.

## Menu-bar lifecycle

Lokalweb shows its dashboard on the first 1.2 launch. After that, a normal launch can remain in the menu bar unless a required service needs attention. Closing the dashboard does not quit Lokalweb or stop its services. Use **Open Lokalweb Dashboard** to restore the full window and **Quit Lokalweb** when you want to end the app; if services are running, Lokalweb asks whether to stop or keep them and puts the saved preference first.

## Runtime data

User-facing records, snapshots, landing assets, and logs:

```text
~/Library/Application Support/Lokalweb/
```

Low-level configuration, PID/socket files, certificates, and MariaDB storage:

```text
~/.lokalweb/runtime/
```

The short runtime path avoids Unix-socket and MariaDB bootstrap problems caused by long paths containing spaces.

## Migrating from MAMP

Do not uninstall MAMP first. Follow [the migration checklist](docs/migration-from-mamp.md), verify every site in Lokalweb, and keep a database export until the new environment is confirmed.

## Public distribution status

The project supports hardened runtime and ad-hoc local builds. A downloadable binary for other Macs still requires Developer ID signing, Apple notarization, clean-machine acceptance tests, and a documented update path. Distribution credentials are never stored in this repository.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and pull-request guidance. Please report suspected vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

Lokalweb is available under the [MIT License](LICENSE). Homebrew runtimes and WordPress retain their own licenses; see [THIRD_PARTY.md](THIRD_PARTY.md).
