# Lokalweb delivery roadmap

Lokalweb is being built around one practical promise: an existing local WordPress project can move away from MAMP without changing or copying its source files. Each phase has a gate so later convenience work does not hide a broken core workflow.

## Phase 0 — Runtime foundation (complete)

- Native SwiftUI app with service and log views.
- App-owned nginx, Apache, PHP-FPM, and MariaDB configuration, processes, data, and logs.
- Homebrew runtime discovery and installation.
- Multiple `.localhost` sites on isolated, non-privileged ports.
- Real nginx/Apache → PHP-FPM → MariaDB integration tests.

**Gate:** Lokalweb can start and stop its own stack without touching MAMP or globally managed Homebrew services.

## Phase 1 — Existing-site migration (complete)

- Detect WordPress and generic PHP project folders without modifying them.
- Add and edit site name, hostname slug, document root, and database name with validation.
- Show the exact database values a site must use with Lokalweb.
- Create, inspect, import, and export a site's MariaDB database.
- Accept both `.sql` and compressed `.sql.gz` imports.
- Cover detection and database migration with automated tests.

**Gate:** given an existing MAMP WordPress folder and SQL dump, the site can be registered, imported, opened through Lokalweb, and exported again. The project folder remains unchanged.

## Phase 2 — Native local networking and HTTPS (complete)

- Zero-configuration `.localhost` hostnames without DNS or host-file changes.
- Optional trusted local TLS certificates through an explicit mkcert action.
- Isolated configurable HTTP and HTTPS ports with collision detection.
- Reversible app-owned certificate and nginx configuration.

**Gate:** Lokalweb generates HTTP and optional HTTPS virtual hosts without changing MAMP, `/etc/hosts`, or system DNS. Trust-store setup happens only after an explicit user action.

## Phase 3 — Runtime compatibility (complete)

- Per-site PHP 8.3, 8.4, and 8.5 assignments with separate PHP-FPM pools.
- Stable automatic pool-port allocation and nginx routing.
- Installed-version and common WordPress extension diagnostics.
- Per-site nginx or Apache selection with an isolated private Apache backend.
- Automatic running-service reconciliation and transactional rollback when a server change fails.
- Apache `.htaccess` and WordPress permalink compatibility.

**Gate:** nginx and Apache sites using different supported PHP versions run side by side, and a live site can switch servers without changing its public URL.

## Phase 4 — WordPress development workflow (complete)

- Fresh WordPress installation through optional WP-CLI.
- Database snapshots, confirmed replacement restore, and safe deletion.
- Plugin developer folder linking with overwrite protection.
- Direct WordPress admin access and migration-safe connection guidance.

**Gate:** common plugin-development setup and reset workflows can be completed inside Lokalweb without hiding the underlying files or commands.

## Phase 5 — Local release and production hardening (complete)

- Homebrew dependency installation remains separate from MAMP and keeps runtime ownership visible.
- Stale-PID recovery, partial-start cleanup, stop-on-quit behavior, and diagnostic export.
- Hardened runtime, local release packaging, and MAMP migration checklist.
- Automated unit/configuration tests plus an isolated real-stack migration test.

**Gate:** a signed local build packages successfully on the target Mac, runs the isolated migration suite, and leaves no Lokalweb service running after validation.

## Phase 6 — Menu-bar workflow (complete)

- Persistent native menu-bar status while the dashboard is closed.
- Start/stop, refresh, site, WordPress Admin, and new-WordPress shortcuts.
- Single dashboard window with dynamic Dock visibility and attention-driven reopening.
- Explicit stop-or-preserve service choice on Quit, with the saved preference as the default.
- Lifecycle state and navigation tests plus native close/reopen/quit verification.

**Gate:** closing the dashboard leaves Lokalweb available without changing service state, the menu bar can reopen the full window, and explicit Quit ends the app cleanly.

The source is prepared for public development under the MIT License. Binary distribution remains a separate release track because Developer ID notarization, an updater and clean-machine testing require distribution credentials and product decisions that are not needed for building Lokalweb locally.

## Phase 7 — Public source release

- Publish the complete source, generated Xcode project and architecture documentation.
- Remove maintainer-specific signing configuration from contributor builds.
- Add an open-source license, contribution guidance, private security reporting and CI.
- Keep ad-hoc local builds clearly separate from future notarized binaries.

**Gate:** a fresh public clone regenerates the Xcode project without drift, passes the test suite, contains no credentials or private runtime data, and documents that no notarized binary is available yet.

## Web-server design decision

nginx remains Lokalweb's public loopback router because two independent servers cannot bind the same address and port. nginx-selected sites are served directly; Apache-selected sites are proxied to a Lokalweb-owned private port. This keeps every site on the same `.localhost` URL, allows both server types to run simultaneously, and confines Apache configuration, PIDs, and logs to Lokalweb.
