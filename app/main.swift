// Orquestra.app — painel visual nativo do orquestrador nvo.
// Maestro no topo, agentes conectados por cabos, notas como fonte de verdade.
// O merge (nvo done) abre o Terminal de proposito: confirmacao digitada e
// decisao humana, nunca um botao.

import SwiftUI
import AppKit

// MARK: - Shell

let HOME = FileManager.default.homeDirectoryForCurrentUser.path
let ORQ = "\(HOME)/orquestra"
let NVO = "\(ORQ)/bin/nvo"
let SESSION = "orquestra"

func toolPath(_ name: String) -> String {
    for p in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"] {
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return name
}
let TMUX = toolPath("tmux")
let GIT = "/usr/bin/git"

@discardableResult
func sh(_ path: String, _ args: [String], stdin: String? = nil) -> (code: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(ORQ)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    p.environment = env
    let outPipe = Pipe(), errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    if let s = stdin {
        let inPipe = Pipe()
        p.standardInput = inPipe
        inPipe.fileHandleForWriting.write(s.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()
    }
    do { try p.run() } catch { return (1, "", "\(error)") }
    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    p.waitUntilExit()
    return (p.terminationStatus, out, err)
}

func notifyMac(_ title: String, _ body: String) {
    let t = title.replacingOccurrences(of: "\"", with: "'")
    let b = body.replacingOccurrences(of: "\"", with: "'")
    sh("/usr/bin/osascript", ["-e", "display notification \"\(b)\" with title \"\(t)\" sound name \"Glass\""])
}

func openTerminal(_ command: String) {
    let cmd = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let script = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
    sh("/usr/bin/osascript", ["-e", script])
}

// MARK: - Model

enum AgentStatus: String {
    case trabalhando, aguardando, concluido, bloqueado
    var color: Color {
        switch self {
        case .trabalhando: return Color(red: 0.63, green: 0.63, blue: 0.67)  // cinza: em curso
        case .aguardando: return Color(red: 0.35, green: 0.78, blue: 0.98)   // azul: plano pronto
        case .concluido: return Color(red: 0.8, green: 1.0, blue: 0.0)       // verde nevoa
        case .bloqueado: return Color(red: 1.0, green: 0.42, blue: 0.42)
        }
    }
    var label: String {
        switch self {
        case .trabalhando: return "trabalhando"
        case .aguardando: return "plano aguardando"
        case .concluido: return "concluído"
        case .bloqueado: return "bloqueado"
        }
    }
}

// Detecta um menu de escolha do Claude Code na tela ("1. Yes / 2. No") para
// oferecer botoes de resposta dentro do app, sem trocar de janela.
struct PanePrompt {
    let options: [(key: String, label: String)]
    var isAsking: Bool { !options.isEmpty }

    init(pane: String) {
        let tail = String(pane.suffix(1500))
        var found: [(String, String)] = []
        for raw in tail.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t❯>│|"))
            guard let first = line.first, first.isNumber,
                  line.count > 3 else { continue }
            let idx = line.index(line.startIndex, offsetBy: 1)
            guard line[idx] == "." || line[idx] == ")" else { continue }
            let key = String(first)
            var label = String(line[line.index(after: idx)...])
                .trimmingCharacters(in: .whitespaces)
            if label.isEmpty { continue }
            if label.count > 46 { label = String(label.prefix(44)) + "…" }
            if !found.contains(where: { $0.0 == key }) { found.append((key, label)) }
        }
        // exige pelo menos duas opcoes para nao confundir com lista comum
        self.options = found.count >= 2 ? Array(found.prefix(4)) : []
    }
}

// Barra de teclas: responde prompts e navega sem sair do app
struct TerminalKeys: View {
    let window: String
    let pane: String
    let orch: Orchestra

    var body: some View {
        let prompt = PanePrompt(pane: pane)
        VStack(alignment: .leading, spacing: 5) {
            if prompt.isAsking {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 9))
                        .foregroundColor(Theme.accent)
                    Text("precisa da sua resposta:")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.accent)
                    ForEach(prompt.options, id: \.key) { opt in
                        Button {
                            orch.sendLiteral(window, opt.key)
                        } label: {
                            Text("\(opt.key). \(opt.label)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Theme.bg)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.accent)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("responde \(opt.key) direto no terminal do agente")
                    }
                    Spacer()
                }
            }
            HStack(spacing: 4) {
                Text("teclas").font(.system(size: 8)).foregroundColor(Theme.dim.opacity(0.7))
                keyButton("↑", "Up"); keyButton("↓", "Down")
                keyButton("⏎", "Enter"); keyButton("esc", "Escape")
                keyButton("tab", "Tab"); keyButton("⌃C", "C-c")
                ForEach(["1", "2", "3"], id: \.self) { d in
                    Button { orch.sendLiteral(window, d) } label: {
                        Text(d).font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.dim)
                            .frame(minWidth: 16)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06)).cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("envia a tecla \(d)")
                }
                Spacer()
            }
        }
    }

    func keyButton(_ label: String, _ tmuxKey: String) -> some View {
        Button { orch.sendKey(window, tmuxKey) } label: {
            Text(label).font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.dim)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.white.opacity(0.06)).cornerRadius(3)
        }
        .buttonStyle(.plain)
        .help("envia \(label) para o terminal")
    }
}

struct UsageInfo: Equatable {
    let blockActive: Bool
    let blockTokens: Int
    let blockCost: Double
    let blockReset: String?
    let todayTokens: Int
    let todayCost: Double
    let models: String

    static func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}

struct AgentInfo: Identifiable, Equatable {
    let name: String
    var branch: String
    var changes: Int
    var status: AgentStatus
    var pane: String
    var note: String
    var cli: String = "claude"
    var model: String = ""
    var id: String { name }
}

final class Orchestra: ObservableObject {
    @Published var project: String?
    @Published var repo: String?
    @Published var agents: [AgentInfo] = []
    @Published var maestroPane: String = ""
    @Published var maestroRunning = false
    @Published var lastError: String?
    @Published var codexInstalled = false
    @Published var usage: UsageInfo?

    private var lastStatus: [String: AgentStatus] = [:]
    private var timer: Timer?
    private var usageTimer: Timer?

    init() {
        DispatchQueue.global().async {
            let found = sh("/bin/bash", ["-lc", "command -v codex"]).code == 0
            DispatchQueue.main.async { self.codexInstalled = found }
        }
        refresh()
        refreshUsage()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    func refreshUsage() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let r = sh("/usr/bin/python3", ["\(ORQ)/bin/nvo-usage.py", "--json"], stdin: nil)
            guard r.code == 0,
                  let data = r.out.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            let block = obj["block"] as? [String: Any] ?? [:]
            let today = obj["today"] as? [String: Any] ?? [:]
            let models = (obj["models"] as? [[String: Any]] ?? []).prefix(3).map { m in
                "\(m["name"] as? String ?? "?") \(Int(((m["share"] as? Double) ?? 0) * 100))%"
            }
            let info = UsageInfo(
                blockActive: block["active"] as? Bool ?? false,
                blockTokens: block["tokens"] as? Int ?? 0,
                blockCost: block["cost"] as? Double ?? 0,
                blockReset: block["reset"] as? String,
                todayTokens: today["tokens"] as? Int ?? 0,
                todayCost: today["cost"] as? Double ?? 0,
                models: models.joined(separator: " · "))
            DispatchQueue.main.async { self?.usage = info }
        }
    }

    func ensureSession() {
        if sh(TMUX, ["has-session", "-t", SESSION]).code != 0 {
            sh(TMUX, ["new-session", "-d", "-s", SESSION, "-n", "maestro", "-c", ORQ])
        }
    }

    // o marcador de status que aparece por ultimo nas notas manda
    static func statusFromNote(_ note: String) -> AgentStatus {
        let tail = String(note.suffix(4000)).uppercased()
        var best: (Int, AgentStatus) = (-1, .trabalhando)
        for (needle, st) in [("STATUS: CONCLU", AgentStatus.concluido),
                             ("STATUS: AGUARDANDO", .aguardando),
                             ("BLOQUEADO", .bloqueado),
                             ("BLOQUEIO:", .bloqueado)] {
            if let r = tail.range(of: needle, options: .backwards) {
                let pos = tail.distance(from: tail.startIndex, to: r.lowerBound)
                if pos > best.0 { best = (pos, st) }
            }
        }
        return best.1
    }

    func pane(_ window: String, lines: Int = 40) -> String? {
        let r = sh(TMUX, ["capture-pane", "-pt", "\(SESSION):\(window)", "-S", "-200"])
        guard r.code == 0 else { return nil }
        let all = r.out.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return all.suffix(lines).joined(separator: "\n")
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let conf = "\(ORQ)/project.conf"
            let repo = (try? String(contentsOfFile: conf, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let proj = repo.map { URL(fileURLWithPath: $0).lastPathComponent }
            self.ensureSession()

            var list: [AgentInfo] = []
            if let proj = proj {
                let wtRoot = "\(ORQ)/worktrees/\(proj)"
                let names = ((try? FileManager.default.contentsOfDirectory(atPath: wtRoot)) ?? []).sorted()
                for name in names {
                    let wt = "\(wtRoot)/\(name)"
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: wt, isDirectory: &isDir), isDir.boolValue else { continue }
                    let branch = sh(GIT, ["-C", wt, "branch", "--show-current"]).out
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let changes = sh(GIT, ["-C", wt, "status", "--porcelain"]).out
                        .split(separator: "\n").count
                    let note = (try? String(contentsOfFile: "\(ORQ)/notes/\(proj)/\(name).md", encoding: .utf8)) ?? ""
                    // mesma logica do nvo: o marcador que aparece por ultimo manda
                    let status = Orchestra.statusFromNote(note)
                    var cli = "claude", model = ""
                    if let meta = try? String(contentsOfFile: "\(ORQ)/agents/\(proj)/\(name).meta",
                                              encoding: .utf8) {
                        for l in meta.split(separator: "\n") {
                            if l.hasPrefix("cli=") { cli = String(l.dropFirst(4)) }
                            if l.hasPrefix("model=") { model = String(l.dropFirst(6)) }
                        }
                    }
                    list.append(AgentInfo(name: name, branch: branch, changes: changes,
                                          status: status, pane: self.pane(name, lines: 12) ?? "(sem janela tmux)",
                                          note: String(note.suffix(8000)),
                                          cli: cli, model: model))
                }
            }
            let maestro = self.pane("maestro", lines: 40) ?? ""
            let running = maestro.count > 200 || maestro.lowercased().contains("claude")

            DispatchQueue.main.async {
                for a in list {
                    if let prev = self.lastStatus[a.name], prev != a.status, a.status != .trabalhando {
                        notifyMac("orquestra: \(a.name)",
                                  a.status == .concluido ? "terminou a tarefa — revise com diff/done"
                                                         : "está bloqueado e precisa de você")
                    }
                    self.lastStatus[a.name] = a.status
                }
                self.repo = repo
                self.project = proj
                self.agents = list
                self.maestroPane = maestro
                self.maestroRunning = running
            }
        }
    }

    // MARK: acoes (todas via nvo — o app nao inventa caminho proprio)

    // nvo maestro abre o claude DENTRO do projeto, com o briefing de orquestrador
    func startMaestro() {
        DispatchQueue.global().async {
            let r = sh(NVO, ["maestro"])
            if r.code != 0 {
                DispatchQueue.main.async { self.lastError = (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
    }

    func sendKey(_ window: String, _ key: String) {
        ensureSession()
        sh(TMUX, ["send-keys", "-t", "\(SESSION):\(window)", key])
    }

    func sendLiteral(_ window: String, _ text: String) {
        ensureSession()
        sh(TMUX, ["send-keys", "-t", "\(SESSION):\(window)", "-l", text])
    }

    func approvePlan(_ name: String) {
        DispatchQueue.global().async {
            sh(NVO, ["approve", name])
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func sendMaestro(_ text: String) {
        ensureSession()
        sh(TMUX, ["send-keys", "-t", "\(SESSION):maestro", "-l", text])
        usleep(300_000)
        sh(TMUX, ["send-keys", "-t", "\(SESSION):maestro", "Enter"])
    }

    func sendAgent(_ name: String, _ text: String) {
        let r = sh(NVO, ["send", name, text])
        if r.code != 0 { DispatchQueue.main.async { self.lastError = r.err } }
    }

    func newAgent(_ name: String, _ task: String, cli: String = "claude",
                  model: String = "", plan: Bool = false,
                  done: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            var args = ["new"]
            if plan { args.append("--plan") }
            args += [name, task, cli]
            if !model.isEmpty { args.append(model) }
            let r = sh(NVO, args)
            DispatchQueue.main.async {
                done(r.code == 0 ? nil : (r.err.isEmpty ? r.out : r.err))
                self.refresh()
            }
        }
    }

    func killAgent(_ name: String, done: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let r = sh(NVO, ["kill", name])
            DispatchQueue.main.async {
                done(r.code == 0 ? nil : r.err)
                self.refresh()
            }
        }
    }

    func diff(_ name: String, done: @escaping (String) -> Void) {
        DispatchQueue.global().async {
            let r = sh(NVO, ["diff", name])
            DispatchQueue.main.async { done(r.code == 0 ? (r.out.isEmpty ? "(sem mudanças)" : r.out) : r.err) }
        }
    }

    func initProject(_ path: String, done: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let r = sh(NVO, ["init", path])
            DispatchQueue.main.async { done(r.code == 0 ? nil : r.err); self.refresh() }
        }
    }

    func isGitRepo(_ path: String) -> Bool {
        sh(GIT, ["-C", path, "rev-parse", "--git-dir"]).code == 0
    }

    func cloneAndRegister(_ urlText: String, done: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            var url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            // aceita "usuario/repo" como atalho do GitHub
            if !url.contains("://") && !url.hasPrefix("git@"),
               url.split(separator: "/").count == 2 {
                url = "https://github.com/\(url).git"
            }
            let name = url.split(separator: "/").last.map(String.init)?
                .replacingOccurrences(of: ".git", with: "") ?? "repo"
            let dest = "\(ORQ)/repos/\(name)"
            if FileManager.default.fileExists(atPath: dest) {
                // ja clonado antes: so atualiza e registra
                sh(GIT, ["-C", dest, "pull", "--ff-only"])
                let r = sh(NVO, ["init", dest])
                DispatchQueue.main.async { done(r.code == 0 ? nil : r.err); self.refresh() }
                return
            }
            try? FileManager.default.createDirectory(atPath: "\(ORQ)/repos",
                                                     withIntermediateDirectories: true)
            let r = sh(GIT, ["clone", url, dest])
            if r.code != 0 {
                DispatchQueue.main.async { done("falha no clone: \(r.err.suffix(300))") }
                return
            }
            let r2 = sh(NVO, ["init", dest])
            DispatchQueue.main.async { done(r2.code == 0 ? nil : r2.err); self.refresh() }
        }
    }

    func gitInitAndRegister(_ path: String, done: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            var r = sh(GIT, ["-C", path, "init", "-b", "main"])
            if r.code == 0 {
                // worktree precisa de pelo menos um commit na base
                sh(GIT, ["-C", path, "add", "-A"])
                r = sh(GIT, ["-C", path, "-c", "user.email=orquestra@local",
                             "-c", "user.name=orquestra", "commit", "-m",
                             "estado inicial (orquestra)", "--allow-empty"])
            }
            if r.code != 0 {
                DispatchQueue.main.async { done(r.err) }
                return
            }
            let r2 = sh(NVO, ["init", path])
            DispatchQueue.main.async { done(r2.code == 0 ? nil : r2.err); self.refresh() }
        }
    }
}

// MARK: - Cabos (anchor preferences)

struct NodeAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Tema

// Paleta Nevoa AI (accent #CCFF00 de nevoaai.com) sobre neutros suaves —
// nada de preto puro: tons de grafite para um visual clean.
enum Theme {
    static let bg = Color(red: 0.11, green: 0.11, blue: 0.125)           // grafite suave
    static let card = Color(red: 0.145, green: 0.145, blue: 0.16)
    static let cardBorder = Color.white.opacity(0.09)
    static let terminalBg = Color(red: 0.085, green: 0.085, blue: 0.098)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let dim = Color(red: 0.66, green: 0.66, blue: 0.70)
    static let accent = Color(red: 0.8, green: 1.0, blue: 0.0)           // #CCFF00
    static let cable = Color(red: 0.8, green: 1.0, blue: 0.0).opacity(0.25)
    static let nevoa = Color(red: 0.8, green: 1.0, blue: 0.0)
}

// MARK: - Views auxiliares

struct TerminalText: View {
    let content: String
    var size: CGFloat = 10.5
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(content.isEmpty ? " " : content)
                        .font(.system(size: size, design: .monospaced))
                        .foregroundColor(Theme.text.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(8)
            }
            .onChange(of: content) { _ in proxy.scrollTo("bottom") }
            .onAppear { proxy.scrollTo("bottom") }
        }
        .background(Theme.terminalBg)
        .cornerRadius(6)
    }
}

struct PromptField: View {
    let placeholder: String
    @Binding var text: String
    var submitLabel: String = "enviar"
    let onSubmit: (String) -> Void

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onSubmit(t)
        text = ""
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.accent)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.text)
                .onSubmit { submit() }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: submit) {
                    HStack(spacing: 3) {
                        Text(submitLabel).font(.system(size: 9, weight: .semibold))
                        Image(systemName: "paperplane.fill").font(.system(size: 8))
                    }
                    .foregroundColor(Theme.bg)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.accent)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("enviar (ou tecle Enter)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.terminalBg)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
    }
}

struct SmallButton: View {
    let label: String
    var icon: String? = nil
    var tint: Color = Theme.dim
    var help: String? = nil
    var prominent: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 9)) }
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(prominent ? Theme.bg : tint)
            .padding(.horizontal, prominent ? 12 : 8).padding(.vertical, prominent ? 6 : 4)
            .background(prominent ? Theme.accent : Color.white.opacity(0.06))
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help(help ?? label)
    }
}

// linha discreta de onboarding: aponta o proximo passo sem gritar
struct StepCard: View {
    let step: String
    let title: String
    let detail: String
    let buttonLabel: String
    let buttonIcon: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(step)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.accent)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.text)
            Text(detail).font(.system(size: 10)).foregroundColor(Theme.dim)
                .lineLimit(1).truncationMode(.tail)
                .help(detail)
            Spacer()
            SmallButton(label: buttonLabel, icon: buttonIcon, tint: Theme.accent,
                        help: detail, action: action)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.card.opacity(0.7))
        .cornerRadius(8)
        .frame(maxWidth: 760)
    }
}

// MARK: - Nos do canvas

struct MaestroNode: View {
    @ObservedObject var orch: Orchestra
    @State private var draft = ""

    private let examples: [(String, String)] = [
        ("👷 criar equipe", "cria um agente builder pra implementar [descreva a funcionalidade] e um agente reviewer pra auditar o trabalho dele. Me avisa quando os dois terminarem."),
        ("📋 ver progresso", "o que os agentes estão fazendo? Lê as notas de cada um e me dá um resumo curto."),
        ("🧹 corrigir rumo", "manda o agente builder priorizar [o que importa] antes de continuar o resto."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(orch.maestroRunning ? Theme.accent : Theme.dim)
                    .frame(width: 8, height: 8)
                Text("MAESTRO").font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.accent)
                    .help("o agente chefe: você fala com ele em português e ele cria e gerencia os outros agentes")
                Text(orch.project.map { "· \($0)" } ?? "")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.dim)
                Spacer()
                if !orch.maestroRunning {
                    SmallButton(label: "iniciar maestro", icon: "play.fill", tint: Theme.accent,
                                help: "abre o Claude Code na janela do maestro — é ele quem orquestra",
                                prominent: true) {
                        orch.startMaestro()
                    }
                }
                SmallButton(label: "ver ao vivo", icon: "terminal",
                            help: "abre o Terminal com todas as janelas (tmux). Sair: Ctrl-b depois d") {
                    openTerminal("tmux attach -t orquestra")
                }
            }
            TerminalText(content: orch.maestroPane.isEmpty
                         ? "o terminal do maestro aparece aqui quando você iniciar"
                         : orch.maestroPane, size: 11)
                .frame(height: 240)
            if orch.maestroRunning {
                TerminalKeys(window: "maestro", pane: orch.maestroPane, orch: orch)
            }
            if orch.maestroRunning && orch.agents.isEmpty && draft.isEmpty {
                HStack(spacing: 6) {
                    Text("experimente:").font(.system(size: 9)).foregroundColor(Theme.dim)
                    ForEach(examples, id: \.0) { ex in
                        Button {
                            draft = ex.1
                        } label: {
                            Text(ex.0).font(.system(size: 9, weight: .medium))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.1))
                                .cornerRadius(9)
                        }
                        .buttonStyle(.plain)
                        .help(ex.1)
                    }
                }
            }
            PromptField(placeholder: "escreva em português o que você quer que a equipe faça…",
                        text: $draft) { t in
                orch.sendMaestro(t)
            }
        }
        .padding(14)
        .background(Theme.card)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        .frame(maxWidth: 760)
        .anchorPreference(key: NodeAnchors.self, value: .bottom) { ["maestro": $0] }
    }
}

struct AgentNode: View {
    @ObservedObject var orch: Orchestra
    let agent: AgentInfo
    let onNotes: () -> Void
    let onDiff: () -> Void
    let onKill: () -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(agent.status.color).frame(width: 7, height: 7)
                Text(agent.name).font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Text(agent.status.label).font(.system(size: 9))
                    .foregroundColor(agent.status.color)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(agent.status.color.opacity(0.12)).cornerRadius(4)
                    .help(agent.status == .concluido
                          ? "o agente escreveu STATUS: CONCLUIDO nas notas — revise o diff e aprove"
                          : agent.status == .bloqueado
                          ? "o agente relatou um bloqueio — leia as notas e destrave ele"
                          : "o agente está trabalhando — acompanhe pela tela ou pelas notas")
                Spacer()
                Text("\(agent.changes) arq. alterados")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.dim)
                    .help("arquivos modificados no espaço isolado deste agente")
            }
            Text("\(agent.branch)  ·  \(agent.cli)\(agent.model.isEmpty ? "" : " · \(agent.model)")")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.dim)
            TerminalText(content: agent.pane).frame(height: 120)
            TerminalKeys(window: agent.name, pane: agent.pane, orch: orch)
            PromptField(placeholder: "mandar instrução para \(agent.name)…", text: $draft) { t in
                orch.sendAgent(agent.name, t)
            }
            if agent.status == .aguardando {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard").font(.system(size: 9))
                        .foregroundColor(AgentStatus.aguardando.color)
                    Text("plano pronto — revise antes de liberar")
                        .font(.system(size: 9)).foregroundColor(Theme.dim)
                    Spacer()
                    SmallButton(label: "ver plano", icon: "note.text",
                                help: "lê o plano que o agente escreveu nas notas", action: onNotes)
                    SmallButton(label: "aprovar plano", icon: "play.fill",
                                tint: AgentStatus.aguardando.color,
                                help: "libera o agente para executar o plano") {
                        orch.approvePlan(agent.name)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 6) {
                SmallButton(label: "notas", icon: "note.text",
                            help: "diário de progresso que o agente escreve — a forma mais rápida de saber onde ele está",
                            action: onNotes)
                SmallButton(label: "diff", icon: "plus.forwardslash.minus",
                            help: "todas as mudanças de código que o agente fez, comparadas com o projeto original",
                            action: onDiff)
                Spacer()
                SmallButton(label: "aprovar", icon: "checkmark.seal",
                            tint: AgentStatus.concluido.color,
                            help: "aplica o trabalho no projeto (merge). Abre o Terminal: você revê o diff e confirma digitando o nome do agente — segurança de verdade") {
                    openTerminal("export PATH=\"$HOME/orquestra/bin:$PATH\"; nvo done \(agent.name)")
                }
                SmallButton(label: "descartar", icon: "xmark",
                            tint: AgentStatus.bloqueado.color,
                            help: "encerra o agente sem aplicar nada. O trabalho fica guardado numa branch, dá pra recuperar",
                            action: onKill)
            }
        }
        .padding(12)
        .background(Theme.card)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        .frame(width: 340)
        .anchorPreference(key: NodeAnchors.self, value: .top) { ["agent-\(agent.name)": $0] }
    }
}

// MARK: - Navegador de arquivos (barra lateral, fechada por padrao)

struct FileEntry: Identifiable {
    let name: String
    let path: String
    let isDir: Bool
    let mtime: Date
    var id: String { path }
}

struct FileBrowser: View {
    let orch: Orchestra
    let onOpen: (String) -> Void
    @State private var source = ""   // "" = projeto base; senao nome do agente
    @State private var rel = ""      // subpasta atual

    var root: String? {
        guard let repo = orch.repo, let proj = orch.project else { return nil }
        return source.isEmpty ? repo : "\(ORQ)/worktrees/\(proj)/\(source)"
    }
    var current: String? {
        guard let r = root else { return nil }
        return rel.isEmpty ? r : "\(r)/\(rel)"
    }

    func entries() -> [FileEntry] {
        guard let dir = current else { return [] }
        let skip: Set<String> = ["node_modules", ".git", ".claude", "__pycache__", ".venv", "dist", "build"]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var out: [FileEntry] = []
        for n in names.sorted() {
            if n.hasPrefix(".") || skip.contains(n) { continue }
            let p = "\(dir)/\(n)"
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
            let attrs = try? FileManager.default.attributesOfItem(atPath: p)
            out.append(FileEntry(name: n, path: p, isDir: isDir.boolValue,
                                 mtime: (attrs?[.modificationDate] as? Date) ?? .distantPast))
        }
        return out.sorted { ($0.isDir ? 0 : 1, $0.name) < ($1.isDir ? 0 : 1, $1.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $source) {
                Text("projeto").tag("")
                ForEach(orch.agents) { a in Text(a.name).tag(a.name) }
            }
            .pickerStyle(.menu)
            .font(.system(size: 10))
            .onChange(of: source) { _ in rel = "" }

            if !rel.isEmpty {
                Button {
                    rel = rel.split(separator: "/").dropLast().joined(separator: "/")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 8))
                        Text(rel).font(.system(size: 9, design: .monospaced)).lineLimit(1)
                    }
                    .foregroundColor(Theme.dim)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries()) { e in
                        Button {
                            if e.isDir { rel = rel.isEmpty ? e.name : "\(rel)/\(e.name)" }
                            else { onOpen(e.path) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: e.isDir ? "folder.fill" : "doc.text")
                                    .font(.system(size: 9))
                                    .foregroundColor(e.isDir ? Theme.accent.opacity(0.7) : Theme.dim)
                                Text(e.name).font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(Theme.text.opacity(0.9)).lineLimit(1)
                                Spacer()
                                if !e.isDir && e.mtime > Date().addingTimeInterval(-900) {
                                    Circle().fill(AgentStatus.concluido.color).frame(width: 5, height: 5)
                                        .help("modificado ha pouco")
                                }
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("● verde = mexido nos últimos 15 min")
                .font(.system(size: 8)).foregroundColor(Theme.dim)
        }
        .padding(10)
        .frame(width: 220)
        .background(Theme.card.opacity(0.6))
    }
}

struct FileViewer: View {
    let path: String
    let onClose: () -> Void
    var content: String {
        guard let data = FileManager.default.contents(atPath: path) else { return "(não consegui ler)" }
        if data.count > 300_000 { return "(arquivo grande demais para visualizar — \(data.count / 1024) KB)" }
        return String(data: data, encoding: .utf8) ?? "(arquivo binário)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text").font(.system(size: 10)).foregroundColor(Theme.accent)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text).lineLimit(1)
                Spacer()
                SmallButton(label: "fechar", icon: "xmark", action: onClose)
            }
            Text(path.replacingOccurrences(of: HOME, with: "~"))
                .font(.system(size: 8, design: .monospaced)).foregroundColor(Theme.dim).lineLimit(1)
            TerminalText(content: content, size: 11)
        }
        .padding(10)
        .frame(width: 440)
        .background(Theme.card.opacity(0.6))
    }
}

// MARK: - Sheets

struct SheetTarget: Identifiable {
    enum Kind { case notes, diff, kill }
    let id = UUID()
    let name: String
    let kind: Kind
}

struct TextSheet: View {
    let title: String
    let content: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Spacer()
                SmallButton(label: "fechar", icon: "xmark") { dismiss() }
            }
            TerminalText(content: content, size: 11)
        }
        .padding(16)
        .frame(width: 680, height: 480)
        .background(Theme.bg)
    }
}

struct KillSheet: View {
    let name: String
    let orch: Orchestra
    @Environment(\.dismiss) var dismiss
    @State private var confirm = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encerrar agente sem merge").font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.text)
            Text("Remove a janela e o worktree de \"\(name)\". A branch agent/\(name) fica preservada. Digite o nome para confirmar:")
                .font(.system(size: 11)).foregroundColor(Theme.dim)
            TextField(name, text: $confirm)
                .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
            if let e = error {
                Text(e).font(.system(size: 10)).foregroundColor(AgentStatus.bloqueado.color)
            }
            HStack {
                Spacer()
                SmallButton(label: "cancelar") { dismiss() }
                SmallButton(label: "encerrar", icon: "xmark",
                            tint: confirm == name ? AgentStatus.bloqueado.color : Theme.dim) {
                    guard confirm == name else { return }
                    orch.killAgent(name) { err in
                        if let err = err { error = err } else { dismiss() }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(Theme.bg)
    }
}

struct NewAgentSheet: View {
    let orch: Orchestra
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var task = ""
    @State private var cli = "claude"
    @State private var model = ""
    @State private var planFirst = false
    @State private var error: String?
    @State private var creating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Novo agente").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
            TextField("nome (ex: builder)", text: $name)
                .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
            if orch.codexInstalled {
                Picker("", selection: $cli) {
                    Text("Claude Code").tag("claude")
                    Text("Codex").tag("codex")
                }
                .pickerStyle(.segmented)
            }
            if cli == "claude" {
                Picker("", selection: $model) {
                    Text("modelo padrão").tag("")
                    Text("Sonnet — rápido e econômico").tag("sonnet")
                    Text("Opus — máxima capacidade").tag("opus")
                    Text("Haiku — ultra barato").tag("haiku")
                }
                .pickerStyle(.menu)
                Text("dica: Sonnet resolve a maioria das tarefas de builder por ~40% do custo do Opus")
                    .font(.system(size: 9)).foregroundColor(Theme.dim)
            }
            Toggle(isOn: $planFirst) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("pedir plano antes de executar").font(.system(size: 11))
                        .foregroundColor(Theme.text)
                    Text("o agente escreve o que pretende fazer e espera sua aprovação — evita gastar token no caminho errado")
                        .font(.system(size: 9)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Text("Tarefa (seja específico: arquivo, critério de pronto, o que NÃO fazer)")
                .font(.system(size: 10)).foregroundColor(Theme.dim)
            TextEditor(text: $task)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.terminalBg).cornerRadius(6)
            if let e = error {
                Text(e).font(.system(size: 10)).foregroundColor(AgentStatus.bloqueado.color)
            }
            HStack {
                Spacer()
                SmallButton(label: "cancelar") { dismiss() }
                SmallButton(label: creating ? "criando…" : "criar agente", icon: "plus",
                            tint: Theme.accent) {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    let t = task.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !n.isEmpty, !t.isEmpty, !creating else { return }
                    creating = true
                    orch.newAgent(n, t, cli: cli, model: model, plan: planFirst) { err in
                        creating = false
                        if let err = err { error = err } else { dismiss() }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 480)
        .background(Theme.bg)
    }
}

struct InitSheet: View {
    let orch: Orchestra
    @Environment(\.dismiss) var dismiss
    @State private var mode = 0
    @State private var path = ""
    @State private var gitUrl = ""
    @State private var error: String?
    @State private var offerGitInit = false
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Escolher projeto").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
            Picker("", selection: $mode) {
                Text("pasta local").tag(0)
                Text("GitHub").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in error = nil; offerGitInit = false }
            if mode == 1 {
                Text("Cola a URL do repositório ou só usuario/repo. Ele clona para ~/orquestra/repos e registra (repos privados usam sua credencial git já configurada).")
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                TextField("ex: nevoa-ai/busca-cnpj ou https://github.com/…", text: $gitUrl)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                if let e = error {
                    Text(e).font(.system(size: 10)).foregroundColor(AgentStatus.bloqueado.color)
                }
                HStack {
                    Spacer()
                    SmallButton(label: "cancelar") { dismiss() }
                    SmallButton(label: busy ? "clonando…" : "clonar e usar",
                                icon: "arrow.down.circle", tint: Theme.accent) {
                        let u = gitUrl.trimmingCharacters(in: .whitespaces)
                        guard !u.isEmpty, !busy else { return }
                        busy = true
                        orch.cloneAndRegister(u) { err in
                            busy = false
                            if let err = err { error = err } else { dismiss() }
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
            Text("Os agentes vão trabalhar SOMENTE dentro desta pasta (cada um em sua cópia isolada — worktree).")
                .font(.system(size: 11)).foregroundColor(Theme.dim)
            HStack {
                TextField("~/meus-projetos/minha-api", text: $path)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                SmallButton(label: "escolher…", icon: "folder") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Usar esta pasta"
                    if panel.runModal() == .OK, let url = panel.url {
                        path = url.path
                        error = nil
                        offerGitInit = !orch.isGitRepo(url.path)
                        if offerGitInit {
                            error = "Esta pasta ainda não é um repositório git — necessário para o isolamento dos agentes."
                        }
                    }
                }
            }
            if let e = error {
                Text(e).font(.system(size: 10)).foregroundColor(AgentStatus.bloqueado.color)
            }
            HStack {
                Spacer()
                SmallButton(label: "cancelar") { dismiss() }
                if offerGitInit {
                    SmallButton(label: "inicializar git e usar", icon: "wand.and.stars", tint: Theme.accent) {
                        let p = (path as NSString).expandingTildeInPath
                        guard !p.isEmpty else { return }
                        orch.gitInitAndRegister(p) { err in
                            if let err = err { error = err } else { dismiss() }
                        }
                    }
                } else {
                    SmallButton(label: "usar esta pasta", icon: "checkmark", tint: Theme.accent) {
                        let p = (path as NSString).expandingTildeInPath
                        guard !p.isEmpty else { return }
                        orch.initProject(p) { err in
                            if let err = err {
                                error = err
                                offerGitInit = !orch.isGitRepo(p)
                            } else { dismiss() }
                        }
                    }
                }
            }
            }
        }
        .padding(18)
        .frame(width: 480)
        .background(Theme.bg)
    }
}

struct HelpView: View {
    func row(_ icon: String, _ title: String, _ text: String, tint: Color = Theme.accent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.text)
                Text(text).font(.system(size: 10.5)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                    Text("O FLUXO").font(.system(size: 9, weight: .black)).foregroundColor(Theme.accent)
                    row("folder", "1 · Escolha o projeto",
                        "Pasta local ou repositório do GitHub. Cada agente trabalha numa cópia isolada — nada muda no seu projeto sem sua aprovação.")
                    row("play.fill", "2 · Inicie o maestro",
                        "Ele abre já dentro do seu projeto, sabendo que é um orquestrador. Fale em português: “cria um builder pra fazer X e um reviewer pra auditar”.")
                    row("person.3.fill", "3 · Acompanhe os agentes",
                        "Cada card mostra a tela ao vivo. Você recebe notificação do macOS quando alguém termina ou trava.")
                    row("checkmark.seal", "4 · Revise e aprove",
                        "Terminou? Clique em diff pra ver o trabalho e em aprovar pra aplicar no projeto. A confirmação final é digitada no Terminal — merge nunca é automático.")

                    Divider().background(Theme.cardBorder)
                    Text("OS STATUS").font(.system(size: 9, weight: .black)).foregroundColor(Theme.accent)
                    row("circle.fill", "cinza — trabalhando", "o agente está executando a tarefa", tint: Theme.dim)
                    row("circle.fill", "azul — plano aguardando", "ele escreveu o plano e parou; leia e clique em aprovar plano", tint: AgentStatus.aguardando.color)
                    row("circle.fill", "verde — concluído", "hora de revisar o diff e aprovar", tint: AgentStatus.concluido.color)
                    row("circle.fill", "vermelho — bloqueado", "o agente precisa de você; leia as notas dele", tint: AgentStatus.bloqueado.color)

                    Divider().background(Theme.cardBorder)
                    Text("BOM SABER").font(.system(size: 9, weight: .black)).foregroundColor(Theme.accent)
                    row("keyboard", "Responder sem sair do app",
                        "Quando um agente pede permissão, os botões de resposta (1, 2, 3…) aparecem acima do campo de texto. A linha de teclas (↑ ↓ ⏎ esc tab ⌃C) controla o terminal de dentro do painel.")
                    row("list.clipboard", "Pedir plano antes de executar",
                        "No “novo agente”, marque a caixa de plano. O agente escreve o que pretende fazer e espera sua aprovação — é o que mais economiza token em tarefa grande ou vaga.")
                    row("bolt.fill", "Medidor de tokens",
                        "A barra do topo mede o uso do Claude Code na sua máquina inteira (todas as sessões, não só os agentes daqui): janela de 5h, quando reseta e o total do dia. Os valores em $ são o equivalente em API — no plano Max é régua de consumo, não cobrança.")
                    row("dollarsign.circle", "Economize com modelos",
                        "No “novo agente”, escolha Sonnet pra construção (≈40% do custo do Opus) e deixe o Opus pra revisões críticas.")
                    row("shield.fill", "Segurança",
                        "Comandos perigosos (rm -rf, git push, acesso a .env e chaves) são bloqueados automaticamente. Descartar um agente preserva o trabalho numa branch.")

                    Divider().background(Theme.cardBorder)
                    Text("DÚVIDAS FREQUENTES").font(.system(size: 9, weight: .black)).foregroundColor(Theme.accent)
                    row("questionmark.circle", "O maestro pode estragar meu projeto?",
                        "Não. Cada agente trabalha numa cópia isolada (git worktree). Seu projeto original só muda quando você clica em aprovar e confirma no Terminal.")
                    row("questionmark.circle", "Fechei o app — perdi tudo?",
                        "Não. Os agentes continuam rodando no tmux em segundo plano. Reabra o app e está tudo lá.")
                    row("questionmark.circle", "Um agente travou, e agora?",
                        "Leia as notas dele (botão notas), destrave mandando uma instrução no campo do card — ou descarte e crie outro com uma tarefa mais específica.")
                    row("questionmark.circle", "Preciso saber git ou terminal?",
                        "Quase nada: o único momento de terminal é a confirmação do aprovar, que já abre pronto — você só digita o nome do agente.")

                    Divider().background(Theme.cardBorder)
                    Text("SOBRE").font(.system(size: 9, weight: .black)).foregroundColor(Theme.accent)
                    row("circle.hexagongrid.fill", "Orquestra",
                        "Orquestrador local de agentes de código (Claude Code e Codex). Open source, licença MIT — github.com/rodrigolinss/orquestra")
                    HStack {
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(URL(string:
                                "https://nevoaai.com/?utm_source=orquestra&utm_medium=about_tab&utm_campaign=opensource_orchestrator")!)
                        } label: {
                            Text("powered by nevoaai.com")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.nevoa)
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                        Spacer()
                    }
                    .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
    }
}

// MARK: - Tela principal

struct ContentView: View {
    @StateObject var orch = Orchestra()
    @State private var sheet: SheetTarget?
    @State private var showNew = false
    @State private var showInit = false
    @State private var diffText = "carregando…"
    @State private var showFiles = false
    @State private var openFile: String?
    @State private var helpTab = false

    var body: some View {
        VStack(spacing: 0) {
            // barra superior
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill").foregroundColor(Theme.accent)
                Text("orquestra").font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Button {
                    NSWorkspace.shared.open(URL(string:
                        "https://nevoaai.com/?utm_source=orquestra&utm_medium=app_badge&utm_campaign=opensource_orchestrator")!)
                } label: {
                    Text("powered by nevoaai.com")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.nevoa.opacity(0.9))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Theme.nevoa.opacity(0.35), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                // abas: painel | ajuda · sobre
                HStack(spacing: 2) {
                    ForEach([false, true], id: \.self) { isHelp in
                        Button {
                            helpTab = isHelp
                        } label: {
                            Text(isHelp ? "ajuda · sobre" : "painel")
                                .font(.system(size: 10, weight: helpTab == isHelp ? .semibold : .regular))
                                .foregroundColor(helpTab == isHelp ? Theme.text : Theme.dim)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(helpTab == isHelp ? Color.white.opacity(0.08) : .clear)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 8)
                if let repo = orch.repo {
                    Text(repo).font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.dim).lineLimit(1)
                }
                Spacer()
                if !helpTab, orch.project != nil {
                    SmallButton(label: "arquivos", icon: "sidebar.left",
                                tint: showFiles ? Theme.accent : Theme.dim,
                                help: "abre o navegador de arquivos: veja o projeto e o que cada agente mexeu (bolinha verde = recente)") {
                        showFiles.toggle()
                        if !showFiles { openFile = nil }
                    }
                }
                if !helpTab {
                    SmallButton(label: "projeto", icon: "folder",
                                help: "escolher a pasta ou repositório do GitHub em que a equipe vai trabalhar") { showInit = true }
                    SmallButton(label: "novo agente", icon: "plus", tint: Theme.accent,
                                help: "cria um agente manualmente — ou peça ao maestro em português, que ele cria sozinho") { showNew = true }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.card)

            // medidor: uso do Claude Code na maquina toda (nao so os agentes daqui)
            if !helpTab, let u = orch.usage {
                HStack(spacing: 12) {
                    Text("uso claude code")
                        .foregroundColor(Theme.dim.opacity(0.7))
                    if u.blockActive {
                        Text("janela 5h: \(UsageInfo.fmt(u.blockTokens)) tok · ~$\(String(format: "%.2f", u.blockCost))")
                        if let r = u.blockReset {
                            Text("reseta \(r)").foregroundColor(Theme.dim)
                        }
                    } else {
                        Text("janela 5h: sem atividade")
                    }
                    Text("hoje: \(UsageInfo.fmt(u.todayTokens)) tok · ~$\(String(format: "%.2f", u.todayCost))")
                    if !u.models.isEmpty { Text(u.models) }
                    Spacer()
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.dim)
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(Theme.card.opacity(0.5))
                .help("Mede TODO o uso do Claude Code nesta máquina (qualquer sessão, não só os agentes do orquestra). Valores em $ são equivalente de API — no plano Max é régua de consumo, não cobrança. A janela de 5h é o ciclo do plano.")
            }

            Divider().background(Theme.cardBorder)

            if helpTab {
                HelpView()
            } else {
            HStack(spacing: 0) {
            if showFiles {
                FileBrowser(orch: orch) { openFile = $0 }
                Divider().background(Theme.cardBorder)
            }
            ScrollView {
                VStack(spacing: 40) {
                    // onboarding: o proximo passo sempre visivel
                    if orch.project == nil {
                        StepCard(step: "1",
                                 title: "Escolha o projeto",
                                 detail: "Uma pasta do seu Mac ou um repositório do GitHub. Os agentes só trabalham dentro dele, cada um numa cópia isolada — seus arquivos ficam intactos até você aprovar.",
                                 buttonLabel: "escolher projeto", buttonIcon: "folder") {
                            showInit = true
                        }
                    } else if !orch.maestroRunning {
                        StepCard(step: "2",
                                 title: "Inicie o maestro",
                                 detail: "O maestro é o agente chefe: você fala com ele em português e ele cria, acompanha e coordena os agentes que constroem de verdade.",
                                 buttonLabel: "iniciar maestro", buttonIcon: "play.fill") {
                            orch.startMaestro()
                        }
                    }
                    MaestroNode(orch: orch)
                    if orch.agents.isEmpty {
                        VStack(spacing: 6) {
                            Text(orch.maestroRunning
                                 ? "3º passo: peça uma equipe ao maestro no campo acima — ou use os exemplos"
                                 : "os agentes que o maestro criar aparecem aqui, conectados a ele")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.dim)
                        }
                        .padding(.bottom, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 360), spacing: 24)],
                                  spacing: 24) {
                            ForEach(orch.agents) { a in
                                AgentNode(orch: orch, agent: a,
                                    onNotes: { sheet = SheetTarget(name: a.name, kind: .notes) },
                                    onDiff: {
                                        diffText = "carregando…"
                                        sheet = SheetTarget(name: a.name, kind: .diff)
                                        orch.diff(a.name) { diffText = $0 }
                                    },
                                    onKill: { sheet = SheetTarget(name: a.name, kind: .kill) })
                            }
                        }
                        .frame(maxWidth: 1140)
                    }
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg)
            .overlayPreferenceValue(NodeAnchors.self) { anchors in
                GeometryReader { proxy in
                    Path { p in
                        guard let m = anchors["maestro"] else { return }
                        let mp = proxy[m]
                        for (key, a) in anchors where key.hasPrefix("agent-") {
                            let ap = proxy[a]
                            p.move(to: mp)
                            p.addCurve(to: ap,
                                       control1: CGPoint(x: mp.x, y: mp.y + 44),
                                       control2: CGPoint(x: ap.x, y: ap.y - 44))
                        }
                    }
                    .stroke(Theme.cable, style: StrokeStyle(lineWidth: 1.5))
                }
                .allowsHitTesting(false)
            }
            if let f = openFile {
                Divider().background(Theme.cardBorder)
                FileViewer(path: f) { openFile = nil }
            }
            }
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { s in
            switch s.kind {
            case .notes:
                TextSheet(title: "notas — \(s.name)",
                          content: orch.agents.first(where: { $0.name == s.name })?.note ?? "(sem notas)")
            case .diff:
                TextSheet(title: "diff — \(s.name)", content: diffText)
            case .kill:
                KillSheet(name: s.name, orch: orch)
            }
        }
        .sheet(isPresented: $showNew) { NewAgentSheet(orch: orch) }
        .sheet(isPresented: $showInit) { InitSheet(orch: orch) }
    }
}

@main
struct OrquestraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.automatic)
    }
}
