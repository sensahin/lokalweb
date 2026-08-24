# Migrating local WordPress sites from MAMP PRO

Keep MAMP installed and its data intact until every migrated site passes the final checks. A working source folder is not a database backup.

## 1. Prepare while MAMP is still running

For each site, record:

- document root;
- current local URL;
- PHP version and important extensions;
- database name;
- the `DB_HOST`, `DB_USER`, and `DB_NAME` values from `wp-config.php`;
- any custom nginx, Apache, or `.htaccess` behavior; select Apache in Lokalweb for sites that depend on `.htaccess`.

Export each database from MAMP as an SQL file. Keep a separate copy outside both MAMP and Lokalweb.

## 2. Stop MAMP, but do not uninstall it

Stopping MAMP prevents port conflicts and gives you a clean comparison. Do not delete its application, configuration, or database directories yet.

Open Lokalweb, install any missing Homebrew runtimes, and start its services. The defaults are deliberately different from MAMP:

```text
HTTP:       8090
HTTPS:      8443 when enabled
MariaDB:    3307
PHP-FPM:    9083 and upward
```

## 3. Register the existing source folder

Choose **Sites → Add Existing** and select the WordPress document root. Lokalweb reads the structure but does not copy the folder or edit `wp-config.php`.

Open **Manage** and choose the PHP runtime that matches the old MAMP host. Install the requested formula from **Services** if it is missing.

## 4. Import the database

In the site's **Database migration** section:

1. confirm the intended Lokalweb database name;
2. choose **Import SQL…**;
3. select the MAMP `.sql` or `.sql.gz` export;
4. wait for the database status and table count.

Before later experiments, choose **Create Snapshot**. Snapshots are stored in Lokalweb app data, not in the WordPress project.

## 5. Update WordPress connection settings

Back up `wp-config.php`, then set the values displayed by Lokalweb:

```php
define('DB_NAME', 'the_database_name_shown_in_lokalweb');
define('DB_USER', 'root');
define('DB_PASSWORD', '');
define('DB_HOST', '127.0.0.1:3307');
```

Lokalweb intentionally reports these values instead of silently rewriting an existing configuration file.

If the hostname changed, use a serialization-aware WordPress search/replace workflow such as WP-CLI. Do not run a raw SQL string replacement across WordPress tables because serialized values can be corrupted.

## 6. Verify the site

Check all of the following before treating the migration as complete:

- front page and several pretty-permalink routes;
- `/wp-admin/` login;
- media upload and image processing;
- the plugin or theme workflow you actively develop;
- scheduled tasks, REST endpoints, and AJAX requests;
- outbound mail behavior if the site depends on it;
- database snapshot creation and export;
- PHP version and required extension diagnostics.

Repeat the process for every local site.

## 7. Decommission MAMP only after verification

Once every site passes and the independent SQL exports are safe:

1. quit Lokalweb and confirm its services stop;
2. archive any MAMP-only configuration you may need later;
3. uninstall MAMP PRO using its supported uninstall process;
4. reopen Lokalweb and run a final site check;
5. retain the pre-migration SQL backups for a reasonable rollback period.

MAMP removal is a separate, explicit operation. Lokalweb never deletes or modifies the MAMP installation.
