import Foundation

struct ConfigurationGenerator {
    let paths: AppPaths

    func writeAll(
        sites: [Site],
        configuration: RuntimeConfiguration,
        binaries: RuntimeBinaries
    ) throws {
        try paths.prepare()
        try writeLandingPage(configuration: configuration)
        try nginxConfiguration(sites: sites, configuration: configuration, binaries: binaries)
            .write(to: paths.nginxConfiguration, atomically: true, encoding: .utf8)
        if sites.contains(where: { $0.webServer == .apache }) {
            try apacheConfiguration(sites: sites, configuration: configuration, binaries: binaries)
                .write(to: paths.apacheConfiguration, atomically: true, encoding: .utf8)
        }
        let phpPlan = PHPRuntimePlan(sites: sites, configuration: configuration)
        try removeStalePHPConfigurations(keeping: Set(phpPlan.instances.map { paths.phpConfiguration(for: $0.formula) }))
        for instance in phpPlan.instances {
            try phpConfiguration(formula: instance.formula, port: instance.port)
                .write(to: paths.phpConfiguration(for: instance.formula), atomically: true, encoding: .utf8)
        }
        try databaseConfiguration(configuration: configuration, binaries: binaries)
            .write(to: paths.databaseConfiguration, atomically: true, encoding: .utf8)
    }

    func nginxConfiguration(
        sites: [Site],
        configuration: RuntimeConfiguration,
        binaries: RuntimeBinaries
    ) throws -> String {
        guard let nginxConfigurationDirectory = binaries.nginxConfigurationDirectory else {
            throw RuntimeError.missingRuntime("nginx")
        }
        let nginxConfigurationURL = URL(fileURLWithPath: nginxConfigurationDirectory, isDirectory: true)
        let mimeTypes = nginxConfigurationURL.appendingPathComponent("mime.types").path
        let fastCGIParameters = nginxConfigurationURL.appendingPathComponent("fastcgi_params").path
        let phpPlan = PHPRuntimePlan(sites: sites, configuration: configuration)
        let serverBlocks = sites.map {
            nginxSiteBlock(
                $0,
                configuration: configuration,
                phpPort: phpPlan.port(for: $0, configuration: configuration),
                fastCGIParameters: fastCGIParameters
            )
        }.joined(separator: "\n\n")
        let defaultHTTPS = httpsDirectives(configuration: configuration, defaultServer: true)

        return """
        worker_processes  1;
        pid \(quote(paths.nginxPID.path));
        error_log \(quote(paths.nginxLog.path)) notice;

        events {
            worker_connections 1024;
        }

        http {
            include \(quote(mimeTypes));
            default_type application/octet-stream;
            access_log \(quote(paths.accessLog.path));
            sendfile on;
            keepalive_timeout 65;
            client_max_body_size 128m;
            index index.php index.html index.htm;

            server {
                listen 127.0.0.1:\(configuration.httpPort) default_server;
        \(indent(defaultHTTPS, spaces: 8))
                server_name localhost;
                root \(quote(paths.landing.path));
                location / { try_files $uri /index.html; }
            }

        \(indent(serverBlocks, spaces: 4))
        }
        """
    }

    func apacheConfiguration(
        sites: [Site],
        configuration: RuntimeConfiguration,
        binaries: RuntimeBinaries
    ) throws -> String {
        guard let prefix = binaries.apachePrefix,
              let moduleDirectory = binaries.apacheModuleDirectory,
              let mimeTypes = binaries.apacheMimeTypes else {
            throw RuntimeError.missingRuntime("Apache (Homebrew httpd)")
        }
        let phpPlan = PHPRuntimePlan(sites: sites, configuration: configuration)
        let virtualHosts = sites.filter { $0.webServer == .apache }.map {
            apacheSiteBlock(
                $0,
                phpPort: phpPlan.port(for: $0, configuration: configuration),
                apachePort: configuration.apachePort
            )
        }.joined(separator: "\n\n")
        let modules = apacheModules.map { name, file in
            "LoadModule \(name) \(quote(URL(fileURLWithPath: moduleDirectory).appendingPathComponent(file).path))"
        }.joined(separator: "\n")

        return """
        ServerRoot \(quote(prefix))
        DefaultRuntimeDir \(quote(paths.run.path))
        PidFile \(quote(paths.apachePID.path))
        Listen 127.0.0.1:\(configuration.apachePort)
        ServerName localhost

        \(modules)

        ErrorLog \(quote(paths.apacheLog.path))
        LogLevel warn
        LogFormat "%h %l %u %t \\\"%r\\\" %>s %b" common
        CustomLog \(quote(paths.apacheAccessLog.path)) common
        TypesConfig \(quote(mimeTypes))
        DirectoryIndex index.php index.html index.htm
        Timeout 300
        KeepAlive On
        MaxKeepAliveRequests 100
        KeepAliveTimeout 5
        EnableSendfile Off
        EnableMMAP Off

        DocumentRoot \(quote(paths.landing.path))
        <Directory \(quote(paths.landing.path))>
            AllowOverride None
            Require all granted
        </Directory>

        \(virtualHosts)
        """
    }

    func phpConfiguration(configuration: RuntimeConfiguration) -> String {
        phpConfiguration(formula: configuration.phpFormula, port: configuration.phpPort)
    }

    func phpConfiguration(formula: String, port: Int) -> String {
        """
        [global]
        pid = \(paths.phpPID(for: formula).path)
        error_log = \(paths.phpLog(for: formula).path)
        daemonize = yes

        [lokalweb-\(formula.replacingOccurrences(of: "@", with: "-"))]
        listen = 127.0.0.1:\(port)
        listen.allowed_clients = 127.0.0.1
        user = \(NSUserName())
        group = staff
        pm = dynamic
        pm.max_children = 12
        pm.start_servers = 2
        pm.min_spare_servers = 1
        pm.max_spare_servers = 4
        catch_workers_output = yes
        clear_env = no
        php_admin_flag[log_errors] = on
        php_admin_value[error_log] = \(paths.phpLog(for: formula).path)
        php_admin_value[memory_limit] = 512M
        php_admin_value[upload_max_filesize] = 128M
        php_admin_value[post_max_size] = 128M
        php_admin_value[max_execution_time] = 300
        """
    }

    func databaseConfiguration(
        configuration: RuntimeConfiguration,
        binaries: RuntimeBinaries
    ) throws -> String {
        guard let prefix = binaries.mariaDBPrefix else {
            throw RuntimeError.missingRuntime("MariaDB")
        }
        return """
        [client]
        port = \(configuration.databasePort)
        socket = \(quote(paths.databaseSocket.path))

        [mariadb]
        basedir = \(quote(prefix))
        datadir = \(quote(paths.database.path))
        port = \(configuration.databasePort)
        bind-address = 127.0.0.1
        socket = \(quote(paths.databaseSocket.path))
        pid-file = \(quote(paths.databasePID.path))
        log-error = \(quote(paths.databaseLog.path))
        skip-name-resolve
        character-set-server = utf8mb4
        collation-server = utf8mb4_unicode_ci
        max_allowed_packet = 128M
        """
    }

    private func nginxSiteBlock(
        _ site: Site,
        configuration: RuntimeConfiguration,
        phpPort: Int,
        fastCGIParameters: String
    ) -> String {
        if site.webServer == .apache {
            return apacheProxyBlock(site, configuration: configuration)
        }
        return """
        server {
            listen 127.0.0.1:\(configuration.httpPort);
        \(indent(httpsDirectives(configuration: configuration, defaultServer: false), spaces: 4))
            server_name \(site.slug).localhost;
            root \(quote(site.rootPath));

            location / {
                try_files $uri $uri/ /index.php?$args;
            }

            location ~ \\.php$ {
                try_files $uri =404;
                include \(quote(fastCGIParameters));
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                fastcgi_param HTTP_PROXY "";
                fastcgi_read_timeout 300;
                fastcgi_pass 127.0.0.1:\(phpPort);
            }

            location ~ /\\.(?!well-known) {
                deny all;
            }
        }
        """
    }

    private func apacheProxyBlock(_ site: Site, configuration: RuntimeConfiguration) -> String {
        """
        server {
            listen 127.0.0.1:\(configuration.httpPort);
        \(indent(httpsDirectives(configuration: configuration, defaultServer: false), spaces: 4))
            server_name \(site.slug).localhost;

            location / {
                proxy_http_version 1.1;
                proxy_set_header Host $http_host;
                proxy_set_header X-Forwarded-Host $http_host;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-Port $server_port;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_read_timeout 300;
                proxy_pass http://127.0.0.1:\(configuration.apachePort);
            }
        }
        """
    }

    private func apacheSiteBlock(_ site: Site, phpPort: Int, apachePort: Int) -> String {
        """
        <VirtualHost 127.0.0.1:\(apachePort)>
            ServerName \(site.slug).localhost
            DocumentRoot \(quote(site.rootPath))

            SetEnvIf X-Forwarded-Proto "^https$" HTTPS=on

            <Directory \(quote(site.rootPath))>
                Options FollowSymLinks
                AllowOverride All
                Require all granted
            </Directory>

            <FilesMatch "\\.php$">
                SetHandler "proxy:fcgi://127.0.0.1:\(phpPort)"
            </FilesMatch>

            <FilesMatch "^\\.">
                Require all denied
            </FilesMatch>
        </VirtualHost>
        """
    }

    private var apacheModules: [(String, String)] {
        [
            ("mpm_event_module", "mod_mpm_event.so"),
            ("authn_file_module", "mod_authn_file.so"),
            ("authn_core_module", "mod_authn_core.so"),
            ("authz_host_module", "mod_authz_host.so"),
            ("authz_groupfile_module", "mod_authz_groupfile.so"),
            ("authz_user_module", "mod_authz_user.so"),
            ("authz_core_module", "mod_authz_core.so"),
            ("access_compat_module", "mod_access_compat.so"),
            ("auth_basic_module", "mod_auth_basic.so"),
            ("reqtimeout_module", "mod_reqtimeout.so"),
            ("filter_module", "mod_filter.so"),
            ("deflate_module", "mod_deflate.so"),
            ("mime_module", "mod_mime.so"),
            ("log_config_module", "mod_log_config.so"),
            ("env_module", "mod_env.so"),
            ("headers_module", "mod_headers.so"),
            ("setenvif_module", "mod_setenvif.so"),
            ("version_module", "mod_version.so"),
            ("proxy_module", "mod_proxy.so"),
            ("proxy_fcgi_module", "mod_proxy_fcgi.so"),
            ("expires_module", "mod_expires.so"),
            ("rewrite_module", "mod_rewrite.so"),
            ("negotiation_module", "mod_negotiation.so"),
            ("unixd_module", "mod_unixd.so"),
            ("autoindex_module", "mod_autoindex.so"),
            ("dir_module", "mod_dir.so"),
            ("alias_module", "mod_alias.so")
        ]
    }

    private func removeStalePHPConfigurations(keeping expected: Set<URL>) throws {
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: paths.configuration,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in existing where url.lastPathComponent.hasPrefix("php-fpm-")
            && url.pathExtension == "conf"
            && !expected.contains(url) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func httpsDirectives(configuration: RuntimeConfiguration, defaultServer: Bool) -> String {
        guard configuration.httpsEnabled else { return "" }
        return """
        listen 127.0.0.1:\(configuration.httpsPort) ssl\(defaultServer ? " default_server" : "");
        ssl_certificate \(quote(paths.certificate.path));
        ssl_certificate_key \(quote(paths.certificateKey.path));
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_cache shared:LokalwebTLS:10m;
        """
    }

    private func writeLandingPage(configuration: RuntimeConfiguration) throws {
        let html = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Lokalweb</title><style>body{font:16px -apple-system,BlinkMacSystemFont,sans-serif;background:#10131a;color:#f4f6fb;display:grid;place-items:center;min-height:100vh;margin:0}.card{max-width:560px;padding:40px;border:1px solid #2e3442;border-radius:20px;background:#171b24;box-shadow:0 24px 80px #0008}h1{margin:0 0 12px;font-size:34px}p{color:#aeb7c8;line-height:1.6}code{color:#78d6b2}</style></head>
        <body><main class="card"><h1>Lokalweb is running</h1><p>Your local web server is listening on port <code>\(configuration.httpPort)</code>. Add a site in the Lokalweb app, then open its <code>.localhost</code> address.</p></main></body></html>
        """
        try html.write(to: paths.landing.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    private func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func indent(_ value: String, spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return value.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }.joined(separator: "\n")
    }
}
