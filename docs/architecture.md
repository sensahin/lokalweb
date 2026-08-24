# Lokalweb architecture

## Ownership boundary

Lokalweb uses Homebrew-provided open-source runtimes but never registers them with `brew services`. Every process receives Lokalweb-specific configuration, PID, log, socket, and data paths. Process termination verifies that the PID command belongs to Lokalweb before sending a signal.

This avoids three unsafe shortcuts:

1. Reusing MAMP binaries would make Lokalweb depend on an expiring installation.
2. Editing `/etc/hosts` or privileged DNS state would create system-wide cleanup and authorization problems.
3. Global Homebrew services would blur ownership and could affect unrelated projects.

## Runtime topology

```text
Browser
  -> <site>.localhost:8090 (or trusted HTTPS :8443)
  -> Lokalweb nginx front router
      -> nginx site: selected PHP-FPM pool on 127.0.0.1:9083+
      -> Apache site: Lokalweb Apache on 127.0.0.1:10080
          -> selected PHP-FPM pool on 127.0.0.1:9083+
  -> Lokalweb MariaDB on 127.0.0.1:3307
```

`.localhost` resolves to loopback without host-file edits. A stable runtime plan assigns the global PHP formula the base port and additional requested formulae subsequent ports. nginx remains the public front router so nginx and Apache sites can share the same URL and HTTPS certificate. Apache starts only when at least one site selects it, listens only on its private loopback port, honors `.htaccess`, and forwards PHP to the site's selected PHP-FPM pool.

Changing a site's web server while Lokalweb is running validates both generated configurations, starts Apache when needed, restarts nginx so existing keep-alive connections cannot use stale routing, and stops Apache after the last Apache site moves away. Site and runtime persistence happens only after the new route succeeds; a failure restores the previous configuration.

## Data layout

Application Support contains site records, logs, snapshots, and UI assets. The short `~/.lokalweb/runtime` path contains MariaDB data, generated configuration, PID/socket files, and optional local certificates. The split prevents MariaDB and Unix-socket path-length failures while keeping user-facing artifacts in the conventional macOS location.

Database imports and exports stream through file handles instead of loading dumps into memory. Exports first write a sibling temporary file and replace the destination only after `mariadb-dump` succeeds. Snapshot restore validates that the selected SQL file is inside that site's Lokalweb-owned snapshot directory before dropping the target database.

## Site-source policy

Registering an existing site is read-only. Lokalweb detects WordPress markers and parses only the non-secret connection constants needed for mismatch reporting. It does not expose `DB_PASSWORD` or automatically rewrite `wp-config.php`.

Fresh WordPress installation and plugin symbolic linking are explicit workflows. Plugin linking refuses any existing destination. Database restore and import require confirmation in the UI.

## Recovery and shutdown

Startup recovery removes a PID file only when its process no longer exists. A live unowned PID is reported as a failure and is never killed. Partial stack startup stops all successfully started Lokalweb components.

The SwiftUI menu-bar scene owns Lokalweb's background presence and its three-second status refresh. The dashboard is a single restorable window rather than the owner of service lifecycle: closing it changes the app to accessory mode, hides the Dock icon, and leaves the model and services intact. Reopening the dashboard returns the app to regular activation mode. First launch and required-service attention keep the window visible.

Explicit termination is separate from closing the dashboard. When services are running, Quit asks whether to stop or preserve them and uses the saved stop-on-quit setting as the recommended first action. Test-host guards prevent an XCTest application host from applying real launch policy or stopping a separately running Lokalweb stack.

## Distribution boundary

The app has no App Sandbox because it must run developer-selected executables and access developer-selected project folders. Hardened runtime is enabled. Source builds use local ad-hoc signing so contributors do not need the maintainer's Apple development team. Public binary distribution additionally needs Developer ID signing, notarization, clean-machine acceptance tests, and a documented update path.
