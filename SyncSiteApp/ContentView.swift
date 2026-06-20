import AppKit
import SwiftUI

struct OperationMessage: Identifiable {
    enum Kind {
        case info
        case success
        case warning
        case error

        var icon: String {
            switch self {
            case .info:
                return "info.circle.fill"
            case .success:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .info:
                return .blue
            case .success:
                return .green
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let date = Date()
}

struct ContentView: View {
    @StateObject private var viewModel = SyncSiteViewModel()
    @State private var showingAddWizard = false
    @State private var showingReviewModal = false
    @State private var showingProgressModal = false
    @State private var showingHistoryModal = false
    @State private var uploadTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            siteList
        } detail: {
            if viewModel.selectedSite != nil {
                siteDetail
            } else {
                emptyState
            }
        }
        .navigationTitle("SyncSite")
        .sheet(isPresented: $showingAddWizard) {
            AddSiteWizard { site, config in
                viewModel.addSite(site, config: config)
            }
        }
        .sheet(isPresented: $showingReviewModal) {
            ReviewChangesModal(
                changes: viewModel.pendingChanges,
                modifiedAfterEnabled: $viewModel.modifiedAfterEnabled,
                modifiedAfterDate: $viewModel.modifiedAfterDate,
                onClose: { showingReviewModal = false },
                onUpload: {
                    showingReviewModal = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        startUpload()
                    }
                }
            )
        }
        .sheet(isPresented: $showingProgressModal) {
            ProgressModal(
                progress: viewModel.progress,
                isRunning: viewModel.isRunning,
                failedChange: viewModel.failedChange,
                errorMessage: viewModel.lastUploadError,
                canResume: viewModel.canResumeUpload,
                onResume: { startUpload(resume: true) },
                onCancel: cancelUpload,
                onClose: { showingProgressModal = false }
            )
        }
        .sheet(isPresented: $showingHistoryModal) {
            ActivityHistoryModal(
                messages: viewModel.messages,
                onClear: viewModel.clearMessages
            )
        }
        .overlay(alignment: .topTrailing) {
            if let toast = viewModel.toastMessage {
                ToastView(message: toast) {
                    viewModel.dismissToast()
                }
                .padding(18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.toastMessage?.id)
    }

    private var siteList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    showingAddWizard = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Adicionar sync")

                Button(role: .destructive) {
                    viewModel.removeSelectedSite()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remover sync selecionado")
                .disabled(viewModel.selectedSite == nil)

                Spacer(minLength: 8)

                Button {
                    viewModel.importSites()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Importar syncs")

                Button {
                    viewModel.exportSites()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Exportar syncs")
                .disabled(viewModel.sites.isEmpty)
            }
            .buttonStyle(SidebarIconButtonStyle())
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            List(selection: $viewModel.selectedSiteID) {
                Section {
                    ForEach(viewModel.sites) { site in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(site.name)
                                    .font(.system(size: 14, weight: .semibold))

                                Text(site.projectPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 5)
                        .tag(site.id)
                    }
                } header: {
                    Text("Syncs configurados")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 280)
    }

    private var siteDetail: some View {
        VStack(spacing: 0) {
            detailHeader

            Divider()

            HStack(alignment: .top, spacing: 0) {
                configAndActions
                    .frame(width: 340)

                Divider()

                dashboardPanel
            }
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.selectedSite?.name ?? "Site")
                    .font(.title2.weight(.semibold))

                Text(viewModel.selectedSite?.projectPath ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Recarregar") {
                viewModel.reloadConfig()
            }
        }
        .padding(16)
    }

    private var configAndActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Configuração FTP") {
                VStack(alignment: .leading, spacing: 10) {
                    labeledField("Servidor", text: $viewModel.config.host, prompt: "ftp.seusite.com")
                    labeledField("Login", text: $viewModel.config.user, prompt: "usuário")
                    labeledField("Senha", text: $viewModel.config.password, prompt: "senha")
                    labeledField("Diretório raiz", text: $viewModel.config.root, prompt: "/public_html")

                    Button("Salvar configuração") {
                        viewModel.saveConfig()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(8)
            }

            GroupBox("Ações") {
                VStack(spacing: 0) {
                    actionButton("Criar base inicial", systemImage: "flag.checkered") {
                        viewModel.createBaseline()
                    }

                    Divider().opacity(0.55)

                    actionButton("Testar FTP", systemImage: "checkmark.seal") {
                        Task {
                            await viewModel.runTest()
                        }
                    }

                    Divider().opacity(0.55)

                    actionButton("Verificar arquivos alterados", systemImage: "list.bullet.rectangle") {
                        viewModel.refreshChanges()
                        showingReviewModal = true
                    }

                    Divider().opacity(0.55)

                    actionButton("Enviar alterações", systemImage: "arrow.up.circle.fill", isPrimary: true) {
                        viewModel.refreshChanges(showMessage: false)
                        startUpload()
                    }
                    .disabled(!viewModel.config.isComplete || viewModel.selectedSite == nil)
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(16)
    }

    private var dashboardPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Resumo")
                    .font(.headline)

                Spacer()

                Button {
                    showingHistoryModal = true
                } label: {
                    Label("Histórico", systemImage: "clock")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label(viewModel.config.isComplete ? "FTP configurado" : "FTP incompleto", systemImage: viewModel.config.isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(viewModel.config.isComplete ? .green : .orange)

                Label(viewModel.modifiedAfterEnabled ? "Filtro por data ativo" : "Comparando com a base salva", systemImage: viewModel.modifiedAfterEnabled ? "calendar.badge.clock" : "square.stack.3d.up")
                    .foregroundStyle(.secondary)

                if !viewModel.pendingChanges.isEmpty {
                    Label("\(viewModel.pendingChanges.count) alterações verificadas", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                }

                if viewModel.canResumeUpload {
                    Label("\(viewModel.resumeChanges.count) arquivos aguardando retomada", systemImage: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)

            Spacer()
        }
        .padding(16)
    }

    private func messageCard(_ message: OperationMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.kind.icon)
                .font(.title2)
                .foregroundStyle(message.kind.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(message.title)
                    .font(.headline)

                if !message.detail.isEmpty {
                    Text(message.detail)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Nenhum site selecionado")
                .font(.title2.weight(.semibold))

            Button {
                showingAddWizard = true
            } label: {
                Label("Adicionar site", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func actionButton(_ title: String, systemImage: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(isPrimary ? Color.primary : Color.secondary)

                Text(title)
                    .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionPanelButtonStyle(isPrimary: isPrimary))
        .disabled(viewModel.isRunning || viewModel.selectedSite == nil)
    }

    private func startUpload(resume: Bool = false) {
        showingProgressModal = true
        uploadTask?.cancel()
        uploadTask = Task {
            let completed = await viewModel.upload(resume: resume)
            await MainActor.run {
                if completed {
                    showingProgressModal = false
                }
            }
        }
    }

    private func cancelUpload() {
        uploadTask?.cancel()
    }
}

private struct ActionPanelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
            }
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .opacity(isEnabled ? 1 : 0.48)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SidebarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 30, height: 28)
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.86 : 0.35))
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.10) : Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ReviewChangesModal: View {
    let changes: [FileChange]
    @Binding var modifiedAfterEnabled: Bool
    @Binding var modifiedAfterDate: Date
    let onClose: () -> Void
    let onUpload: () -> Void

    private var folderCount: Int {
        Set(changes.map(\.folderPath).filter { !$0.isEmpty }).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arquivos alterados")
                        .font(.title2.weight(.semibold))

                    Text("\(changes.count) arquivos em \(folderCount) pastas")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Fechar")
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Usar arquivos modificados depois de uma data", isOn: $modifiedAfterEnabled)
                    .toggleStyle(.checkbox)

                DatePicker(
                    "Data e hora",
                    selection: $modifiedAfterDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .disabled(!modifiedAfterEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if changes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)

                    Text("Nenhuma alteração encontrada")
                        .font(.headline)

                    Text("Não há arquivos para enviar com os filtros atuais.")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 680, height: 360)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(changes) { change in
                            FileChangeRow(change: change)
                        }
                    }
                    .padding(16)
                }
                .frame(width: 680, height: 360)
            }

            Divider()

            HStack {
                Button("Sair", action: onClose)

                Spacer()

                Button {
                    onUpload()
                } label: {
                    Label("Enviar agora", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(changes.isEmpty)
            }
            .padding(16)
        }
    }
}

struct ProgressModal: View {
    let progress: SyncProgress
    let isRunning: Bool
    let failedChange: FileChange?
    let errorMessage: String
    let canResume: Bool
    let onResume: () -> Void
    let onCancel: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    Text(progress.title)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(.green)

            VStack(alignment: .leading, spacing: 10) {
                if !progress.detail.isEmpty {
                    Text(progress.detail)
                        .font(.headline)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }

                if !progress.eta.isEmpty {
                    Text(progress.eta)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !errorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)

                        Text("Erro no upload")
                            .font(.headline)
                    }

                    if let failedChange {
                        Text(failedChange.path)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.35))
                )
            }

            Spacer()

            HStack {
                Spacer()

                if isRunning {
                    Button(role: .destructive) {
                        onCancel()
                    } label: {
                        Label("Cancelar", systemImage: "xmark.circle.fill")
                    }
                } else {
                    Button("Fechar", action: onClose)

                    if canResume {
                        Button {
                            onResume()
                        } label: {
                            Label("Retomar envio", systemImage: "arrow.clockwise.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 620, height: errorMessage.isEmpty ? 300 : 430)
    }

    private var title: String {
        if isRunning {
            return "Enviando arquivos"
        }

        if !errorMessage.isEmpty {
            return "Envio interrompido"
        }

        return "Envio finalizado"
    }
}

struct ActivityHistoryModal: View {
    let messages: [OperationMessage]
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Histórico de atividades")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Limpar", action: onClear)
                    .disabled(messages.isEmpty)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(20)

            Divider()

            if messages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)

                    Text("Nenhuma atividade registrada")
                        .font(.headline)
                }
                .frame(width: 620, height: 360)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageCard(message: message)
                        }
                    }
                    .padding(16)
                }
                .frame(width: 620, height: 360)
            }
        }
    }
}

struct ToastView: View {
    let message: OperationMessage
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.kind.icon)
                .font(.title2)
                .foregroundStyle(message.kind.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.headline)

                if !message.detail.isEmpty {
                    Text(message.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8))
        )
        .shadow(radius: 12, y: 6)
    }
}

struct MessageCard: View {
    let message: OperationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.kind.icon)
                .font(.title2)
                .foregroundStyle(message.kind.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(message.title)
                    .font(.headline)

                if !message.detail.isEmpty {
                    Text(message.detail)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8))
        )
    }
}

struct FileChangeRow: View {
    let change: FileChange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: change.kind == .upload ? "arrow.up.doc.fill" : "trash.fill")
                    .foregroundStyle(change.kind == .upload ? .blue : .red)

                Text(change.path)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(change.kind.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !change.folderPath.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)

                    Text(change.folderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

@MainActor
final class SyncSiteViewModel: ObservableObject {
    @Published var sites: [Site] {
        didSet {
            SiteStore.saveSites(sites)
        }
    }
    @Published var selectedSiteID: Site.ID? {
        didSet {
            SiteStore.saveSelectedID(selectedSiteID)
            reloadConfig()
        }
    }
    @Published var config = SyncConfig()
    @Published var messages: [OperationMessage] = []
    @Published var toastMessage: OperationMessage?
    @Published var pendingChanges: [FileChange] = []
    @Published var resumeChanges: [FileChange] = []
    @Published var failedChange: FileChange?
    @Published var lastUploadError = ""
    @Published var progress = SyncProgress()
    @Published var isRunning = false
    @Published var modifiedAfterEnabled = false {
        didSet {
            persistModifiedAfter()
            refreshChanges(showMessage: false)
        }
    }
    @Published var modifiedAfterDate = Date() {
        didSet {
            persistModifiedAfter()
            refreshChanges(showMessage: false)
        }
    }

    var selectedSite: Site? {
        sites.first { $0.id == selectedSiteID }
    }

    var canResumeUpload: Bool {
        !isRunning && !resumeChanges.isEmpty
    }

    init() {
        sites = SiteStore.loadSites()

        if let savedID = SiteStore.loadSelectedID(), sites.contains(where: { $0.id == savedID }) {
            selectedSiteID = savedID
        } else {
            selectedSiteID = sites.first?.id
        }

        reloadConfig()
    }

    func exportSites() {
        guard !sites.isEmpty else {
            addMessage(.warning, title: "Nenhum sync para exportar", detail: "Adicione pelo menos um sync antes de exportar.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exportar syncs"
        panel.nameFieldStringValue = "syncsite-syncs.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sites)
            try data.write(to: url, options: .atomic)
            addMessage(.success, title: "Syncs exportados", detail: "A lista de syncs foi salva em \(url.lastPathComponent).")
        } catch {
            addMessage(.error, title: "Não foi possível exportar", detail: error.localizedDescription)
        }
    }

    func importSites() {
        let panel = NSOpenPanel()
        panel.title = "Importar syncs"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let importedSites = try decoder.decode([Site].self, from: data)
            let existingIDs = Set(sites.map(\.id))
            let newSites = importedSites.filter { !existingIDs.contains($0.id) }

            guard !newSites.isEmpty else {
                addMessage(.info, title: "Nada para importar", detail: "Todos os syncs desse arquivo já estão na lista.")
                return
            }

            sites.append(contentsOf: newSites)
            selectedSiteID = newSites.first?.id
            addMessage(.success, title: "Syncs importados", detail: "\(newSites.count) syncs foram adicionados à lista.")
        } catch {
            addMessage(.error, title: "Não foi possível importar", detail: "Confira se o arquivo selecionado é uma exportação válida do SyncSite.\n\n\(error.localizedDescription)")
        }
    }

    func addSite(_ site: Site, config: SyncConfig) {
        do {
            try config.save(to: site.projectURL)

            sites.append(site)
            selectedSiteID = site.id
            self.config = config
            addMessage(.success, title: "Site adicionado", detail: "\(site.name) foi configurado e está pronto para testes.")
        } catch {
            addMessage(.error, title: "Não foi possível adicionar o site", detail: error.localizedDescription)
        }
    }

    func removeSelectedSite() {
        guard let selectedSiteID else {
            return
        }

        sites.removeAll { $0.id == selectedSiteID }
        self.selectedSiteID = sites.first?.id
    }

    func reloadConfig() {
        guard let selectedSite else {
            config = SyncConfig()
            pendingChanges = []
            clearUploadFailure()
            return
        }

        config = SyncConfig.load(from: selectedSite.projectURL)
        if let modifiedAfter = selectedSite.modifiedAfter {
            modifiedAfterEnabled = true
            modifiedAfterDate = modifiedAfter
        } else {
            modifiedAfterEnabled = false
            modifiedAfterDate = Date()
        }
        refreshChanges(showMessage: false)
    }

    func saveConfig() {
        guard let selectedSite else {
            addMessage(.warning, title: "Nenhum site selecionado", detail: "Escolha um site na lista lateral antes de salvar.")
            return
        }

        do {
            try config.save(to: selectedSite.projectURL)
            addMessage(.success, title: "Configuração salva", detail: "Os dados de FTP foram atualizados para \(selectedSite.name).")
        } catch {
            addMessage(.error, title: "Erro ao salvar configuração", detail: error.localizedDescription)
        }
    }

    func createBaseline() {
        guard let selectedSite else {
            addMessage(.warning, title: "Nenhum site selecionado", detail: "Escolha um site antes de criar a base.")
            return
        }

        do {
            try NativeSyncEngine.createBaseline(for: selectedSite)
            pendingChanges = []
            resumeChanges = []
            clearUploadFailure()
            addMessage(.success, title: "Base inicial criada", detail: "O estado atual de \(selectedSite.name) foi salvo. A partir daqui, o app enviará apenas alterações futuras.")
        } catch {
            addMessage(.error, title: "Não foi possível criar a base", detail: error.localizedDescription)
        }
    }

    func runTest() async {
        saveConfig()
        guard !isRunning else {
            return
        }

        guard let selectedSite else {
            addMessage(.warning, title: "Nenhum site selecionado", detail: "Escolha um site antes de testar o FTP.")
            return
        }

        isRunning = true
        progress = SyncProgress(fraction: 0, title: "Testando FTP", detail: selectedSite.name, eta: "")

        do {
            _ = try await NativeSyncEngine.testConnection(config: config)
            addMessage(.success, title: "FTP conectado", detail: "A conexão de \(selectedSite.name) foi validada com sucesso.")
        } catch {
            addMessage(.error, title: "Falha na conexão FTP", detail: friendlyError(from: error.localizedDescription))
        }

        progress = SyncProgress(fraction: 1, title: "Teste finalizado", detail: "", eta: "")
        isRunning = false
    }

    @discardableResult
    func upload(resume: Bool = false) async -> Bool {
        let automaticResumeLimit = 3
        saveConfig()
        guard !isRunning else {
            return false
        }

        guard let selectedSite else {
            addMessage(.warning, title: "Nenhum site selecionado", detail: "Escolha um site antes de enviar.")
            return false
        }

        var automaticResumeCount = 0
        var completedUploads = 0
        var completedDeletes = 0
        var completedBytes: Int64 = 0

        do {
            try Task.checkCancellation()
            var changes: [FileChange]
            if resume, !resumeChanges.isEmpty {
                let latestChanges = try NativeSyncEngine.changes(for: selectedSite, config: config, modifiedAfter: activeModifiedAfter)
                changes = normalizedChanges(mergedChanges(resumeChanges, latestChanges), site: selectedSite)
                resumeChanges = changes
            } else {
                changes = normalizedChanges(try NativeSyncEngine.changes(for: selectedSite, config: config, modifiedAfter: activeModifiedAfter), site: selectedSite)
                resumeChanges = changes
            }

            pendingChanges = changes
            clearUploadFailure()

            guard !changes.isEmpty else {
                addMessage(.success, title: "Nada para enviar", detail: "Nenhuma alteração foi encontrada.")
                resumeChanges = []
                return true
            }

            isRunning = true
            progress = SyncProgress(fraction: 0, title: resume ? "Retomando envio" : "Iniciando envio", detail: "\(changes.count) alterações pendentes", eta: "Calculando")

            while true {
                do {
                    _ = try await NativeSyncEngine.sync(site: selectedSite, config: config, changes: changes) { [weak self] progress in
                        self?.progress = progress
                    } completedChange: { [weak self] change in
                        if change.kind == .upload {
                            completedUploads += 1
                            completedBytes += change.size
                        } else {
                            completedDeletes += 1
                        }
                        self?.markChangeCompleted(change)
                    }
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()

                    guard automaticResumeCount < automaticResumeLimit else {
                        throw error
                    }

                    automaticResumeCount += 1
                    let latestChanges = try NativeSyncEngine.changes(for: selectedSite, config: config, modifiedAfter: activeModifiedAfter)
                    changes = normalizedChanges(mergedChanges(resumeChanges, latestChanges), site: selectedSite)
                    resumeChanges = changes
                    pendingChanges = changes
                    clearUploadFailure()

                    guard !changes.isEmpty else {
                        break
                    }

                    progress = SyncProgress(
                        fraction: progress.fraction,
                        title: "Retomando automaticamente \(automaticResumeCount)/\(automaticResumeLimit)",
                        detail: "\(changes.count) arquivos pendentes",
                        eta: "Tentando novamente"
                    )

                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            pendingChanges = []
            resumeChanges = []
            clearUploadFailure()
            addMessage(.success, title: "Sincronização concluída", detail: "\(completedUploads) arquivos enviados, \(completedDeletes) removidos. \(formatBytes(completedBytes)) transferidos.")
            isRunning = false
            return true
        } catch is CancellationError {
            pendingChanges = resumeChanges
            failedChange = nil
            lastUploadError = "Envio cancelado pelo usuário. Os arquivos que ainda não foram confirmados continuam na fila para retomada."
            progress = SyncProgress(fraction: progress.fraction, title: "Envio cancelado", detail: "\(resumeChanges.count) arquivos pendentes", eta: "")
            addMessage(.warning, title: "Envio cancelado", detail: "\(resumeChanges.count) arquivos continuam pendentes para retomada.")
            isRunning = false
            return false
        } catch {
            pendingChanges = resumeChanges
            failedChange = (error as? SyncError)?.failedChange
            lastUploadError = friendlyError(from: error.localizedDescription)
            progress = SyncProgress(fraction: progress.fraction, title: "Envio interrompido", detail: "\(resumeChanges.count) arquivos pendentes", eta: "Pronto para retomar")
            addMessage(.error, title: "Sincronização falhou", detail: "O app tentou retomar automaticamente \(automaticResumeLimit) vezes, mas \(resumeChanges.count) arquivos ficaram pendentes.\n\n\(lastUploadError)")
            isRunning = false
            return false
        }
    }

    func clearMessages() {
        messages.removeAll()
    }

    func dismissToast() {
        toastMessage = nil
    }

    func refreshChanges(showMessage: Bool = true) {
        guard let selectedSite else {
            pendingChanges = []
            return
        }

        do {
            pendingChanges = try NativeSyncEngine.changes(for: selectedSite, config: config, modifiedAfter: activeModifiedAfter)
            resumeChanges = []
            clearUploadFailure()
            if showMessage {
                let folderCount = Set(pendingChanges.map(\.folderPath).filter { !$0.isEmpty }).count
                let detail: String
                if let activeModifiedAfter {
                    detail = "\(pendingChanges.count) arquivos em \(folderCount) pastas modificados depois de \(formatDate(activeModifiedAfter))."
                } else {
                    detail = "\(pendingChanges.count) alterações em \(folderCount) pastas encontradas ao comparar com a base salva."
                }
                addMessage(.info, title: "Arquivos alterados verificados", detail: detail)
            }
        } catch {
            pendingChanges = []
            resumeChanges = []
            if showMessage {
                addMessage(.error, title: "Não foi possível verificar os arquivos", detail: error.localizedDescription)
            }
        }
    }

    private var activeModifiedAfter: Date? {
        modifiedAfterEnabled ? modifiedAfterDate : nil
    }

    private func persistModifiedAfter() {
        guard let selectedSiteID, let index = sites.firstIndex(where: { $0.id == selectedSiteID }) else {
            return
        }

        sites[index].modifiedAfter = modifiedAfterEnabled ? modifiedAfterDate : nil
    }

    private func friendlyError(from output: String) -> String {
        if output.contains("Access denied") || output.contains("530") {
            return "O servidor recusou o login. Confira usuário e senha."
        }

        if output.localizedCaseInsensitiveContains("could not resolve host") ||
            output.localizedCaseInsensitiveContains("Could not resolve") {
            return "Não foi possível encontrar o servidor FTP. Confira o endereço informado."
        }

        if output.localizedCaseInsensitiveContains("Connection refused") {
            return "O servidor recusou a conexão. Confira host, porta ou disponibilidade do FTP."
        }

        if output.localizedCaseInsensitiveContains("QUOT command failed with 550") ||
            output.localizedCaseInsensitiveContains("550") {
            return "O servidor FTP recusou uma operação com código 550. Normalmente isso indica pasta inexistente, permissão insuficiente ou bloqueio para criar/enviar nesta pasta. Confira o diretório raiz e as permissões do FTP.\n\nDetalhes técnicos:\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        if output.localizedCaseInsensitiveContains("Arquivo syncsite nao encontrado") {
            return "As ferramentas internas não foram instaladas corretamente na pasta do site."
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Ocorreu um erro inesperado." : trimmed
    }

    private func markChangeCompleted(_ change: FileChange) {
        resumeChanges.removeAll { $0.id == change.id }
        pendingChanges = resumeChanges
    }

    private func clearUploadFailure() {
        failedChange = nil
        lastUploadError = ""
    }

    private func mergedChanges(_ lhs: [FileChange], _ rhs: [FileChange]) -> [FileChange] {
        var merged: [String: FileChange] = [:]
        for change in lhs + rhs {
            merged[change.id] = change
        }

        return merged.values.sorted { left, right in
            if left.kind.rawValue == right.kind.rawValue {
                return left.path.localizedStandardCompare(right.path) == .orderedAscending
            }

            return left.kind == .upload
        }
    }

    private func normalizedChanges(_ changes: [FileChange], site: Site) -> [FileChange] {
        changes.filter { change in
            guard change.kind == .upload else {
                return true
            }

            return FileManager.default.fileExists(atPath: site.projectURL.appendingPathComponent(change.path).path)
        }
    }

    private func addMessage(_ kind: OperationMessage.Kind, title: String, detail: String) {
        let message = OperationMessage(kind: kind, title: title, detail: detail)
        messages.insert(message, at: 0)
        toastMessage = message

        Task { [weak self, messageID = message.id] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard self?.toastMessage?.id == messageID else {
                return
            }
            self?.toastMessage = nil
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AddSiteWizard: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var siteName = ""
    @State private var projectURL: URL?
    @State private var config = SyncConfig()

    let onFinish: (Site, SyncConfig) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
                .frame(width: 560, height: 330)
                .padding(24)

            Divider()

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adicionar site")
                .font(.title2.weight(.semibold))

            Text(stepTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Text("Nome do site")
                    .font(.headline)

                TextField("Exemplo: Site institucional", text: $siteName)
                    .textFieldStyle(.roundedBorder)
            }
        case 1:
            VStack(alignment: .leading, spacing: 12) {
                Text("Pasta do projeto")
                    .font(.headline)

                Text(projectURL?.path ?? "Nenhuma pasta selecionada")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Button("Escolher pasta") {
                    chooseFolder()
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 10) {
                Text("Dados do FTP")
                    .font(.headline)

                wizardField("Servidor", text: $config.host, prompt: "ftp.seusite.com")
                wizardField("Login", text: $config.user, prompt: "usuário")
                wizardField("Senha", text: $config.password, prompt: "senha")
                wizardField("Diretório raiz", text: $config.root, prompt: "/public_html")
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text("Revisão")
                    .font(.headline)

                summaryRow("Site", value: siteName)
                summaryRow("Pasta", value: projectURL?.path ?? "")
                summaryRow("Servidor", value: config.host)
                summaryRow("Login", value: config.user)
                summaryRow("Diretório", value: config.root)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancelar") {
                dismiss()
            }

            Spacer()

            Button("Voltar") {
                step -= 1
            }
            .disabled(step == 0)

            Button(step == 3 ? "Concluir" : "Continuar") {
                if step == 3 {
                    finish()
                } else {
                    step += 1
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
        }
        .padding(16)
    }

    private var stepTitle: String {
        switch step {
        case 0:
            return "Primeiro, dê um nome para identificar este site."
        case 1:
            return "Escolha a pasta local onde ficam os arquivos do site."
        case 2:
            return "Informe os dados de conexão FTP."
        default:
            return "Confira as informações antes de salvar."
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return !siteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return projectURL != nil
        case 2:
            return config.isComplete
        default:
            return true
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Escolha a pasta local do site"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        projectURL = url
    }

    private func finish() {
        guard let projectURL else {
            return
        }

        let site = Site(name: siteName.trimmingCharacters(in: .whitespacesAndNewlines), projectPath: projectURL.path)
        onFinish(site, config)
        dismiss()
    }

    private func wizardField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
