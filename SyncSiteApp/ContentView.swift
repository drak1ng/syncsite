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
    @State private var showingBackupConfirmation = false
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
                onReload: { viewModel.refreshChanges(showMessage: false) },
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
                activeBackupFiles: viewModel.activeBackupFiles,
                showsBackupFiles: viewModel.isBackupRunning,
                onResume: { startUpload(resume: true) },
                onMinimize: { showingProgressModal = false },
                onCancel: cancelUpload,
                onClose: { showingProgressModal = false }
            )
            .interactiveDismissDisabled(viewModel.isRunning)
        }
        .sheet(isPresented: $showingBackupConfirmation) {
            BackupConfirmationModal(
                onCancel: { showingBackupConfirmation = false },
                onConfirm: {
                    showingBackupConfirmation = false
                    startBackup()
                }
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
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isRunning && !showingProgressModal {
                MinimizedProgressBanner(progress: viewModel.progress) {
                    showingProgressModal = true
                }
                .padding(18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.toastMessage?.id)
        .animation(.easeOut(duration: 0.2), value: viewModel.isRunning)
        .onAppear {
            DockTileProgressController.update(progress: viewModel.progress, isRunning: viewModel.isRunning)
        }
        .onChange(of: viewModel.progress) { progress in
            DockTileProgressController.update(progress: progress, isRunning: viewModel.isRunning)
        }
        .onChange(of: viewModel.isRunning) { isRunning in
            DockTileProgressController.update(progress: viewModel.progress, isRunning: isRunning)
        }
    }

    private var siteList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("SyncSite")
                            .font(.system(size: 18, weight: .bold))

                        Text("Deploy por FTP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

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
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 16)

            List(selection: $viewModel.selectedSiteID) {
                Section {
                    ForEach(viewModel.sites) { site in
                        let visualState = viewModel.visualState(for: site)
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(visualState.color.opacity(visualState == .idle ? 0.06 : 0.16))

                                Image(systemName: visualState.sidebarIcon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(visualState == .idle ? Color.secondary : visualState.color)
                            }
                            .frame(width: 30, height: 30)

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
                        .padding(.vertical, 6)
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
        .frame(minWidth: 290)
        .background(.regularMaterial)
        .disabled(viewModel.isMonitoring)
    }

    private var siteDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader

                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 320, maximum: 420), spacing: 18, alignment: .top),
                    GridItem(.flexible(minimum: 320), spacing: 18, alignment: .top)
                ], alignment: .leading, spacing: 18) {
                    ftpSection
                    actionsSection
                }

                dashboardPanel
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(viewModel.selectedVisualState.color.gradient)
                    Image(systemName: viewModel.selectedVisualState.detailIcon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedSite?.name ?? "Site")
                        .font(.system(size: 28, weight: .bold))

                    Text(viewModel.selectedSite?.projectPath ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        startUpload()
                    } label: {
                        Label("Enviar alterações", systemImage: "arrow.up.circle.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.orange)
                    .disabled(!viewModel.config.isComplete || viewModel.selectedSite == nil || viewModel.isRunning)
                    .help("Enviar alterações agora")

                    Toggle("Monitorar", isOn: Binding(
                        get: { viewModel.isMonitoring },
                        set: { viewModel.setMonitoring($0) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(viewModel.selectedSite == nil || viewModel.isRunning)
                }

                if viewModel.isMonitoring {
                    Text("Tela bloqueada · monitorando apenas este projeto")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StatusPill(
                        title: viewModel.config.isComplete ? "FTP configurado" : "FTP incompleto",
                        systemImage: viewModel.config.isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        color: viewModel.config.isComplete ? .green : .orange
                    )

                    StatusPill(
                        title: viewModel.modifiedAfterEnabled ? "Filtro por data ativo" : "Base salva",
                        systemImage: viewModel.modifiedAfterEnabled ? "calendar.badge.clock" : "square.stack.3d.up",
                        color: .gray
                    )

                    if viewModel.canResumeUpload {
                        StatusPill(
                            title: "\(viewModel.resumeChanges.count) pendentes",
                            systemImage: "arrow.clockwise.circle.fill",
                            color: .orange
                        )
                    }

                    if viewModel.selectedVisualState != .idle {
                        StatusPill(
                            title: viewModel.selectedVisualState.title,
                            systemImage: viewModel.selectedVisualState.statusIcon,
                            color: viewModel.selectedVisualState.color
                        )
                    }
                }
            }
        }
    }

    private var ftpSection: some View {
        SectionPanel(title: "Configuração FTP", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 12) {
                labeledField("Servidor", text: $viewModel.config.host, prompt: "ftp.seusite.com")
                labeledField("Login", text: $viewModel.config.user, prompt: "usuário")
                labeledField("Senha", text: $viewModel.config.password, prompt: "senha")
                labeledField("Diretório raiz", text: $viewModel.config.root, prompt: "/public_html")

                HStack {
                    Spacer()

                    Button {
                        viewModel.saveConfig()
                    } label: {
                        Label("Salvar configuração", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(.top, 4)
            }
        }
        .disabled(viewModel.isMonitoring)
    }

    private var actionsSection: some View {
        SectionPanel(title: "Ações", systemImage: "bolt") {
            VStack(spacing: 2) {
                actionButton("Criar base inicial", detail: "Salva o estado atual como ponto de partida.", systemImage: "flag.checkered") {
                    viewModel.createBaseline()
                }

                SoftDivider()

                actionButton("Testar FTP", detail: "Valida servidor, usuário, senha e diretório.", systemImage: "checkmark.seal") {
                    Task {
                        await viewModel.runTest()
                    }
                }

                SoftDivider()

                actionButton("Backup FTP", detail: "Baixa todos os arquivos do FTP e substitui os locais.", systemImage: "arrow.down.circle.fill") {
                    showingBackupConfirmation = true
                }

                SoftDivider()

                actionButton("Verificar arquivos alterados", detail: "Mostra a lista antes de enviar.", systemImage: "doc.text.magnifyingglass") {
                    viewModel.refreshChanges()
                    showingReviewModal = true
                }

                SoftDivider()

                actionButton("Enviar alterações", detail: "Inicia o envio com progresso e retomada.", systemImage: "arrow.up.circle.fill", isPrimary: true) {
                    startUpload()
                }
                .disabled(!viewModel.config.isComplete || viewModel.selectedSite == nil)
            }
        }
        .disabled(viewModel.isMonitoring)
    }

    private var dashboardPanel: some View {
        SectionPanel(title: "Resumo", systemImage: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    SummaryMetric(
                        title: "Arquivos verificados",
                        value: "\(viewModel.pendingChanges.count)",
                        systemImage: "doc.text.magnifyingglass"
                    )

                    SummaryMetric(
                        title: "Aguardando retomada",
                        value: "\(viewModel.resumeChanges.count)",
                        systemImage: "arrow.clockwise.circle"
                    )

                    SummaryMetric(
                        title: "Modo de comparação",
                        value: viewModel.modifiedAfterEnabled ? "Data" : "Base",
                        systemImage: viewModel.modifiedAfterEnabled ? "calendar" : "square.stack.3d.up"
                    )
                }

                SoftDivider()

                HStack {
                    Label("Eventos recentes e mensagens do app ficam no histórico.", systemImage: "clock")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showingHistoryModal = true
                    } label: {
                        Label("Histórico", systemImage: "clock")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.callout)
            }
        }
        .disabled(viewModel.isMonitoring)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.orange.gradient)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 86, height: 86)

            VStack(spacing: 6) {
                Text("Nenhum sync selecionado")
                    .font(.system(size: 28, weight: .bold))

                Text("Escolha um sync na lateral ou adicione um novo projeto para começar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                showingAddWizard = true
            } label: {
                Label("Adicionar sync", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private func actionButton(_ title: String, detail: String, systemImage: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPrimary ? Color.orange.opacity(0.16) : Color.primary.opacity(0.055))

                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPrimary ? Color.orange : Color.secondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func startBackup() {
        showingProgressModal = true
        uploadTask?.cancel()
        uploadTask = Task {
            let completed = await viewModel.backupFTP()
            await MainActor.run {
                if completed { showingProgressModal = false }
            }
        }
    }

    private func cancelUpload() {
        uploadTask?.cancel()
        viewModel.cancelCurrentOperation()
    }

}

enum SyncVisualState: Equatable {
    case idle
    case preparing
    case uploading
    case deleting
    case completed
    case failed

    var title: String {
        switch self {
        case .idle:
            return "Parado"
        case .preparing:
            return "Preparando"
        case .uploading:
            return "Enviando"
        case .deleting:
            return "Removendo"
        case .completed:
            return "Concluído"
        case .failed:
            return "Com erro"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .orange
        case .preparing:
            return .blue
        case .uploading:
            return .green
        case .deleting:
            return .red
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    var sidebarIcon: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .preparing:
            return "clock.arrow.circlepath"
        case .uploading:
            return "arrow.up.circle.fill"
        case .deleting:
            return "trash.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    var detailIcon: String {
        switch self {
        case .idle:
            return "arrow.triangle.2.circlepath"
        case .preparing:
            return "clock.arrow.circlepath"
        case .uploading:
            return "arrow.up"
        case .deleting:
            return "trash"
        case .completed:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var statusIcon: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .preparing:
            return "clock.arrow.circlepath"
        case .uploading:
            return "arrow.up.circle.fill"
        case .deleting:
            return "trash.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }
}

extension SyncVisualState {
    init(phase: SyncOperationPhase) {
        switch phase {
        case .idle, .testing:
            self = .idle
        case .preparing:
            self = .preparing
        case .uploading:
            self = .uploading
        case .deleting:
            self = .deleting
        case .completed:
            self = .completed
        case .cancelled, .failed:
            self = .failed
        }
    }
}

private struct SectionPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)

                Spacer()
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.075))
            .frame(height: 1)
    }
}

private enum DockTileProgressController {
    private static var originalIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 128, height: 128))
    }

    @MainActor
    static func update(progress: SyncProgress, isRunning: Bool) {
        let dockTile = NSApp.dockTile

        guard isRunning else {
            dockTile.badgeLabel = nil
            dockTile.contentView = nil
            dockTile.display()
            return
        }

        dockTile.badgeLabel = nil

        dockTile.contentView = DockProgressIconView(
            frame: NSRect(x: 0, y: 0, width: dockTile.size.width, height: dockTile.size.height),
            icon: originalIcon,
            progress: progress
        )
        dockTile.display()
    }
}

private final class DockProgressIconView: NSView {
    private let icon: NSImage
    private let progress: SyncProgress

    init(frame: NSRect, icon: NSImage, progress: SyncProgress) {
        self.icon = icon
        self.progress = progress
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        icon.draw(in: bounds)

        let color = NSColor.systemBlue
        let barHeight = max(7, bounds.height * 0.08)
        let inset = bounds.width * 0.13
        let barRect = NSRect(
            x: inset,
            y: bounds.height * 0.08,
            width: bounds.width - (inset * 2),
            height: barHeight
        )
        let radius = barHeight / 2

        NSColor.black.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()

        let filledWidth = barRect.width * min(max(progress.fraction, 0), 1)
        if filledWidth > 1 {
            let filledRect = NSRect(x: barRect.minX, y: barRect.minY, width: filledWidth, height: barRect.height)
            color.setFill()
            NSBezierPath(roundedRect: filledRect, xRadius: radius, yRadius: radius).fill()
        }
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
    let onReload: () -> Void
    let onUpload: () -> Void

    private var folderCount: Int {
        Set(changes.map(\.folderPath).filter { !$0.isEmpty }).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.16))
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 46, height: 46)

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

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    SummaryMetric(title: "Arquivos", value: "\(changes.count)", systemImage: "doc")
                    SummaryMetric(title: "Pastas", value: "\(folderCount)", systemImage: "folder")
                }

                HStack(spacing: 12) {
                    Toggle("Filtrar por data e hora", isOn: $modifiedAfterEnabled)
                        .toggleStyle(.checkbox)
                        .frame(width: 190, alignment: .leading)

                    Text("Depois de")
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    DatePicker(
                        "",
                        selection: $modifiedAfterDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .disabled(!modifiedAfterEnabled)

                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 18)
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
                .frame(width: 680, height: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(changes) { change in
                            FileChangeRow(change: change)
                        }
                    }
                    .padding(16)
                }
                .frame(width: 680, height: 340)
            }

            Divider()

            HStack {
                Button("Sair", action: onClose)

                Spacer()

                Button {
                    onReload()
                } label: {
                    Label("Recarregar busca", systemImage: "arrow.clockwise")
                }

                Button {
                    onUpload()
                } label: {
                    Label("Enviar agora", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(changes.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ProgressModal: View {
    let progress: SyncProgress
    let isRunning: Bool
    let failedChange: FileChange?
    let errorMessage: String
    let canResume: Bool
    let activeBackupFiles: [BackupFileProgress]
    let showsBackupFiles: Bool
    let onResume: () -> Void
    let onMinimize: () -> Void
    let onCancel: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(visualState.color.opacity(0.16))
                    Image(systemName: visualState.statusIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(visualState.color)
                }
                .frame(width: 46, height: 46)

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

            SectionPanel(title: "Progresso", systemImage: "arrow.up.circle") {
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
            }

            if showsBackupFiles {
                SectionPanel(title: "Downloads ativos", systemImage: "arrow.down.circle") {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if activeBackupFiles.isEmpty {
                                Text("Aguardando o início dos downloads…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            } else {
                                ForEach(activeBackupFiles) { file in
                                    BackupFileProgressRow(file: file)
                                }
                            }
                        }
                    }
                    .frame(height: 126)
                }
            }

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
                    Button {
                        onMinimize()
                    } label: {
                        Label("Minimizar", systemImage: "rectangle.compress.vertical")
                    }

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
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 620, height: modalHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var modalHeight: CGFloat {
        let downloadsHeight: CGFloat = showsBackupFiles ? 170 : 0
        return (errorMessage.isEmpty ? 360 : 460) + downloadsHeight
    }

    private var title: String {
        if isRunning {
            return visualState.runningTitle
        }

        if !errorMessage.isEmpty {
            return "Envio interrompido"
        }

        return "Envio finalizado"
    }

    private var visualState: SyncVisualState {
        if !errorMessage.isEmpty {
            return .failed
        }

        return SyncVisualState(phase: progress.phase)
    }
}

private struct BackupFileProgressRow: View {
    let file: BackupFileProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(file.path)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(speed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(.green)
            Text("\(formatBytes(file.downloadedBytes)) de \(file.totalBytes.map(formatBytes) ?? "tamanho desconhecido")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var fraction: Double {
        guard let total = file.totalBytes, total > 0 else { return 0 }
        return min(Double(file.downloadedBytes) / Double(total), 1)
    }

    private var speed: String {
        let elapsed = max(Date().timeIntervalSince(file.startedAt), 0.1)
        return "\(formatBytes(Int64(Double(file.downloadedBytes) / elapsed)))/s"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct BackupConfirmationModal: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                Text("Sobrescrever arquivos locais?")
                    .font(.title2.weight(.semibold))
            }

            Text("O backup vai baixar todo o conteúdo da pasta FTP para este projeto. Arquivos locais com o mesmo nome serão substituídos e essa ação não pode ser desfeita.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancelar", action: onCancel)
                Spacer()
                Button(role: .destructive, action: onConfirm) {
                    Label("Continuar mesmo assim", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension SyncVisualState {
    var runningTitle: String {
        switch self {
        case .preparing:
            return "Preparando envio"
        case .uploading:
            return "Enviando arquivos"
        case .deleting:
            return "Removendo arquivos"
        case .completed:
            return "Envio finalizado"
        case .failed:
            return "Envio interrompido"
        case .idle:
            return "Aguardando"
        }
    }
}

struct MinimizedProgressBanner: View {
    let progress: SyncProgress
    let onOpen: () -> Void

    private var visualState: SyncVisualState {
        SyncVisualState(phase: progress.phase)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(visualState.color.opacity(0.22), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress.fraction)
                        .stroke(visualState.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: visualState.detailIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(visualState.color)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(visualState.runningTitle)
                        .font(.callout.weight(.semibold))

                    Text(progress.detail.isEmpty ? progress.title : progress.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 320, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .help("Abrir progresso do envio")
    }
}

struct ActivityHistoryModal: View {
    let messages: [OperationMessage]
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.07))
                    Image(systemName: "clock")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 46, height: 46)

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
        .background(Color(nsColor: .windowBackgroundColor))
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
        }
        .padding(.leading, 14)
        .padding(.trailing, 42)
        .padding(.vertical, 14)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8))
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(12)
            .help("Fechar")
        }
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
    @Published var activeBackupFiles: [BackupFileProgress] = []
    @Published var isBackupRunning = false
    @Published var failedChange: FileChange?
    @Published var lastUploadError = ""
    @Published var progress = SyncProgress()
    @Published var isRunning = false
    @Published var activeUploadSiteID: Site.ID?
    @Published private(set) var monitoredSiteID: Site.ID?
    private var activeUploadModifiedAfter: Date?
    private var monitorTask: Task<Void, Never>?
    private var monitorSignature: String?
    private var isReloadingSite = false
    @Published var modifiedAfterEnabled = false {
        didSet {
            if !isReloadingSite {
                persistModifiedAfter()
            }
        }
    }
    @Published var modifiedAfterDate = Date() {
        didSet {
            if !isReloadingSite {
                persistModifiedAfter()
            }
        }
    }

    var selectedSite: Site? {
        sites.first { $0.id == selectedSiteID }
    }

    var isMonitoring: Bool {
        monitoredSiteID != nil
    }

    var canResumeUpload: Bool {
        !isRunning && !resumeChanges.isEmpty
    }

    var selectedVisualState: SyncVisualState {
        guard let selectedSite else {
            return .idle
        }

        return visualState(for: selectedSite)
    }

    func visualState(for site: Site) -> SyncVisualState {
        guard activeUploadSiteID == site.id else {
            return .idle
        }

        if isRunning {
            return SyncVisualState(phase: progress.phase)
        }

        if !lastUploadError.isEmpty {
            return .failed
        }

        return .idle
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

    deinit {
        monitorTask?.cancel()
    }

    func setMonitoring(_ enabled: Bool) {
        if enabled {
            guard let selectedSite, config.isComplete else {
                addMessage(.warning, title: "FTP incompleto", detail: "Preencha e salve a configuração FTP antes de ativar o monitoramento.")
                return
            }

            monitoredSiteID = selectedSite.id
            monitorSignature = nil
            startMonitoring(siteID: selectedSite.id)
            addMessage(.info, title: "Monitoramento ativado", detail: "A tela foi bloqueada e somente \(selectedSite.name) será monitorado.")
        } else {
            stopMonitoring()
            addMessage(.warning, title: "Monitoramento desativado", detail: "A tela foi liberada e a verificação automática foi encerrada.")
        }
    }

    private func startMonitoring(siteID: Site.ID) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.checkMonitoredSite(siteID: siteID)
            }
        }
    }

    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        monitorSignature = nil
        monitoredSiteID = nil
    }

    func cancelCurrentOperation() {
        guard isRunning else {
            return
        }

        if monitoredSiteID != nil {
            stopMonitoring()
        }
    }

    private func checkMonitoredSite(siteID: Site.ID) async {
        guard !isRunning,
              monitoredSiteID == siteID,
              let site = sites.first(where: { $0.id == siteID }) else {
            return
        }

        let siteConfig = SyncConfig.load(from: site.projectURL)
        guard siteConfig.isComplete else {
            stopMonitoring()
            addMessage(.error, title: "Monitoramento encerrado", detail: "A configuração FTP de \(site.name) está incompleta.")
            return
        }

        do {
            let changes = normalizedChanges(
                try await NativeSyncEngine.changesAsync(for: site, config: siteConfig, modifiedAfter: modifiedAfter(for: site)),
                site: site
            )

            guard !changes.isEmpty else {
                monitorSignature = nil
                return
            }

            let signature = changes.map(\.id).joined(separator: "|")
            guard signature == monitorSignature else {
                monitorSignature = signature
                return
            }

            pendingChanges = changes
            _ = await upload(site: site, silent: true)
            monitorSignature = nil
        } catch is CancellationError {
            // O usuário desligou o monitoramento ou cancelou o envio.
            // Isso é um encerramento esperado, não uma falha de FTP.
            return
        } catch {
            stopMonitoring()
            addMessage(.error, title: "Monitoramento encerrado", detail: friendlyError(from: error.localizedDescription))
        }
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
            resumeChanges = []
            clearUploadFailure()
            return
        }

        config = SyncConfig.load(from: selectedSite.projectURL)
        pendingChanges = []
        resumeChanges = []
        clearUploadFailure()
        isReloadingSite = true
        if let modifiedAfter = selectedSite.modifiedAfter {
            modifiedAfterEnabled = true
            modifiedAfterDate = modifiedAfter
        } else {
            modifiedAfterEnabled = false
            modifiedAfterDate = Date()
        }
        isReloadingSite = false
    }

    func saveConfig(showMessage: Bool = true) {
        guard let selectedSite else {
            if showMessage {
                addMessage(.warning, title: "Nenhum site selecionado", detail: "Escolha um site na lista lateral antes de salvar.")
            }
            return
        }

        do {
            try config.save(to: selectedSite.projectURL)
            if showMessage {
                addMessage(.success, title: "Configuração salva", detail: "Os dados de FTP foram atualizados para \(selectedSite.name).")
            }
        } catch {
            if showMessage {
                addMessage(.error, title: "Erro ao salvar configuração", detail: error.localizedDescription)
            }
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
        progress = SyncProgress(fraction: 0, title: "Testando FTP", detail: selectedSite.name, eta: "", phase: .testing)

        do {
            _ = try await NativeSyncEngine.testConnection(config: config)
            addMessage(.success, title: "FTP conectado", detail: "A conexão de \(selectedSite.name) foi validada com sucesso.")
        } catch {
            addMessage(.error, title: "Falha na conexão FTP", detail: friendlyError(from: error.localizedDescription))
        }

        progress = SyncProgress(fraction: 1, title: "Teste finalizado", detail: "", eta: "", phase: .completed)
        isRunning = false
    }

    @discardableResult
    func backupFTP() async -> Bool {
        guard !isRunning, let selectedSite else { return false }
        saveConfig(showMessage: false)
        guard config.isComplete else {
            addMessage(.warning, title: "FTP incompleto", detail: "Preencha a configuração FTP antes de iniciar o backup.")
            return false
        }

        isRunning = true
        activeUploadSiteID = selectedSite.id
        activeBackupFiles = []
        isBackupRunning = true
        clearUploadFailure()
        progress = SyncProgress(title: "Preparando backup FTP", detail: selectedSite.name, eta: "", phase: .preparing)

        do {
            let summary = try await NativeSyncEngine.backup(
                site: selectedSite,
                config: config,
                progress: { [weak self] progress in self?.progress = progress },
                activeFiles: { [weak self] files in self?.activeBackupFiles = files }
            )
            pendingChanges = []
            resumeChanges = []
            activeBackupFiles = []
            isBackupRunning = false
            clearUploadFailure()
            isRunning = false
            activeUploadSiteID = nil
            addMessage(.success, title: "Backup FTP concluído", detail: "\(summary.downloaded) arquivos foram baixados. A base local foi atualizada.")
            return true
        } catch is CancellationError {
            activeBackupFiles = []
            isBackupRunning = false
            isRunning = false
            activeUploadSiteID = nil
            progress = SyncProgress(fraction: progress.fraction, title: "Backup cancelado", detail: "Arquivos já baixados foram mantidos.", eta: "", phase: .cancelled)
            addMessage(.warning, title: "Backup cancelado", detail: "Os arquivos já baixados foram mantidos, mas a base não foi atualizada.")
            return false
        } catch {
            activeBackupFiles = []
            isBackupRunning = false
            isRunning = false
            activeUploadSiteID = nil
            lastUploadError = friendlyError(from: error.localizedDescription)
            progress = SyncProgress(fraction: progress.fraction, title: "Backup interrompido", detail: "", eta: "", phase: .failed)
            addMessage(.error, title: "Backup FTP falhou", detail: lastUploadError)
            return false
        }
    }

    @discardableResult
    func upload(site targetSite: Site? = nil, resume: Bool = false, silent: Bool = false) async -> Bool {
        let automaticResumeLimit = 3
        guard !isRunning else {
            return false
        }

        let uploadSite = siteForUpload(targetSite: targetSite, resume: resume)
        guard let selectedSite = uploadSite else {
            if !silent {
                addMessage(.warning, title: "Nenhum site selecionado", detail: "Escolha um site antes de enviar.")
            }
            return false
        }
        if selectedSite.id == selectedSiteID {
            saveConfig(showMessage: !silent)
        }

        let uploadConfig = selectedSite.id == selectedSiteID ? config : SyncConfig.load(from: selectedSite.projectURL)
        let uploadModifiedAfter = resume ? activeUploadModifiedAfter : modifiedAfter(for: selectedSite)
        activeUploadModifiedAfter = uploadModifiedAfter

        var automaticResumeCount = 0
        var completedUploads = 0
        var completedDeletes = 0
        var completedBytes: Int64 = 0

        do {
            try Task.checkCancellation()
            var changes: [FileChange]
            if resume, !resumeChanges.isEmpty {
                let latestChanges = try await NativeSyncEngine.changesAsync(for: selectedSite, config: uploadConfig, modifiedAfter: uploadModifiedAfter)
                changes = normalizedChanges(mergedChanges(resumeChanges, latestChanges), site: selectedSite)
                if selectedSite.id == selectedSiteID || activeUploadSiteID == selectedSite.id {
                    resumeChanges = changes
                }
            } else {
                changes = normalizedChanges(try await NativeSyncEngine.changesAsync(for: selectedSite, config: uploadConfig, modifiedAfter: uploadModifiedAfter), site: selectedSite)
                if selectedSite.id == selectedSiteID || targetSite == nil {
                    resumeChanges = changes
                }
            }

            if selectedSite.id == selectedSiteID {
                pendingChanges = changes
            }
            clearUploadFailure()

            guard !changes.isEmpty else {
                if !silent {
                    addMessage(.success, title: "Nada para enviar", detail: "Nenhuma alteração foi encontrada.")
                }
                if selectedSite.id == selectedSiteID {
                    resumeChanges = []
                }
                activeUploadSiteID = nil
                activeUploadModifiedAfter = nil
                return true
            }

            isRunning = true
            activeUploadSiteID = selectedSite.id
            progress = SyncProgress(fraction: 0, title: resume ? "Retomando envio" : "Iniciando envio", detail: "\(changes.count) alterações pendentes", eta: "Calculando", phase: .preparing)

            while true {
                do {
                    _ = try await NativeSyncEngine.sync(site: selectedSite, config: uploadConfig, changes: changes) { [weak self] progress in
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
                    let latestChanges = try await NativeSyncEngine.changesAsync(for: selectedSite, config: uploadConfig, modifiedAfter: uploadModifiedAfter)
                    changes = normalizedChanges(mergedChanges(resumeChanges, latestChanges), site: selectedSite)
                    if selectedSite.id == selectedSiteID {
                        resumeChanges = changes
                        pendingChanges = changes
                    }
                    clearUploadFailure()

                    guard !changes.isEmpty else {
                        break
                    }

                    progress = SyncProgress(
                        fraction: progress.fraction,
                        title: "Retomando automaticamente \(automaticResumeCount)/\(automaticResumeLimit)",
                        detail: "\(changes.count) arquivos pendentes",
                        eta: "Tentando novamente",
                        phase: .preparing
                    )

                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            if selectedSite.id == selectedSiteID {
                pendingChanges = []
                resumeChanges = []
            }
            clearUploadFailure()
            addMessage(
                .success,
                title: silent ? "Sincronização automática concluída" : "Sincronização concluída",
                detail: "\(completedUploads) arquivos enviados, \(completedDeletes) removidos. \(formatBytes(completedBytes)) transferidos."
            )
            isRunning = false
            activeUploadSiteID = nil
            activeUploadModifiedAfter = nil
            return true
        } catch is CancellationError {
            if selectedSite.id == selectedSiteID {
                pendingChanges = resumeChanges
            }
            failedChange = nil
            lastUploadError = "Envio cancelado pelo usuário. Os arquivos que ainda não foram confirmados continuam na fila para retomada."
            progress = SyncProgress(fraction: progress.fraction, title: "Envio cancelado", detail: "\(resumeChanges.count) arquivos pendentes", eta: "", phase: .cancelled)
            if !silent {
                addMessage(.warning, title: "Envio cancelado", detail: "\(resumeChanges.count) arquivos continuam pendentes para retomada.")
            }
            isRunning = false
            activeUploadSiteID = nil
            activeUploadModifiedAfter = nil
            return false
        } catch {
            if selectedSite.id == selectedSiteID {
                pendingChanges = resumeChanges
            }
            failedChange = (error as? SyncError)?.failedChange
            lastUploadError = friendlyError(from: error.localizedDescription)
            progress = SyncProgress(fraction: progress.fraction, title: "Envio interrompido", detail: "\(resumeChanges.count) arquivos pendentes", eta: "Pronto para retomar", phase: .failed)
            addMessage(.error, title: "Sincronização falhou", detail: "O app tentou retomar automaticamente \(automaticResumeLimit) vezes, mas \(resumeChanges.count) arquivos ficaram pendentes.\n\n\(lastUploadError)")
            isRunning = false
            return false
        }
    }

    private func siteForUpload(targetSite: Site?, resume: Bool) -> Site? {
        if let targetSite {
            return targetSite
        }

        if resume, let activeUploadSiteID, let site = sites.first(where: { $0.id == activeUploadSiteID }) {
            return site
        }

        return selectedSite
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

    private func modifiedAfter(for site: Site) -> Date? {
        if site.id == selectedSiteID {
            return activeModifiedAfter
        }

        return site.modifiedAfter
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.16))
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adicionar sync")
                        .font(.title2.weight(.semibold))

                    Text(stepTitle)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Color.orange : Color.primary.opacity(0.13))
                            .frame(width: index == step ? 36 : 18, height: 5)
                            .animation(.easeOut(duration: 0.18), value: step)
                    }
                }
            }

            Spacer()
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
            .buttonStyle(.borderedProminent)
            .tint(.orange)
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
