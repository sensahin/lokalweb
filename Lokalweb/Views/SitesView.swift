import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SitesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @State private var showingAddSite = false
    @State private var showingNewWordPress = false
    @State private var selectedSite: Site?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                PageHeader(title: "Sites", subtitle: "Connect and migrate existing PHP and WordPress projects.")
                Spacer()
                Button { showingAddSite = true } label: { Label("Add Existing", systemImage: "folder.badge.plus") }
                Button { showingNewWordPress = true } label: { Label("New WordPress", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.allRunning || model.isBusy)
                    .help(model.allRunning ? "Install a fresh WordPress site" : "Start all services first")
            }

            if model.sites.isEmpty {
                EmptyState(icon: "globe", title: "No sites yet", message: "Add an existing project folder. Lokalweb never copies, edits, or deletes your source files.")
            } else {
                List(model.sites) { site in
                    SiteRow(site: site, inspection: model.inspection(for: site)) {
                        selectedSite = site
                    }
                    .environmentObject(model)
                }
                .listStyle(.inset)
            }
        }
        .padding(32)
        .sheet(isPresented: $showingAddSite) {
            AddSiteSheet(isPresented: $showingAddSite)
                .environmentObject(model)
        }
        .sheet(isPresented: $showingNewWordPress) {
            NewWordPressSheet(isPresented: $showingNewWordPress, existingSite: nil)
                .environmentObject(model)
        }
        .sheet(item: $selectedSite) { site in
            SiteDetailSheet(site: site)
                .environmentObject(model)
        }
        .onAppear { handleNewWordPressRequest() }
        .onChange(of: navigation.newWordPressRequest) { _, _ in
            handleNewWordPressRequest()
        }
    }

    private func handleNewWordPressRequest() {
        guard let request = navigation.newWordPressRequest else { return }
        navigation.consumeNewWordPressRequest(request)
        showingNewWordPress = true
    }
}

private struct NewWordPressSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    let existingSite: Site?
    @State private var name: String
    @State private var rootPath: String
    @State private var adminUser = "admin"
    @State private var adminPassword = ""
    @State private var adminEmail = ""

    init(isPresented: Binding<Bool>, existingSite: Site?) {
        _isPresented = isPresented
        self.existingSite = existingSite
        _name = State(initialValue: existingSite?.name ?? "")
        _rootPath = State(initialValue: existingSite?.rootPath ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(existingSite == nil ? "New WordPress site" : "Complete WordPress setup").font(.title.bold())
            Text(installerDescription)
                .foregroundStyle(.secondary)

            if model.binaries.wpCLI == nil {
                HStack {
                    Label("WP-CLI is required.", systemImage: "shippingbox")
                    Spacer()
                    Button("Install WP-CLI") { model.installWordPressTools() }
                        .disabled(model.isBusy)
                }
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            Form {
                TextField("Site title", text: $name)
                if existingSite == nil {
                    HStack {
                        TextField("Empty project folder", text: $rootPath)
                        Button("Choose…") { chooseFolder() }
                    }
                } else {
                    LabeledContent("Project folder") {
                        Text(rootPath).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
                TextField("Admin username", text: $adminUser)
                SecureField("Admin password", text: $adminPassword)
                TextField("Admin email", text: $adminEmail)
            }

            HStack {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Text(model.activity).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isBusy)
                Button(existingSite == nil ? "Install WordPress" : "Retry Installation") {
                    beginInstallation()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall)
            }
        }
        .padding(28)
        .frame(width: 620)
        .interactiveDismissDisabled(model.isBusy)
    }

    private var installerDescription: String {
        if existingSite == nil {
            return "Lokalweb will download WordPress into an empty folder, create its database, and generate wp-config.php. The site is added only after installation succeeds. The admin password is used once and is not stored by Lokalweb."
        }
        return "The earlier download did not complete. Lokalweb will reuse this empty site entry and will reuse its database only if it has no tables. The admin password is used once and is not stored."
    }

    private var canInstall: Bool {
        model.binaries.wpCLI != nil
            && model.allRunning
            && !model.isBusy
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rootPath.isEmpty
            && adminUser.range(of: #"^[A-Za-z0-9_.-]{1,60}$"#, options: .regularExpression) != nil
            && adminPassword.count >= 8
            && adminEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private func beginInstallation() {
        let completion: (Bool) -> Void = { success in
            guard success else { return }
            adminPassword = ""
            isPresented = false
        }
        if let existingSite {
            model.completeWordPressInstallation(
                for: existingSite,
                title: name,
                adminUser: adminUser,
                adminPassword: adminPassword,
                adminEmail: adminEmail,
                completion: completion
            )
        } else {
            model.createWordPressSite(
                name: name,
                rootPath: rootPath,
                adminUser: adminUser,
                adminPassword: adminPassword,
                adminEmail: adminEmail,
                completion: completion
            )
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Empty Folder"
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            if name.isEmpty { name = url.lastPathComponent }
        }
    }
}

private struct SiteRow: View {
    @EnvironmentObject private var model: AppModel
    let site: Site
    let inspection: SiteInspection
    let manage: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: inspection.platform.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(site.name).font(.headline)
                    SitePlatformBadge(platform: inspection.platform)
                }
                Text(site.url(configuration: model.configuration)?.absoluteString ?? site.slug)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("\(site.webServer.label) · \(RuntimeConfiguration.phpLabel(for: site.phpFormula ?? model.configuration.phpFormula))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(site.rootPath).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Button("Open") { model.open(site) }.disabled(!model.allRunning)
            Button("Manage", action: manage)
            Menu {
                Button("Reveal in Finder") { model.reveal(site) }
                Button("Create Database") { model.createDatabase(for: site) }
                    .disabled(model.serviceStates[.database]?.isRunning != true || model.isBusy)
                Divider()
                Button("Remove from Lokalweb", role: .destructive) { model.removeSite(site) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 8)
    }
}

private struct SitePlatformBadge: View {
    let platform: SitePlatform

    var body: some View {
        Text(platform.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch platform {
        case .wordpress, .php: return .green
        case .wordpressNeedsConfiguration: return .orange
        case .unsupported, .missing: return .red
        }
    }
}

private struct AddSiteSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var rootPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Add a site").font(.title.bold())
            Text("Choose the folder that contains index.php or your WordPress installation. Lokalweb inspects it without changing it.")
                .foregroundStyle(.secondary)

            Form {
                TextField("Name", text: $name)
                HStack {
                    TextField("Project folder", text: $rootPath)
                    Button("Choose…") { chooseFolder() }
                }
                LabeledContent("Local URL") {
                    Text(previewURL)
                        .monospaced().foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add Site") {
                    if model.addSite(name: name, rootPath: rootPath) {
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rootPath.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 580)
    }

    private var previewURL: String {
        let site = Site(name: name, slug: Site.makeSlug(from: name), rootPath: "/")
        return site.url(configuration: model.configuration)?.absoluteString ?? ""
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Site Folder"
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            if name.isEmpty { name = url.lastPathComponent }
        }
    }
}

private struct SiteDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Site
    @State private var savedSite: Site
    @State private var pendingImportURL: URL?
    @State private var showingImportConfirmation = false
    @State private var snapshotConfirmation: SnapshotConfirmation?
    @State private var showingWordPressInstaller = false

    init(site: Site) {
        _draft = State(initialValue: site)
        _savedSite = State(initialValue: site)
    }

    private var inspection: SiteInspection {
        model.inspection(for: draft)
    }

    private var databaseIsRunning: Bool {
        model.serviceStates[.database]?.isRunning == true
    }

    private var hasUnsavedChanges: Bool {
        draft != savedSite
    }

    private var isWordPress: Bool {
        inspection.platform == .wordpress || inspection.platform == .wordpressNeedsConfiguration
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Manage site").font(.title.bold())
                        SitePlatformBadge(platform: inspection.platform)
                        Spacer()
                        Button("Open") { model.open(savedSite) }.disabled(!model.allRunning || hasUnsavedChanges)
                    }

                    GroupBox("Site settings") {
                        Form {
                            TextField("Name", text: $draft.name)
                            TextField("Hostname slug", text: $draft.slug)
                            HStack {
                                TextField("Project folder", text: $draft.rootPath)
                                Button("Choose…") { chooseFolder() }
                            }
                            TextField("Database", text: $draft.databaseName)
                            Picker("PHP runtime", selection: $draft.phpFormula) {
                                Text("Use global setting").tag(String?.none)
                                ForEach(RuntimeConfiguration.supportedPHPFormulae, id: \.self) { formula in
                                    Text(RuntimeConfiguration.phpLabel(for: formula)).tag(String?.some(formula))
                                }
                            }
                            .disabled(model.anyRunning)
                            if model.anyRunning {
                                Text("Stop Lokalweb before changing a site's PHP runtime.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Picker("Web server", selection: $draft.webServer) {
                                ForEach(WebServerKind.allCases) { server in
                                    Text(server.label).tag(server)
                                }
                            }
                            if draft.webServer == .apache {
                                Text(model.binaries.apache == nil
                                    ? "Apache requires the Homebrew httpd runtime. Install missing runtimes from Services, then save again."
                                    : "Lokalweb will route this site through Apache on its private port and apply the change automatically.")
                                    .font(.caption)
                                    .foregroundStyle(model.binaries.apache == nil ? .orange : .secondary)
                            }
                            LabeledContent("Local URL") {
                                Text(draft.url(configuration: model.configuration)?.absoluteString ?? "Invalid URL")
                                    .font(.callout.monospaced())
                            }
                        }
                        .padding(.top, 8)
                    }

                    GroupBox("Project inspection") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(inspection.platform.label, systemImage: inspection.platform.systemImage)
                                .font(.headline)
                            if inspection.notes.isEmpty {
                                Text("The project structure is ready for Lokalweb.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(inspection.notes, id: \.self) { note in
                                    Label(note, systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text("Lokalweb only reads this folder for inspection. It does not edit wp-config.php or other project files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }

                    if canCompleteWordPressInstallation {
                        GroupBox("Incomplete WordPress setup") {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("The project folder is still empty.").font(.headline)
                                    Text("Retry the setup with the corrected installer. Lokalweb keeps this site entry, asks for the administrator details again, and refuses to overwrite a database that contains tables.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Complete Setup…") { showingWordPressInstaller = true }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!model.allRunning || model.isBusy)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }

                    GroupBox("Database migration") {
                        VStack(alignment: .leading, spacing: 14) {
                            DatabaseConnectionRow(label: "DB_NAME", value: draft.databaseName)
                            DatabaseConnectionRow(label: "DB_USER", value: "root")
                            DatabaseConnectionRow(label: "DB_PASSWORD", value: "(empty)")
                            DatabaseConnectionRow(label: "DB_HOST", value: "127.0.0.1:\(model.configuration.databasePort)")
                            Divider()
                            databaseStatusView
                            if hasUnsavedChanges {
                                Label("Save site changes before managing this database.", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            HStack {
                                Button("Create Database") { model.createDatabase(for: savedSite) }
                                Button("Import SQL…") { chooseImportFile() }
                                Button("Export SQL…") { chooseExportFile() }
                                Spacer()
                                Button { model.refreshDatabaseStatus(for: savedSite) } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(!databaseIsRunning || hasUnsavedChanges || model.isBusy)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }

                    GroupBox("Database snapshots") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Snapshots are SQL exports stored in Lokalweb's app data, outside your project folder.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { model.createSnapshot(for: savedSite) } label: {
                                    Label("Create Snapshot", systemImage: "camera")
                                }
                                .disabled(!databaseIsRunning || hasUnsavedChanges || model.isBusy)
                            }
                            let siteSnapshots = model.snapshots[savedSite.id] ?? []
                            if siteSnapshots.isEmpty {
                                Text("No snapshots yet.").foregroundStyle(.secondary)
                            } else {
                                ForEach(siteSnapshots) { snapshot in
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.tint)
                                        VStack(alignment: .leading) {
                                            Text(snapshot.displayName)
                                            Text(snapshot.formattedSize).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Restore") { snapshotConfirmation = .restore(snapshot) }
                                            .disabled(!databaseIsRunning || model.isBusy)
                                        Button(role: .destructive) { snapshotConfirmation = .delete(snapshot) } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(10)
                                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }

                    if isWordPress {
                        GroupBox("WordPress development") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Button("Open WP Admin") { model.openAdmin(savedSite) }
                                        .disabled(!model.allRunning)
                                    Button("Link Plugin Folder…") { choosePluginFolder() }
                                        .disabled(hasUnsavedChanges || model.isBusy)
                                    Spacer()
                                    if model.binaries.wpCLI == nil {
                                        Button("Install WP-CLI") { model.installWordPressTools() }
                                            .disabled(model.isBusy)
                                    } else {
                                        Label("WP-CLI ready", systemImage: "checkmark.circle.fill")
                                            .font(.caption).foregroundStyle(.green)
                                    }
                                }
                                Text("Plugin linking creates a symbolic link and refuses to replace an existing plugin folder.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(28)
            }

            Divider()
            HStack {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Text(model.activity).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Changes") { saveChanges() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges || model.isBusy)
            }
            .padding(18)
        }
        .frame(width: 720, height: 720)
        .onAppear {
            if databaseIsRunning { model.refreshDatabaseStatus(for: savedSite) }
            model.refreshSnapshots(for: savedSite)
        }
        .sheet(isPresented: $showingWordPressInstaller) {
            NewWordPressSheet(isPresented: $showingWordPressInstaller, existingSite: savedSite)
                .environmentObject(model)
        }
        .alert("Import into \(savedSite.databaseName)?", isPresented: $showingImportConfirmation) {
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
            Button("Import", role: .destructive) {
                if let inputURL = pendingImportURL {
                    model.importDatabase(for: savedSite, from: inputURL)
                }
                pendingImportURL = nil
            }
        } message: {
            Text("The SQL file can replace or remove existing tables. Export a backup first if this database contains work you need.")
        }
        .alert(item: $snapshotConfirmation) { action in
            switch action {
            case .restore(let snapshot):
                return Alert(
                    title: Text("Restore database snapshot?"),
                    message: Text("This drops the current \(savedSite.databaseName) database and replaces it with the selected snapshot."),
                    primaryButton: .destructive(Text("Restore")) { model.restoreSnapshot(snapshot, for: savedSite) },
                    secondaryButton: .cancel()
                )
            case .delete(let snapshot):
                return Alert(
                    title: Text("Delete database snapshot?"),
                    message: Text("This removes the snapshot file from Lokalweb's app data."),
                    primaryButton: .destructive(Text("Delete")) { model.deleteSnapshot(snapshot, for: savedSite) },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    @ViewBuilder
    private var databaseStatusView: some View {
        if !databaseIsRunning {
            Label("Start MariaDB to inspect or migrate this database.", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        } else if hasUnsavedChanges {
            EmptyView()
        } else if let status = model.databaseStatuses[savedSite.id] {
            if status.exists {
                Label("Database exists with \(status.tableCount) tables.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Database has not been created yet.", systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Database status has not been checked.").foregroundStyle(.secondary)
        }
    }

    private var canCompleteWordPressInstallation: Bool {
        guard inspection.platform == .unsupported else { return false }
        let root = URL(fileURLWithPath: savedSite.rootPath, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return false }
        return contents.allSatisfy { $0.lastPathComponent == ".DS_Store" }
    }

    private func saveChanges() {
        if model.updateSite(draft) {
            savedSite = draft
            if databaseIsRunning { model.refreshDatabaseStatus(for: savedSite) }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Site Folder"
        if panel.runModal() == .OK, let url = panel.url {
            draft.rootPath = url.path
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["sql", "gz"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Choose SQL File"
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            showingImportConfirmation = true
        }
    }

    private func chooseExportFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(savedSite.databaseName).sql"
        panel.allowedContentTypes = ["sql"].compactMap { UTType(filenameExtension: $0) }
        panel.canCreateDirectories = true
        panel.prompt = "Export Database"
        if panel.runModal() == .OK, let url = panel.url {
            model.exportDatabase(for: savedSite, to: url)
        }
    }

    private func choosePluginFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Link Plugin Folder"
        if panel.runModal() == .OK, let url = panel.url {
            model.linkPlugin(from: url, to: savedSite)
        }
    }
}

private enum SnapshotConfirmation: Identifiable {
    case restore(DatabaseSnapshot)
    case delete(DatabaseSnapshot)

    var id: String {
        switch self {
        case .restore(let snapshot): return "restore-\(snapshot.id)"
        case .delete(let snapshot): return "delete-\(snapshot.id)"
        }
    }
}

private struct DatabaseConnectionRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value == "(empty)" ? "" : value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy value")
        }
    }
}
