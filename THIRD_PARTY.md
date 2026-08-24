# Third-party software

Lokalweb source code is licensed under the MIT License. The application does
not bundle the server runtimes it manages. It discovers or installs them using
Homebrew at the user's explicit request.

Those independent packages retain their own licenses and release policies:

- nginx
- Apache HTTP Server
- PHP
- MariaDB
- WP-CLI
- mkcert

Homebrew displays the exact formula source, version and upstream project for
each installed package. Lokalweb does not relicense those packages and does not
register them as global `brew services`.

WordPress downloaded by WP-CLI is distributed by the WordPress project under
its own license. WordPress plugins and themes remain subject to their respective
licenses.
