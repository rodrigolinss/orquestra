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

// O app roda pelo launchd, que da um PATH minimo (/usr/bin:/bin:...). Isso nao
// alcanca nem o homebrew nem ~/.local/bin — onde o Claude Code costuma morar.
// O tmux herda esse PATH, entao um "claude" fora dele falha silenciosamente
// dentro da janela. Montamos o PATH na mao para o app ver o mesmo que o shell.
let SEARCH_PATH = [
    "\(ORQ)/bin",
    "\(HOME)/.local/bin",          // instalador oficial do Claude Code
    "\(HOME)/bin",
    "/opt/homebrew/bin",           // homebrew, Apple Silicon
    "/usr/local/bin",              // homebrew, Intel
    "/usr/bin", "/bin", "/usr/sbin", "/sbin",
].joined(separator: ":")

func toolPath(_ name: String) -> String {
    for dir in SEARCH_PATH.split(separator: ":") {
        let p = "\(dir)/\(name)"
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
    env["PATH"] = SEARCH_PATH
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

// O merge exige terminal de proposito (confirmacao digitada). Mas o AppleScript
// falha calado quando a permissao de Automacao esta negada — devolvemos o erro
// para quem chamou em vez de deixar o botao parecer quebrado.
@discardableResult
func openTerminal(_ command: String) -> String? {
    let cmd = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let script = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
    let r = sh("/usr/bin/osascript", ["-e", script])
    guard r.code != 0 else { return nil }
    let detalhe = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
    return """
    não consegui abrir o Terminal (\(detalhe.isEmpty ? "erro \(r.code)" : detalhe)).
    Permita em Ajustes do Sistema › Privacidade e Segurança › Automação › Orquestra.
    Ou rode você mesmo:  \(command)
    """
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
                    Image(systemName: "hand.raised.fill").font(.system(size: Theme.uiSize(9)))
                        .foregroundColor(Theme.accent)
                    Text("precisa da sua resposta:")
                        .font(.system(size: Theme.uiSize(9), weight: .semibold)).foregroundColor(Theme.accent)
                    ForEach(prompt.options, id: \.key) { opt in
                        Button {
                            orch.sendLiteral(window, opt.key)
                        } label: {
                            Text("\(opt.key). \(opt.label)")
                                .font(.system(size: Theme.uiSize(9), weight: .medium))
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
                Text("teclas").font(.system(size: Theme.uiSize(8))).foregroundColor(Theme.dim.opacity(0.7))
                keyButton("↑", "Up"); keyButton("↓", "Down")
                keyButton("⏎", "Enter"); keyButton("esc", "Escape")
                keyButton("tab", "Tab"); keyButton("⌃C", "C-c")
                ForEach(["1", "2", "3"], id: \.self) { d in
                    Button { orch.sendLiteral(window, d) } label: {
                        Text(d).font(.system(size: Theme.uiSize(9), design: .monospaced))
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
            Text(label).font(.system(size: Theme.uiSize(9), design: .monospaced))
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

// Um limite configuravel da equipe, com a faixa aceita e o porque — o numero
// sozinho nao ajuda ninguem a decidir se deve mexer nele.
enum Aba: String, CaseIterable, Identifiable {
    case painel, ajustes, ajuda
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .painel: return "painel"
        case .ajustes: return "ajustes"
        case .ajuda: return "ajuda · sobre"
        }
    }
}

struct Limite: Identifiable, Equatable {
    let key: String
    var value: Int
    let min: Int
    let max: Int
    let label: String
    let help: String
    var id: String { key }
}

struct Harness: Identifiable, Equatable {
    let id: String
    let label: String
    let installed: Bool
    let models: [String]
    let install: String     // comando para instalar, quando falta
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
    var task: String = ""        // o que foi pedido, em uma frase
    var progress: String = ""    // ultima linha util das notas: o que ele esta fazendo agora
    var parent: String = ""      // vazio = filho direto do maestro
    var depth: Int = 1           // maestro e 0; agentes dele, 1; subagentes, 2
    var id: String { name }
}

// A tarefa fica na 1a linha do .prompt ("Tarefa: ..."). Encurtamos na primeira
// frase para caber num resumo — o texto inteiro continua a um clique em notas.
func resumoTarefa(_ prompt: String, limite: Int = 160) -> String {
    guard let head = prompt.split(separator: "\n").first else { return "" }
    var t = String(head).trimmingCharacters(in: .whitespaces)
    if t.lowercased().hasPrefix("tarefa:") { t = String(t.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
    // corta na primeira frase, se ela sozinha ja disser o assunto
    if let dot = t.firstIndex(of: "."), t.distance(from: t.startIndex, to: dot) > 25 {
        t = String(t[t.startIndex..<dot])
    }
    if t.count > limite { t = String(t.prefix(limite)).trimmingCharacters(in: .whitespaces) + "…" }
    return t
}

// Ultima linha de conteudo das notas, ignorando cabecalhos e marcadores —
// serve como "o que ele esta fazendo agora" sem abrir o diario inteiro.
func ultimoProgresso(_ note: String) -> String {
    for raw in note.split(separator: "\n").reversed() {
        var l = raw.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty, !l.hasPrefix("#"), !l.hasPrefix("---") else { continue }
        while l.hasPrefix("-") || l.hasPrefix("*") || l.hasPrefix(">") {
            l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard l.count > 3 else { continue }
        return l.count > 150 ? String(l.prefix(150)) + "…" : l
    }
    return ""
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
    @Published var harnesses: [Harness] = []
    @Published var limites: [Limite] = []

    private var lastStatus: [String: AgentStatus] = [:]
    private var timer: Timer?
    private var usageTimer: Timer?

    // -- avisos e autonomia ---------------------------------------------------
    // som suave quando alguem pede resposta; liberdade = responder "1" sozinho
    @Published var soundOn: Bool = UserDefaults.standard.object(forKey: "aviso.som") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundOn, forKey: "aviso.som") }
    }
    @Published var autoYes: Bool = UserDefaults.standard.bool(forKey: "modo.liberdade") {
        didSet { UserDefaults.standard.set(autoYes, forKey: "modo.liberdade") }
    }
    @Published var somVolume: Double = {
        let v = UserDefaults.standard.double(forKey: "aviso.volume")
        return v > 0 ? v : 0.35
    }() {
        didSet { UserDefaults.standard.set(somVolume, forKey: "aviso.volume") }
    }
    private var lastPromptSig: [String: String] = [:]   // por janela: prompt ja avisado
    private var lastAutoAnswer: [String: Date] = [:]    // por assinatura: quando respondemos

    // "Purr" e o som mais discreto do sistema; o volume e da pessoa.
    // Instancia nova a cada toque: play() num som ainda tocando nao toca.
    static func somSuave(volume: Double = 0.35) {
        guard let s = NSSound(named: "Purr") else { return }
        s.volume = Float(min(1.0, max(0.05, volume)))
        s.play()
    }

    // Roda a cada refresh, na main. Toca o aviso so na TRANSICAO para "pedindo
    // resposta" (assinatura nova), nunca a cada ciclo. No modo liberdade,
    // responde "1" — a opcao afirmativa padrao do Claude Code — com trava de
    // 8s por assinatura para nao mandar "1" duas vezes enquanto a tela atualiza.
    private func processarPrompt(janela: String, pane: String) {
        let p = PanePrompt(pane: pane)
        guard p.isAsking else {
            lastPromptSig[janela] = nil
            return
        }
        let sig = janela + "|" + p.options.map { $0.key + $0.label }.joined()
        let novo = lastPromptSig[janela] != sig
        lastPromptSig[janela] = sig

        if autoYes {
            let agora = Date()
            if let ultima = lastAutoAnswer[sig], agora.timeIntervalSince(ultima) < 8 { return }
            lastAutoAnswer[sig] = agora
            sendLiteral(janela, "1")
        } else if novo, soundOn {
            Orchestra.somSuave(volume: somVolume)
        }
    }

    // Quais CLIs de agente existem, vindas do registro do nvo — assim adicionar
    // um harness novo e editar um arquivo de texto, sem tocar no app.
    func refreshHarnesses() {
        DispatchQueue.global().async { [weak self] in
            let r = sh(NVO, ["harnesses"])
            guard r.code == 0 else { return }
            let lista: [Harness] = r.out.split(separator: "\n").compactMap { linha in
                let c = linha.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard c.count >= 5 else { return nil }
                return Harness(id: c[0], label: c[1], installed: c[2] == "1",
                               models: c[3].split(separator: ",").map(String.init),
                               install: c[4])
            }
            DispatchQueue.main.async {
                self?.harnesses = lista
                self?.codexInstalled = lista.contains { $0.id == "codex" && $0.installed }
            }
        }
    }

    func refreshConfig() {
        DispatchQueue.global().async { [weak self] in
            let r = sh(NVO, ["config"])
            guard r.code == 0 else { return }
            let lista: [Limite] = r.out.split(separator: "\n").compactMap { linha in
                let c = linha.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard c.count >= 6, let v = Int(c[1]), let mn = Int(c[2]), let mx = Int(c[3])
                else { return nil }
                return Limite(key: c[0], value: v, min: mn, max: mx, label: c[4], help: c[5])
            }
            DispatchQueue.main.async { self?.limites = lista }
        }
    }

    func setLimite(_ key: String, _ value: Int) {
        DispatchQueue.global().async { [weak self] in
            let r = sh(NVO, ["config", key, "\(value)"])
            DispatchQueue.main.async {
                if r.code != 0 {
                    self?.lastError = (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                self?.refreshConfig()
            }
        }
    }

    init() {
        refreshHarnesses()
        refreshConfig()
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

    // Saber se a janela tem agente vivo olhando o texto da tela era chute: um
    // shell com bastante scrollback passava por agente. Perguntamos ao tmux qual
    // processo esta em primeiro plano — se nao for um shell, tem agente rodando.
    // (o binario do Claude Code aparece pelo nome da versao, ex. "2.1.220", entao
    // detectar pela negativa e o que aguenta atualizacao de versao)
    static let shellCommands: Set<String> = ["zsh", "bash", "sh", "fish", "login", "tmux", "dash", "ksh"]

    func windowBusy(_ window: String) -> Bool {
        let r = sh(TMUX, ["list-panes", "-t", "\(SESSION):\(window)", "-F", "#{pane_current_command}"])
        guard r.code == 0 else { return false }
        return r.out.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { !$0.isEmpty && !Orchestra.shellCommands.contains($0) }
    }

    // A statusline do Claude Code (contexto, uso, MCPs, hooks, reguas) ocupava
    // metade do card e empurrava para fora justamente o que interessa: o que o
    // agente esta fazendo. Ela e ruido aqui — o app ja mede uso na barra de cima.
    static func isRuido(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces)
        if l.isEmpty { return true }
        // reguas horizontais de qualquer largura
        if l.count > 8, l.allSatisfy({ "─━=—-_".contains($0) }) { return true }
        if l.contains("Context") && l.contains("%") { return true }
        if l.contains("Usage") && l.contains("%") { return true }
        if l.contains("resets in") { return true }
        if l.contains("MCPs") && l.contains("hooks") { return true }
        if l.contains("manual mode on") { return true }
        if l.contains("tmux focus-events") { return true }
        // linha de modelo/branch: "[Opus 5 (1M context)] │ orquestra git:(main) │ ⏱ 2m"
        if l.hasPrefix("[") && l.contains("git:(") { return true }
        return false
    }

    func pane(_ window: String, lines: Int = 40) -> String? {
        let r = sh(TMUX, ["capture-pane", "-pt", "\(SESSION):\(window)", "-S", "-200"])
        guard r.code == 0 else { return nil }
        let all = r.out.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !Orchestra.isRuido($0) }
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
                    var cli = "claude", model = "", parent = "", depth = 1
                    if let meta = try? String(contentsOfFile: "\(ORQ)/agents/\(proj)/\(name).meta",
                                              encoding: .utf8) {
                        for l in meta.split(separator: "\n") {
                            if l.hasPrefix("cli=") { cli = String(l.dropFirst(4)) }
                            if l.hasPrefix("model=") { model = String(l.dropFirst(6)) }
                            if l.hasPrefix("parent=") { parent = String(l.dropFirst(7)) }
                            if l.hasPrefix("depth=") { depth = Int(String(l.dropFirst(6))) ?? 1 }
                        }
                    }
                    let prompt = (try? String(contentsOfFile: "\(ORQ)/agents/\(proj)/\(name).prompt",
                                              encoding: .utf8)) ?? ""
                    list.append(AgentInfo(name: name, branch: branch, changes: changes,
                                          status: status, pane: self.pane(name, lines: 12) ?? "(sem janela tmux)",
                                          note: String(note.suffix(8000)),
                                          cli: cli, model: model,
                                          task: resumoTarefa(prompt),
                                          progress: ultimoProgresso(note),
                                          parent: parent, depth: depth))
                }
            }
            let maestro = self.pane("maestro", lines: 40) ?? ""
            let running = self.windowBusy("maestro")

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
                // aviso sonoro / modo liberdade: maestro e todos os agentes
                self.processarPrompt(janela: "maestro", pane: maestro)
                for a in list { self.processarPrompt(janela: a.name, pane: a.pane) }
            }
        }
    }

    // MARK: acoes (todas via nvo — o app nao inventa caminho proprio)

    // Modelo do maestro: escolha da pessoa, guardada entre sessoes. Os workers
    // o maestro dosa sozinho pela complexidade; o cerebro do chefe e quem paga
    // a conta que decide.
    static let maestroModelKey = "maestro.model"
    var maestroModel: String {
        get { UserDefaults.standard.string(forKey: Self.maestroModelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.maestroModelKey); objectWillChange.send() }
    }

    // nvo maestro abre o claude DENTRO do projeto, com o briefing de orquestrador
    func startMaestro() {
        let model = maestroModel
        DispatchQueue.global().async {
            var args = ["maestro", "claude"]
            if !model.isEmpty { args.append(model) }
            let r = sh(NVO, args)
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

    // Merge sem sair do app. A confirmacao digitada continua obrigatoria — ela
    // viaja como argumento e o nvo recusa se nao bater com o nome do agente.
    func doneAgent(_ name: String, confirm: String, done: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let r = sh(NVO, ["done", name, "--confirm", confirm])
            let saida = (r.err + "\n" + r.out).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                done(r.code == 0 ? nil : (saida.isEmpty ? "o merge falhou (código \(r.code))" : saida))
                self.refresh()
            }
        }
    }

    // Fecha o expediente: derruba maestro e agentes, preserva o trabalho no disco.
    func stopSession(keepProject: Bool, done: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let r = sh(NVO, keepProject ? ["stop"] : ["stop", "--forget-project"])
            let saida = (r.err + "\n" + r.out).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                done(r.code == 0 ? nil : (saida.isEmpty ? "não consegui encerrar a sessão" : saida))
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

// Pan do canvas estilo Figma: clicar no VAZIO e arrastar move a visao.
// Fica atras dos cards no ZStack, entao so recebe o clique onde nao ha card.
// Move o NSScrollView diretamente em coordenadas de tela — independe do zoom.
struct PanArea: NSViewRepresentable {
    final class PanView: NSView {
        private var last: NSPoint?

        override func mouseDown(with event: NSEvent) {
            last = event.locationInWindow
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let scroll = enclosingScrollView, let l = last else { return }
            let p = event.locationInWindow
            let clip = scroll.contentView
            var o = clip.bounds.origin
            o.x -= (p.x - l.x)
            o.y += clip.isFlipped ? (p.y - l.y) : -(p.y - l.y)
            o = clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin
            clip.setBoundsOrigin(o)
            scroll.reflectScrolledClipView(clip)
            last = p
        }

        override func mouseUp(with event: NSEvent) {
            last = nil
            NSCursor.pop()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    func makeNSView(context: Context) -> PanView { PanView() }
    func updateNSView(_ nsView: PanView, context: Context) {}
}

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

    static func uiSize(_ base: CGFloat) -> CGFloat { base * CGFloat(UIScale.shared.zoom) }
}

// Zoom global. O painel nasceu com tipografia de 10–11pt, confortavel so em
// tela grande. Como o SwiftUI nao tem zoom de janela, escalamos na fonte: e
// nitido em qualquer passo, diferente de um scaleEffect na raiz.
// Observavel para que mudar o zoom redesenhe a arvore toda.
final class UIScale: ObservableObject {
    static let shared = UIScale()
    static let steps: [Double] = [0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
    private static let key = "ui.zoom"

    @Published var zoom: Double {
        didSet { UserDefaults.standard.set(zoom, forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.key)
        zoom = saved > 0 ? saved : 1.0
    }

    var canZoomIn: Bool { zoom < Self.steps.last! - 0.001 }
    var canZoomOut: Bool { zoom > Self.steps.first! + 0.001 }

    func zoomIn()  { if let n = Self.steps.first(where: { $0 > zoom + 0.001 }) { zoom = n } }
    func zoomOut() { if let n = Self.steps.last(where:  { $0 < zoom - 0.001 }) { zoom = n } }
    func reset()   { zoom = 1.0 }

    var label: String { "\(Int((zoom * 100).rounded()))%" }
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
                        .font(.system(size: Theme.uiSize(size), design: .monospaced))
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

// Historico de prompts por campo, igual ao do shell: sobrevive ao fechar o app
// para que voce nao perca a instrucao boa que escreveu ontem.
enum PromptHistory {
    static let limit = 60

    static func load(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: "history.\(key)") ?? []
    }

    static func append(_ key: String, _ entry: String) -> [String] {
        var h = load(key)
        if h.last == entry { return h }          // repetir o mesmo comando nao vira duas entradas
        h.append(entry)
        if h.count > limit { h.removeFirst(h.count - limit) }
        UserDefaults.standard.set(h, forKey: "history.\(key)")
        return h
    }
}

struct PromptField: View {
    let placeholder: String
    @Binding var text: String
    var submitLabel: String = "enviar"
    var historyKey: String? = nil
    let onSubmit: (String) -> Void

    @State private var history: [String] = []
    @State private var cursor: Int? = nil      // nil = escrevendo algo novo
    @State private var stash: String = ""      // o rascunho guardado antes de subir no historico

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let k = historyKey { history = PromptHistory.append(k, t) }
        cursor = nil
        stash = ""
        // o tmux send-keys manda linha a linha; achatamos para o prompt chegar
        // inteiro como uma instrucao so
        onSubmit(t.replacingOccurrences(of: "\n", with: " "))
        text = ""
    }

    // Imagem da area de transferencia vira arquivo em ~/orquestra/attachments
    // e o caminho entra no prompt — o agente le a imagem pelo caminho.
    private func colarImagem() {
        let pb = NSPasteboard.general
        let png: Data? = pb.data(forType: .png)
            ?? NSImage(pasteboard: pb)?.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
        guard let data = png else { NSSound.beep(); return }
        let dir = "\(ORQ)/attachments"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let path = "\(dir)/colado-\(df.string(from: Date())).png"
        guard (try? data.write(to: URL(fileURLWithPath: path))) != nil else { NSSound.beep(); return }
        text += (text.isEmpty ? "" : " ") + path + " "
    }

    // ↑ caminha para tras no historico; ↓ volta e devolve o rascunho no fim
    private func recall(back: Bool) -> KeyPress.Result {
        guard historyKey != nil, !history.isEmpty else { return .ignored }
        // num texto de varias linhas as setas sao do cursor, nao do historico
        guard cursor != nil || !text.contains("\n") else { return .ignored }
        if back {
            let next: Int
            if let c = cursor {
                guard c > 0 else { return .handled }   // ja no mais antigo: segura
                next = c - 1
            } else {
                stash = text                            // guarda o que estava sendo digitado
                next = history.count - 1
            }
            cursor = next
            text = history[next]
        } else {
            guard let c = cursor else { return .ignored }
            if c + 1 < history.count {
                cursor = c + 1
                text = history[c + 1]
            } else {
                cursor = nil
                text = stash                            // saiu do historico: rascunho de volta
            }
        }
        return .handled
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Image(systemName: "chevron.right").font(.system(size: Theme.uiSize(9), weight: .bold))
                .foregroundColor(Theme.accent)
                .padding(.bottom, 3)
            // bloco de texto: cresce ate 5 linhas e depois rola por dentro —
            // prompt bom raramente cabe numa linha so
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: Theme.uiSize(11), design: .monospaced))
                .foregroundColor(Theme.text)
                .onSubmit { submit() }
                .onKeyPress(.upArrow) { recall(back: true) }
                .onKeyPress(.downArrow) { recall(back: false) }
                .onPasteCommand(of: [.png, .tiff, .image]) { _ in colarImagem() }
                .onAppear { if let k = historyKey { history = PromptHistory.load(k) } }
            // anexo por clique: cobre o caso do ⌘V nao chegar ate nos quando o
            // campo ja esta em edicao
            Button(action: colarImagem) {
                Image(systemName: "paperclip")
                    .font(.system(size: Theme.uiSize(10)))
                    .foregroundColor(Theme.dim)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)
            .help("cola a imagem da área de transferência (print de tela, por exemplo): ela vira um arquivo e o caminho entra no prompt para o agente ler")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: submit) {
                    HStack(spacing: 3) {
                        Text(submitLabel).font(.system(size: Theme.uiSize(9), weight: .semibold))
                        Image(systemName: "paperplane.fill").font(.system(size: Theme.uiSize(8)))
                    }
                    .foregroundColor(Theme.bg)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.accent)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 1)
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
                if let icon = icon { Image(systemName: icon).font(.system(size: Theme.uiSize(9))) }
                Text(label).font(.system(size: Theme.uiSize(10), weight: .medium))
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
                .font(.system(size: Theme.uiSize(9), weight: .bold, design: .monospaced))
                .foregroundColor(Theme.accent)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
            Text(title).font(.system(size: Theme.uiSize(11), weight: .semibold)).foregroundColor(Theme.text)
            Text(detail).font(.system(size: Theme.uiSize(10))).foregroundColor(Theme.dim)
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
    @ObservedObject private var layout = AgentLayout.shared
    @State private var dragging = false
    @State private var resizing = false
    // commit incremental a cada frame: nunca ha "soltar e voltar"
    @State private var lastDrag: CGSize = .zero
    @State private var lastResize: CGSize = .zero

    private var box: AgentLayout.Box { layout.maestroBox }
    private var liveX: CGFloat { box.x }
    private var liveY: CGFloat { box.y }
    private var liveW: CGFloat { box.w }
    private var liveH: CGFloat { box.h }
    private var active: Bool { dragging || resizing }

    private let examples: [(String, String)] = [
        ("👷 criar equipe", "cria um agente builder pra implementar [descreva a funcionalidade] e um agente reviewer pra auditar o trabalho dele. Me avisa quando os dois terminarem."),
        ("📋 ver progresso", "o que os agentes estão fazendo? Lê as notas de cada um e me dá um resumo curto."),
        ("🧹 corrigir rumo", "manda o agente builder priorizar [o que importa] antes de continuar o resto."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: Theme.uiSize(11), weight: .bold))
                    .foregroundColor(dragging ? Theme.accent : Theme.dim.opacity(0.55))
                    .padding(.horizontal, 3).padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .help("arraste para mover o maestro · duplo clique volta ao lugar original")
                    .onHover { $0 ? NSCursor.openHand.push() : NSCursor.pop() }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in
                                // divide pelo zoom: o card segue o cursor 1:1
                                // em qualquer escala do canvas
                                layout.moveMaestro(by: CGSize(
                                    width: (v.translation.width - lastDrag.width) / layout.zoom,
                                    height: (v.translation.height - lastDrag.height) / layout.zoom))
                                lastDrag = v.translation
                                dragging = true
                            }
                            .onEnded { _ in
                                lastDrag = .zero
                                dragging = false
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            layout.reset(AgentLayout.maestroKey)
                        }
                    }
                Circle().fill(orch.maestroRunning ? Theme.accent : Theme.dim)
                    .frame(width: 8, height: 8)
                Text("MAESTRO").font(.system(size: Theme.uiSize(12), weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.accent)
                    .help("o agente chefe: você fala com ele em português e ele cria e gerencia os outros agentes")
                Text(orch.project.map { "· \($0)" } ?? "")
                    .font(.system(size: Theme.uiSize(11), design: .monospaced)).foregroundColor(Theme.dim)
                Spacer()
                if !orch.maestroRunning {
                    // o cerebro do maestro e escolha da pessoa; workers ele dosa sozinho
                    Menu {
                        Picker("modelo do maestro", selection: Binding(
                            get: { orch.maestroModel },
                            set: { orch.maestroModel = $0 })) {
                            Text("modelo padrão").tag("")
                            Text("Opus — melhor pra coordenar").tag("opus")
                            Text("Sonnet — mais barato").tag("sonnet")
                            Text("Haiku — mínimo").tag("haiku")
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "brain").font(.system(size: Theme.uiSize(8)))
                            Text(orch.maestroModel.isEmpty ? "modelo" : orch.maestroModel)
                                .font(.system(size: Theme.uiSize(9), design: .monospaced))
                        }
                        .foregroundColor(Theme.dim)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.05)).cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("qual modelo o maestro usa — os agentes dele você controla no “novo agente”, ou ele escolhe pela complexidade")
                    SmallButton(label: "iniciar maestro", icon: "play.fill", tint: Theme.accent,
                                help: "abre o Claude Code na janela do maestro — é ele quem orquestra",
                                prominent: true) {
                        orch.startMaestro()
                    }
                }
                SmallButton(label: "ver ao vivo", icon: "terminal",
                            help: "abre o Terminal com todas as janelas (tmux). Sair: Ctrl-b depois d") {
                    if let erro = openTerminal("tmux attach -t orquestra") { orch.lastError = erro }
                }
            }
            // o terminal absorve o espaco extra: maestro maior mostra mais tela
            TerminalText(content: orch.maestroPane.isEmpty
                         ? "o terminal do maestro aparece aqui quando você iniciar"
                         : orch.maestroPane, size: 11)
                .frame(minHeight: 120, maxHeight: .infinity)
            if orch.maestroRunning {
                TerminalKeys(window: "maestro", pane: orch.maestroPane, orch: orch)
            }
            if orch.maestroRunning && orch.agents.isEmpty && draft.isEmpty {
                HStack(spacing: 6) {
                    Text("experimente:").font(.system(size: Theme.uiSize(9))).foregroundColor(Theme.dim)
                    ForEach(examples, id: \.0) { ex in
                        Button {
                            draft = ex.1
                        } label: {
                            Text(ex.0).font(.system(size: Theme.uiSize(9), weight: .medium))
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
                        text: $draft, historyKey: "maestro") { t in
                orch.sendMaestro(t)
            }
        }
        .padding(14)
        .frame(width: liveW, height: liveH, alignment: .topLeading)
        .background(Theme.card)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(active ? Theme.accent.opacity(0.7) : Theme.accent.opacity(0.35), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: Theme.uiSize(8), weight: .bold))
                .foregroundColor(resizing ? Theme.accent : Theme.dim.opacity(0.5))
                .padding(6)
                .contentShape(Rectangle())
                .help("arraste para redimensionar o maestro")
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            layout.resizeMaestro(by: CGSize(
                                width: (v.translation.width - lastResize.width) / layout.zoom,
                                height: (v.translation.height - lastResize.height) / layout.zoom))
                            lastResize = v.translation
                            resizing = true
                        }
                        .onEnded { _ in
                            lastResize = .zero
                            resizing = false
                        }
                )
        }
        .shadow(color: .black.opacity(active ? 0.5 : 0), radius: active ? 16 : 0)
        // a ancora vem ANTES do .position: assim ela pertence ao card (nao ao
        // involucro que preenche o canvas) e resolve na posicao real dele,
        // acompanhando o arraste frame a frame
        .anchorPreference(key: NodeAnchors.self, value: .bottom) { ["maestro": $0] }
        .position(x: liveX + liveW / 2, y: liveY + liveH / 2)
        .zIndex(active ? 10 : 0)
    }
}

// Canvas livre: cada card tem posicao e tamanho proprios, em coordenadas
// absolutas do canvas. Um agente novo entra numa vaga arrumada; o que voce
// moveu ou redimensionou fica como deixou, inclusive depois de fechar o app.
final class AgentLayout: ObservableObject {
    static let shared = AgentLayout()
    // v3: o maestro entrou no canvas e as vagas mudaram de geometria; a chave
    // nova descarta posicoes salvas no esquema antigo, que ficariam sobrepostas
    // v4: cartoes de passo entraram no canvas e o maestro ganhou folga no topo;
    // a chave nova descarta posicoes salvas durante os testes da geometria antiga
    private static let key = "ui.agentBoxes.v4"

    struct Box: Equatable {
        var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    }

    static let defW: CGFloat = 340
    static let defH: CGFloat = 430
    static let minW: CGFloat = 260
    static let minH: CGFloat = 240
    static let maxW: CGFloat = 1100
    static let maxH: CGFloat = 1400
    private static let gap: CGFloat = 28
    private static let cols = 3

    // o maestro vive no mesmo canvas e tambem se move e redimensiona;
    // "@" nao e valido em nome de agente, entao a chave nunca colide
    static let maestroKey = "@maestro"
    // x = (1076 - 760) / 2: maestro centrado sobre o cluster de 3 colunas
    // y=560 pre-aloca folga ACIMA do maestro para arrastar cards para cima;
    // a visao abre centrada nele, entao a folga so aparece quando usada.
    // O cartao de passo ancora logo acima do topo dele.
    static let maestroDefault = Box(x: 158, y: 560, w: 760, h: 470)
    static let maestroMinW: CGFloat = 480
    static let maestroMinH: CGFloat = 300
    // as vagas dos agentes comecam abaixo do maestro, com folga para os cabos

    @Published private(set) var boxes: [String: Box] = [:]

    // deslocamento de origem das posicoes PADRAO: calculado a partir da largura
    // da janela para o arranjo inicial nascer centralizado. So afeta cards que
    // o usuario nunca moveu — posicao arrastada e absoluta e nao se mexe.
    @Published var originX: CGFloat = 0

    // zoom do canvas (estilo Figma): pinca no trackpad, ⌘− / ⌘= ou os botoes
    // do topo. Persistido entre sessoes.
    @Published var zoom: CGFloat = UserDefaults.standard.object(forKey: "ui.canvasZoom")
        .flatMap { $0 as? Double }.map { CGFloat($0) } ?? 1.0

    func setZoom(_ z: CGFloat) {
        zoom = min(2.0, max(0.3, z))
        UserDefaults.standard.set(Double(zoom), forKey: "ui.canvasZoom")
    }

    private init() {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [Double]]
        else { return }
        for (k, v) in raw where v.count == 4 {
            boxes[k] = Box(x: v[0], y: v[1], w: v[2], h: v[3])
        }
    }

    private func persist() {
        let raw = boxes.mapValues { [Double($0.x), Double($0.y), Double($0.w), Double($0.h)] }
        UserDefaults.standard.set(raw, forKey: Self.key)
    }

    // vaga natural: fileiras de 3 ALINHADAS sob a posicao ATUAL do maestro —
    // agente novo nasce arrumado embaixo dele, onde quer que ele esteja,
    // nunca em cima de outro card. Mover um card o torna absoluto (livre).
    func slot(_ index: Int) -> Box {
        let m = maestroBox
        let clusterW = CGFloat(Self.cols) * Self.defW + CGFloat(Self.cols - 1) * Self.gap
        let left = max(0, m.x + m.w / 2 - clusterW / 2)
        let col = index % Self.cols, row = index / Self.cols
        return Box(x: left + CGFloat(col) * (Self.defW + Self.gap),
                   y: m.y + m.h + 96 + CGFloat(row) * (Self.defH + Self.gap),
                   w: Self.defW, h: Self.defH)
    }

    var maestroBox: Box {
        if let b = boxes[Self.maestroKey] { return b }
        var d = Self.maestroDefault
        d.x += originX
        return d
    }

    func moveMaestro(by d: CGSize) {
        var b = maestroBox
        b.x = max(0, b.x + d.width)
        b.y = max(0, b.y + d.height)
        boxes[Self.maestroKey] = b
        persist()
    }

    func resizeMaestro(by d: CGSize) {
        var b = maestroBox
        b.w = min(Self.maxW, max(Self.maestroMinW, b.w + d.width))
        b.h = min(Self.maxH, max(Self.maestroMinH, b.h + d.height))
        boxes[Self.maestroKey] = b
        persist()
    }

    func box(_ name: String, index: Int) -> Box {
        boxes[name] ?? slot(index)
    }

    func move(_ name: String, index: Int, by d: CGSize) {
        var b = box(name, index: index)
        b.x = max(0, b.x + d.width)
        b.y = max(0, b.y + d.height)
        boxes[name] = b
        persist()
    }

    func resize(_ name: String, index: Int, by d: CGSize) {
        var b = box(name, index: index)
        b.w = min(Self.maxW, max(Self.minW, b.w + d.width))
        b.h = min(Self.maxH, max(Self.minH, b.h + d.height))
        boxes[name] = b
        persist()
    }

    func reset(_ name: String) {
        boxes.removeValue(forKey: name)
        persist()
    }

    func resetAll() {
        boxes = [:]
        persist()
    }

    var isCustomized: Bool { !boxes.isEmpty }

    // area total que o canvas precisa ter para caber tudo que foi arrastado
    func canvasSize(names: [String]) -> CGSize {
        let m = maestroBox
        var w: CGFloat = max(1140, m.x + m.w + 60)
        var h: CGFloat = max(560, m.y + m.h + 60)
        for (i, n) in names.enumerated() {
            let b = box(n, index: i)
            w = max(w, b.x + b.w + 60)
            h = max(h, b.y + b.h + 60)
        }
        return CGSize(width: w, height: h)
    }
}

struct AgentNode: View {
    @ObservedObject var orch: Orchestra
    let agent: AgentInfo
    let index: Int
    let onNotes: () -> Void
    let onDiff: () -> Void
    let onKill: () -> Void
    let onDone: () -> Void
    @State private var draft = ""
    @ObservedObject private var layout = AgentLayout.shared
    @State private var dragging = false
    @State private var resizing = false
    // ultimo translation visto: o gesto e comitado INCREMENTALMENTE a cada
    // frame (posicao ja salva em cada instante), entao nao existe "soltar e
    // voltar" — mesmo que um re-render mate o gesto, o card fica onde esta
    @State private var lastDrag: CGSize = .zero
    @State private var lastResize: CGSize = .zero

    private var box: AgentLayout.Box { layout.box(agent.name, index: index) }
    private var liveX: CGFloat { box.x }
    private var liveY: CGFloat { box.y }
    private var liveW: CGFloat { box.w }
    private var liveH: CGFloat { box.h }
    private var active: Bool { dragging || resizing }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                // punho de arrastar: so ele move o card, para nao roubar o
                // clique dos botoes nem a selecao de texto do terminal
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: Theme.uiSize(11), weight: .bold))
                    .foregroundColor(dragging ? Theme.accent : Theme.dim.opacity(0.55))
                    .padding(.horizontal, 3).padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .help("arraste para mover · duplo clique volta para o lugar original")
                    .onHover { $0 ? NSCursor.openHand.push() : NSCursor.pop() }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in
                                // divide pelo zoom: o card segue o cursor 1:1
                                // em qualquer escala do canvas
                                layout.move(agent.name, index: index, by: CGSize(
                                    width: (v.translation.width - lastDrag.width) / layout.zoom,
                                    height: (v.translation.height - lastDrag.height) / layout.zoom))
                                lastDrag = v.translation
                                dragging = true
                            }
                            .onEnded { _ in
                                lastDrag = .zero
                                dragging = false
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            layout.reset(agent.name)
                        }
                    }
                Circle().fill(agent.status.color).frame(width: 7, height: 7)
                Text(agent.name).font(.system(size: Theme.uiSize(12), weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Text(agent.status.label).font(.system(size: Theme.uiSize(9)))
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
                    .font(.system(size: Theme.uiSize(9), design: .monospaced))
                    .foregroundColor(Theme.dim)
                    .help("arquivos modificados no espaço isolado deste agente")
            }
            HStack(spacing: 5) {
                Text("\(agent.branch)  ·  \(agent.cli)\(agent.model.isEmpty ? "" : " · \(agent.model)")")
                    .font(.system(size: Theme.uiSize(9), design: .monospaced)).foregroundColor(Theme.dim)
                if !agent.parent.isEmpty {
                    Text("sub de \(agent.parent)")
                        .font(.system(size: Theme.uiSize(8), weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.accent.opacity(0.85))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.12)).cornerRadius(3)
                        .help("este agente foi criado por \(agent.parent), na camada \(agent.depth)")
                }
            }

            // O que ele foi contratado para fazer e onde esta — decidir aprovar
            // ou descartar nao pode exigir a leitura da tela do terminal.
            if !agent.task.isEmpty || !agent.progress.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if !agent.task.isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "target")
                                .font(.system(size: Theme.uiSize(8)))
                                .foregroundColor(Theme.dim)
                                .padding(.top, 1)
                            Text(agent.task)
                                .font(.system(size: Theme.uiSize(10)))
                                .foregroundColor(Theme.text.opacity(0.85))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !agent.progress.isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: Theme.uiSize(8)))
                                .foregroundColor(agent.status.color)
                                .padding(.top, 1)
                            Text(agent.progress)
                                .font(.system(size: Theme.uiSize(10)))
                                .foregroundColor(Theme.dim)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .cornerRadius(5)
                .help("o alvo é a tarefa que você pediu; a seta é a última anotação de progresso do agente")
            }

            // o terminal absorve o espaco extra: aumentar o card mostra mais tela
            TerminalText(content: agent.pane)
                .frame(minHeight: 70, maxHeight: .infinity)
            TerminalKeys(window: agent.name, pane: agent.pane, orch: orch)
            PromptField(placeholder: "mandar instrução para \(agent.name)…",
                        text: $draft, historyKey: "agent") { t in
                orch.sendAgent(agent.name, t)
            }
            if agent.status == .aguardando {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard").font(.system(size: Theme.uiSize(9)))
                        .foregroundColor(AgentStatus.aguardando.color)
                    Text("plano pronto — revise antes de liberar")
                        .font(.system(size: Theme.uiSize(9))).foregroundColor(Theme.dim)
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
                            help: "aplica o trabalho no projeto (merge): abre o diff aqui mesmo e pede o nome do agente para confirmar",
                            action: onDone)
                SmallButton(label: "descartar", icon: "xmark",
                            tint: AgentStatus.bloqueado.color,
                            help: "encerra o agente sem aplicar nada. O trabalho fica guardado numa branch, dá pra recuperar",
                            action: onKill)
            }
        }
        .padding(12)
        .frame(width: liveW, height: liveH, alignment: .topLeading)
        .background(Theme.card)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(active ? Theme.accent.opacity(0.55) : Theme.cardBorder, lineWidth: 1))
        // punho de redimensionar, no canto inferior direito
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: Theme.uiSize(8), weight: .bold))
                .foregroundColor(resizing ? Theme.accent : Theme.dim.opacity(0.5))
                .padding(6)
                .contentShape(Rectangle())
                .help("arraste para redimensionar este card")
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            layout.resize(agent.name, index: index, by: CGSize(
                                width: (v.translation.width - lastResize.width) / layout.zoom,
                                height: (v.translation.height - lastResize.height) / layout.zoom))
                            lastResize = v.translation
                            resizing = true
                        }
                        .onEnded { _ in
                            lastResize = .zero
                            resizing = false
                        }
                )
        }
        .shadow(color: .black.opacity(active ? 0.5 : 0), radius: active ? 16 : 0)
        // a ancora vem ANTES do .position: assim ela pertence ao card (nao ao
        // involucro que preenche o canvas) e resolve na posicao real dele,
        // acompanhando o arraste frame a frame
        .anchorPreference(key: NodeAnchors.self, value: .top) { ["agent-\(agent.name)": $0] }
        .position(x: liveX + liveW / 2, y: liveY + liveH / 2)
        .zIndex(active ? 10 : 0)
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

// Arvore de arquivos estilo IDE: pasta expande PARA BAIXO, no lugar, com
// recuo por nivel — nada de navegar para dentro e perder a visao do resto.
struct FileBrowser: View {
    let orch: Orchestra
    let onOpen: (String) -> Void
    @State private var source = ""            // "" = projeto base; senao nome do agente
    @State private var expanded: Set<String> = []  // caminhos de pastas abertas
    @State private var selected: String?

    private struct Row: Identifiable {
        let entry: FileEntry
        let depth: Int
        var id: String { entry.path }
    }

    var root: String? {
        guard let repo = orch.repo, let proj = orch.project else { return nil }
        return source.isEmpty ? repo : "\(ORQ)/worktrees/\(proj)/\(source)"
    }

    private func entries(of dir: String) -> [FileEntry] {
        let skip: Set<String> = ["node_modules", ".git", ".claude", "__pycache__",
                                 ".venv", "dist", "build", ".next", "target"]
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

    // achata a arvore: pastas expandidas contribuem seus filhos logo abaixo,
    // com profundidade +1 (limite de 12 niveis contra ciclos de symlink)
    private func rows() -> [Row] {
        guard let r = root else { return [] }
        var out: [Row] = []
        func walk(_ dir: String, depth: Int) {
            guard depth < 12 else { return }
            for e in entries(of: dir) {
                out.append(Row(entry: e, depth: depth))
                if e.isDir && expanded.contains(e.path) {
                    walk(e.path, depth: depth + 1)
                }
            }
        }
        walk(r, depth: 0)
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $source) {
                Text("projeto").tag("")
                ForEach(orch.agents) { a in Text(a.name).tag(a.name) }
            }
            .pickerStyle(.menu)
            .font(.system(size: Theme.uiSize(10)))
            .onChange(of: source) { _ in expanded = []; selected = nil }
            .help("de quem são os arquivos: o projeto original ou a cópia de trabalho de um agente")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows()) { row in
                        let e = row.entry
                        Button {
                            if e.isDir {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    if expanded.contains(e.path) {
                                        // fecha a pasta e tudo que esta dentro dela
                                        expanded = expanded.filter { !$0.hasPrefix(e.path) }
                                    } else {
                                        expanded.insert(e.path)
                                    }
                                }
                            } else {
                                selected = e.path
                                onOpen(e.path)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if e.isDir {
                                    Image(systemName: expanded.contains(e.path)
                                          ? "chevron.down" : "chevron.right")
                                        .font(.system(size: Theme.uiSize(7), weight: .semibold))
                                        .foregroundColor(Theme.dim)
                                        .frame(width: 10)
                                    Image(systemName: expanded.contains(e.path)
                                          ? "folder.fill" : "folder")
                                        .font(.system(size: Theme.uiSize(9)))
                                        .foregroundColor(Theme.accent.opacity(0.7))
                                } else {
                                    Spacer().frame(width: 10)
                                    Image(systemName: "doc.text")
                                        .font(.system(size: Theme.uiSize(9)))
                                        .foregroundColor(Theme.dim)
                                }
                                Text(e.name)
                                    .font(.system(size: Theme.uiSize(10.5), design: .monospaced))
                                    .foregroundColor(selected == e.path
                                                     ? Theme.accent : Theme.text.opacity(0.9))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if !e.isDir && e.mtime > Date().addingTimeInterval(-900) {
                                    Circle().fill(AgentStatus.concluido.color)
                                        .frame(width: 5, height: 5)
                                        .help("modificado há pouco")
                                }
                            }
                            .padding(.leading, 6 + CGFloat(row.depth) * 12)
                            .padding(.trailing, 6)
                            .padding(.vertical, 2.5)
                            .background(selected == e.path
                                        ? Theme.accent.opacity(0.08) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(e.isDir ? "clique para abrir a pasta aqui mesmo" : e.path)
                    }
                }
            }
            Text("● verde = mexido nos últimos 15 min")
                .font(.system(size: Theme.uiSize(8))).foregroundColor(Theme.dim)
        }
        .padding(10)
        .frame(width: 230)
        .background(Theme.card.opacity(0.6))
    }
}

struct FileViewer: View {
    let path: String
    let onClose: () -> Void

    // Um projeto tem logo, icone, screenshot. Mostrar "(arquivo binario)" para
    // um PNG e desistir cedo demais: o AppKit abre esses formatos sozinho.
    private var isImage: Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp",
                "icns", "ico", "pdf", "svg"].contains(ext)
    }

    private var image: NSImage? { isImage ? NSImage(contentsOfFile: path) : nil }

    private var fileSize: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let b = attrs?[.size] as? Int else { return "" }
        return b < 1024 ? "\(b) B"
             : b < 1024 * 1024 ? "\(b / 1024) KB"
             : String(format: "%.1f MB", Double(b) / 1024 / 1024)
    }

    var content: String {
        guard let data = FileManager.default.contents(atPath: path) else { return "(não consegui ler)" }
        if data.count > 300_000 { return "(arquivo grande demais para visualizar — \(data.count / 1024) KB)" }
        return String(data: data, encoding: .utf8) ?? "(arquivo binário — sem pré-visualização para este formato)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: image != nil ? "photo" : "doc.text")
                    .font(.system(size: Theme.uiSize(10))).foregroundColor(Theme.accent)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: Theme.uiSize(11), weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text).lineLimit(1)
                Spacer()
                SmallButton(label: "fechar", icon: "xmark", action: onClose)
            }
            Text(path.replacingOccurrences(of: HOME, with: "~"))
                .font(.system(size: Theme.uiSize(8), design: .monospaced)).foregroundColor(Theme.dim).lineLimit(1)

            if let img = image {
                VStack(spacing: 6) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 420)
                            // xadrez por baixo: sem ele, um PNG transparente
                            // some no fundo escuro e parece que nao carregou
                            .background(TransparencyChecker())
                            .padding(8)
                    }
                    HStack(spacing: 8) {
                        Text("\(Int(img.size.width))×\(Int(img.size.height)) px")
                        Text("·")
                        Text(fileSize)
                        Spacer()
                        Button("abrir no Preview") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                            .buttonStyle(.plain).foregroundColor(Theme.accent)
                    }
                    .font(.system(size: Theme.uiSize(9), design: .monospaced))
                    .foregroundColor(Theme.dim)
                }
                .frame(maxWidth: .infinity)
                .background(Theme.terminalBg)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
            } else {
                TerminalText(content: content, size: 11)
            }
        }
        .padding(10)
        .frame(width: 440)
        .background(Theme.card.opacity(0.6))
    }
}

// MARK: - Ajustes

// Configurar nao pode exigir abrir arquivo nem decorar nome de variavel: cada
// limite aparece com o valor, a faixa aceita e o motivo de existir, ao lado do
// efeito pratico de mexer nele.
struct AjustesView: View {
    @ObservedObject var orch: Orchestra
    @ObservedObject private var scale = UIScale.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {

                secao("Limites da equipe",
                      "Valem para você e para os agentes: quando um deles tenta criar um subagente além do limite, o nvo recusa e explica o motivo.") {
                    VStack(spacing: 14) {
                        ForEach(orch.limites) { l in
                            LimiteRow(limite: l) { novo in orch.setLimite(l.key, novo) }
                        }
                        if orch.limites.isEmpty {
                            Text("carregando…").font(.system(size: Theme.uiSize(10)))
                                .foregroundColor(Theme.dim)
                        }
                    }
                }

                secao("Quem executa os agentes",
                      "Cada agente roda numa CLI. As que faltam aparecem com o comando de instalação — depois de instalar, volte aqui e recarregue.") {
                    VStack(spacing: 8) {
                        ForEach(orch.harnesses) { h in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: h.installed ? "checkmark.circle.fill" : "circle.dashed")
                                    .font(.system(size: Theme.uiSize(12)))
                                    .foregroundColor(h.installed ? Theme.accent : Theme.dim.opacity(0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.label)
                                        .font(.system(size: Theme.uiSize(11), weight: .semibold))
                                        .foregroundColor(h.installed ? Theme.text : Theme.dim)
                                    if h.installed {
                                        Text("modelos: \(h.models.joined(separator: ", "))")
                                            .font(.system(size: Theme.uiSize(9), design: .monospaced))
                                            .foregroundColor(Theme.dim)
                                    } else {
                                        Text(h.install)
                                            .font(.system(size: Theme.uiSize(9), design: .monospaced))
                                            .foregroundColor(Theme.dim.opacity(0.85))
                                            .textSelection(.enabled)
                                    }
                                }
                                Spacer()
                                if !h.installed {
                                    // um clique abre o Terminal ja com o comando rodando;
                                    // depois e so voltar e recarregar
                                    SmallButton(label: "instalar", icon: "arrow.down.circle",
                                                tint: Theme.accent,
                                                help: "abre o Terminal e roda: \(h.install). Depois de terminar (e fazer login, se a CLI pedir), volte e clique em recarregar") {
                                        if let erro = openTerminal(h.install) { orch.lastError = erro }
                                    }
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.035))
                            .cornerRadius(6)
                        }
                        HStack(spacing: 8) {
                            SmallButton(label: "recarregar", icon: "arrow.clockwise",
                                        help: "relê o registro e verifica de novo o que está instalado") {
                                orch.refreshHarnesses()
                                orch.refreshConfig()
                            }
                            SmallButton(label: "abrir harnesses.conf", icon: "doc.text",
                                        help: "adicione a sua própria CLI — é um arquivo de texto, sem recompilar nada") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "\(ORQ)/bin/harnesses.conf"))
                            }
                            Spacer()
                        }
                    }
                }

                secao("Avisos e autonomia",
                      "Como o orquestra chama a sua atenção — e o quanto ele decide sozinho.") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                Toggle(isOn: Binding(get: { orch.soundOn }, set: { orch.soundOn = $0 })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("aviso sonoro").font(.system(size: Theme.uiSize(11), weight: .semibold))
                                            .foregroundColor(Theme.text)
                                        Text("um toque bem suave quando o maestro ou um agente fica esperando a sua resposta — só na hora em que a pergunta aparece, nunca repetido")
                                            .font(.system(size: Theme.uiSize(9))).foregroundColor(Theme.dim)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                Spacer()
                                SmallButton(label: "ouvir", icon: "speaker.wave.1",
                                            help: "toca o aviso uma vez, no volume escolhido") {
                                    Orchestra.somSuave(volume: orch.somVolume)
                                }
                            }
                            if orch.soundOn {
                                HStack(spacing: 8) {
                                    Image(systemName: "speaker.fill")
                                        .font(.system(size: Theme.uiSize(8))).foregroundColor(Theme.dim)
                                    // soltou o dedo, ouve na hora como ficou
                                    Slider(value: Binding(get: { orch.somVolume },
                                                          set: { orch.somVolume = $0 }),
                                           in: 0.1...1.0) { arrastando in
                                        if !arrastando { Orchestra.somSuave(volume: orch.somVolume) }
                                    }
                                    .frame(maxWidth: 220)
                                    Image(systemName: "speaker.wave.3.fill")
                                        .font(.system(size: Theme.uiSize(8))).foregroundColor(Theme.dim)
                                    Text("\(Int((orch.somVolume * 100).rounded()))%")
                                        .font(.system(size: Theme.uiSize(9), design: .monospaced))
                                        .foregroundColor(Theme.dim)
                                        .frame(minWidth: Theme.uiSize(30), alignment: .trailing)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.white.opacity(0.035)).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))

                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(get: { orch.autoYes }, set: { orch.autoYes = $0 })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("modo liberdade — concordar com tudo")
                                        .font(.system(size: Theme.uiSize(11), weight: .semibold))
                                        .foregroundColor(Theme.text)
                                    Text("quando um agente pedir permissão, o orquestra responde “sim” sozinho, para todos. O firewall (guard.sh) continua bloqueando comandos destrutivos, e aplicar trabalho no projeto continua exigindo a sua confirmação digitada.")
                                        .font(.system(size: Theme.uiSize(9))).foregroundColor(Theme.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.checkbox)
                            if orch.autoYes {
                                HStack(spacing: 5) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: Theme.uiSize(9)))
                                        .foregroundColor(Theme.accent)
                                    Text("ativo — os agentes estão com carta branca; acompanhe pelas notas e pelo diff antes de aprovar")
                                        .font(.system(size: Theme.uiSize(9)))
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(orch.autoYes ? Theme.accent.opacity(0.06) : Color.white.opacity(0.035))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(orch.autoYes ? Theme.accent.opacity(0.4) : Theme.cardBorder))
                    }
                }

                secao("Aparência",
                      "O zoom vale para toda a interface e fica salvo entre sessões.") {
                    HStack(spacing: 10) {
                        SmallButton(label: "menor", icon: "textformat.size.smaller") { scale.zoomOut() }
                        Text(scale.label)
                            .font(.system(size: Theme.uiSize(12), design: .monospaced))
                            .foregroundColor(Theme.text).frame(minWidth: Theme.uiSize(52))
                        SmallButton(label: "maior", icon: "textformat.size.larger") { scale.zoomIn() }
                        SmallButton(label: "padrão", icon: "arrow.uturn.backward") { scale.reset() }
                        Spacer()
                        Text("⌘+ · ⌘− · ⌘0")
                            .font(.system(size: Theme.uiSize(9), design: .monospaced))
                            .foregroundColor(Theme.dim)
                    }
                }

                // assinatura da marca, como no topo do painel
                HStack {
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(string:
                            "https://nevoaai.com/?utm_source=orquestra&utm_medium=app_ajustes&utm_campaign=opensource_orchestrator")!)
                    } label: {
                        Text("powered by nevoaai.com")
                            .font(.system(size: Theme.uiSize(9), weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.nevoa.opacity(0.9))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(Capsule().stroke(Theme.nevoa.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .onAppear { orch.refreshConfig(); orch.refreshHarnesses() }
    }

    @ViewBuilder
    private func secao<C: View>(_ titulo: String, _ subtitulo: String,
                                @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo).font(.system(size: Theme.uiSize(13), weight: .bold))
                .foregroundColor(Theme.text)
            Text(subtitulo).font(.system(size: Theme.uiSize(10)))
                .foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            conteudo()
        }
    }
}

struct LimiteRow: View {
    let limite: Limite
    let onChange: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(limite.label)
                    .font(.system(size: Theme.uiSize(11), weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(limite.help)
                    .font(.system(size: Theme.uiSize(9)))
                    .foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    passo("minus", ativo: limite.value > limite.min) {
                        onChange(limite.value - 1)
                    }
                    Text("\(limite.value)")
                        .font(.system(size: Theme.uiSize(15), weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                        .frame(minWidth: Theme.uiSize(28))
                    passo("plus", ativo: limite.value < limite.max) {
                        onChange(limite.value + 1)
                    }
                }
                Text("\(limite.min)–\(limite.max)")
                    .font(.system(size: Theme.uiSize(8), design: .monospaced))
                    .foregroundColor(Theme.dim.opacity(0.7))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.035))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
    }

    private func passo(_ icone: String, ativo: Bool, _ acao: @escaping () -> Void) -> some View {
        Button(action: { if ativo { acao() } }) {
            Image(systemName: icone)
                .font(.system(size: Theme.uiSize(10), weight: .bold))
                .foregroundColor(ativo ? Theme.text : Theme.dim.opacity(0.3))
                .frame(width: Theme.uiSize(22), height: Theme.uiSize(20))
                .background(Color.white.opacity(ativo ? 0.07 : 0.02))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
    }
}

// Xadrez cinza classico para indicar transparencia atras da imagem.
struct TransparencyChecker: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            for row in 0..<Int(ceil(size.height / s)) {
                for col in 0..<Int(ceil(size.width / s)) {
                    guard (row + col).isMultiple(of: 2) else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(col) * s, y: CGFloat(row) * s,
                                         width: s, height: s)),
                             with: .color(.white.opacity(0.05)))
                }
            }
        }
    }
}

// MARK: - Sheets

struct SheetTarget: Identifiable {
    enum Kind { case notes, diff, kill, done, stop }
    let id = UUID()
    let name: String
    let kind: Kind
}

// Aprovar sem sair do app: o diff na tela e o nome digitado logo abaixo dele.
// Nenhum merge acontece por um clique so — a regra 6 do SPEC continua valendo,
// muda apenas o lugar onde o humano confirma.
struct DoneSheet: View {
    let name: String
    let orch: Orchestra
    @Environment(\.dismiss) var dismiss
    @State private var diff = "carregando o diff…"
    @State private var confirm = ""
    @State private var error: String?
    @State private var merging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.seal").foregroundColor(AgentStatus.concluido.color)
                Text("Aprovar o trabalho de \(name)")
                    .font(.system(size: Theme.uiSize(13), weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Spacer()
                SmallButton(label: "fechar", icon: "xmark") { dismiss() }
            }
            Text("Revise as mudanças abaixo. Aplicar faz merge --no-ff de agent/\(name) e remove o worktree; as notas ficam guardadas.")
                .font(.system(size: Theme.uiSize(10))).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            TerminalText(content: diff, size: 10.5)

            HStack(spacing: 8) {
                Text("digite \(name) para confirmar:")
                    .font(.system(size: Theme.uiSize(10), design: .monospaced))
                    .foregroundColor(Theme.dim)
                TextField(name, text: $confirm)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: Theme.uiSize(12), design: .monospaced))
                    .frame(width: 160)
                    .disabled(merging)
                    .onSubmit { aplicar() }
            }
            if let e = error {
                Text(e).font(.system(size: Theme.uiSize(10), design: .monospaced))
                    .foregroundColor(AgentStatus.bloqueado.color)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                SmallButton(label: "cancelar") { dismiss() }
                SmallButton(label: merging ? "aplicando…" : "aplicar no projeto",
                            icon: "checkmark.seal",
                            tint: confirm == name ? AgentStatus.concluido.color : Theme.dim,
                            help: confirm == name
                                ? "faz o merge de agent/\(name)"
                                : "digite \(name) no campo acima para liberar",
                            action: aplicar)
            }
        }
        .padding(18)
        .frame(width: 720, height: 560)
        .background(Theme.bg)
        .onAppear { orch.diff(name) { diff = $0 } }
    }

    private func aplicar() {
        guard !merging else { return }
        guard confirm == name else {
            error = confirm.isEmpty
                ? "digite \(name) no campo acima para confirmar."
                : "o nome não confere — digite exatamente: \(name)"
            return
        }
        error = nil
        merging = true
        orch.doneAgent(name, confirm: confirm) { err in
            merging = false
            if let err = err { error = err } else { dismiss() }
        }
    }
}

// Encerrar a sessao para trocar de contexto sem perder trabalho.
struct StopSheet: View {
    let orch: Orchestra
    @Environment(\.dismiss) var dismiss
    @State private var keepProject = true
    @State private var error: String?
    @State private var stopping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encerrar a sessão").font(.system(size: Theme.uiSize(13), weight: .bold))
                .foregroundColor(Theme.text)
            Text("Desliga o maestro e todos os agentes. Worktrees, branches e notas ficam intactos — religando os agentes, o trabalho continua de onde parou.")
                .font(.system(size: Theme.uiSize(11))).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $keepProject) {
                Text("manter \(orch.project ?? "o projeto") registrado")
                    .font(.system(size: Theme.uiSize(11)))
                    .foregroundColor(Theme.text)
            }
            .toggleStyle(.checkbox)
            Text(keepProject
                 ? "Ao reabrir, você volta para este mesmo projeto."
                 : "O projeto será desregistrado e o app abre pedindo um novo.")
                .font(.system(size: Theme.uiSize(10))).foregroundColor(Theme.dim)
            if let e = error {
                Text(e).font(.system(size: Theme.uiSize(10), design: .monospaced))
                    .foregroundColor(AgentStatus.bloqueado.color)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                SmallButton(label: "cancelar") { dismiss() }
                SmallButton(label: stopping ? "encerrando…" : "encerrar sessão",
                            icon: "stop.circle", tint: AgentStatus.bloqueado.color) {
                    guard !stopping else { return }
                    stopping = true
                    orch.stopSession(keepProject: keepProject) { err in
                        stopping = false
                        if let err = err { error = err } else { dismiss() }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(Theme.bg)
    }
}

struct TextSheet: View {
    let title: String
    let content: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: Theme.uiSize(13), weight: .bold, design: .monospaced))
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
            Text("Encerrar agente sem merge").font(.system(size: Theme.uiSize(13), weight: .bold))
                .foregroundColor(Theme.text)
            Text("Remove a janela e o worktree de \"\(name)\". A branch agent/\(name) fica preservada. Digite o nome para confirmar:")
                .font(.system(size: Theme.uiSize(11))).foregroundColor(Theme.dim)
            TextField(name, text: $confirm)
                .textFieldStyle(.roundedBorder).font(.system(size: Theme.uiSize(12), design: .monospaced))
            if let e = error {
                Text(e).font(.system(size: Theme.uiSize(10))).foregroundColor(AgentStatus.bloqueado.color)
            }
            HStack {
                Spacer()
                SmallButton(label: "cancelar") { dismiss() }
                SmallButton(label: "encerrar", icon: "xmark",
                            tint: confirm == name ? AgentStatus.bloqueado.color : Theme.dim,
                            help: confirm == name
                                ? "encerra o agente \(name)"
                                : "digite \(name) no campo acima para liberar") {
                    // antes o clique com o nome errado nao fazia nada e nao
                    // explicava nada — parecia botao quebrado
                    guard confirm == name else {
                        error = confirm.isEmpty
                            ? "digite \(name) no campo acima para confirmar."
                            : "o nome não confere — digite exatamente: \(name)"
                        return
                    }
                    error = nil
                    orch.killAgent(name) { err in
                        if let err = err {
                            error = err.isEmpty ? "o nvo falhou ao encerrar o agente." : err
                        } else { dismiss() }
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
            Text("Novo agente").font(.system(size: Theme.uiSize(13), weight: .bold)).foregroundColor(Theme.text)
            // Sem isto nao dava para saber onde o agente ia parar: ele entra
            // sempre no projeto ativo, ao lado dos que ja estao no painel.
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: Theme.uiSize(9))).foregroundColor(Theme.accent)
                Text("entra no projeto **\(orch.project ?? "—")**, junto dos agentes que já estão no painel")
                    .font(.system(size: Theme.uiSize(10))).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .cornerRadius(5)
            .help("para trabalhar em outro repositório, use “projeto” na barra de cima")

            TextField("nome (ex: builder)", text: $name)
                .textFieldStyle(.roundedBorder).font(.system(size: Theme.uiSize(12), design: .monospaced))
            // Escolha do harness. Mostramos tambem os que faltam, com o comando
            // de instalacao: saber que a opcao existe vale mais do que uma lista
            // curta que finge que so ha uma escolha.
            VStack(alignment: .leading, spacing: 5) {
                Text("quem vai executar")
                    .font(.system(size: Theme.uiSize(10), weight: .semibold)).foregroundColor(Theme.dim)
                ForEach(orch.harnesses) { h in
                    Button {
                        guard h.installed else { return }
                        cli = h.id
                        model = ""
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: cli == h.id ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: Theme.uiSize(11)))
                                .foregroundColor(h.installed ? (cli == h.id ? Theme.accent : Theme.dim)
                                                             : Theme.dim.opacity(0.4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.label)
                                    .font(.system(size: Theme.uiSize(11),
                                                  weight: cli == h.id ? .semibold : .regular))
                                    .foregroundColor(h.installed ? Theme.text : Theme.dim.opacity(0.6))
                                if !h.installed {
                                    Text("não instalado · \(h.install)")
                                        .font(.system(size: Theme.uiSize(9), design: .monospaced))
                                        .foregroundColor(Theme.dim.opacity(0.7))
                                        .textSelection(.enabled)
                                }
                            }
                            Spacer()
                            if !h.installed {
                                SmallButton(label: "instalar", icon: "arrow.down.circle",
                                            help: "abre o Terminal e roda o comando de instalação") {
                                    if let erro = openTerminal(h.install) { orch.lastError = erro }
                                }
                            }
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(cli == h.id ? Theme.accent.opacity(0.10) : .clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!h.installed)
                    .help(h.installed ? "usar \(h.label) neste agente"
                                      : "instale com: \(h.install)")
                }
            }

            // modelos do harness escolhido, direto do registro
            if let atual = orch.harnesses.first(where: { $0.id == cli }), !atual.models.isEmpty {
                Picker("", selection: $model) {
                    Text("modelo padrão").tag("")
                    ForEach(atual.models, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                if cli == "claude" {
                    Text("dica: Sonnet resolve a maioria das tarefas de builder por ~40% do custo do Opus")
                        .font(.system(size: Theme.uiSize(9))).foregroundColor(Theme.dim)
                }
            }
            Toggle(isOn: $planFirst) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("pedir plano antes de executar").font(.system(size: Theme.uiSize(11)))
                        .foregroundColor(Theme.text)
                    Text("o agente escreve o que pretende fazer e espera sua aprovação — evita gastar token no caminho errado")
                        .font(.system(size: Theme.uiSize(9))).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Text("Tarefa (seja específico: arquivo, critério de pronto, o que NÃO fazer)")
                .font(.system(size: Theme.uiSize(10))).foregroundColor(Theme.dim)
            TextEditor(text: $task)
                .font(.system(size: Theme.uiSize(12), design: .monospaced))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.terminalBg).cornerRadius(6)
            if let e = error {
                Text(e).font(.system(size: Theme.uiSize(10))).foregroundColor(AgentStatus.bloqueado.color)
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
            Text("Escolher projeto").font(.system(size: Theme.uiSize(13), weight: .bold)).foregroundColor(Theme.text)
            Picker("", selection: $mode) {
                Text("pasta local").tag(0)
                Text("GitHub").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in error = nil; offerGitInit = false }
            if mode == 1 {
                Text("Cola a URL do repositório ou só usuario/repo. Ele clona para ~/orquestra/repos e registra (repos privados usam sua credencial git já configurada).")
                    .font(.system(size: Theme.uiSize(11))).foregroundColor(Theme.dim)
                TextField("ex: nevoa-ai/busca-cnpj ou https://github.com/…", text: $gitUrl)
                    .textFieldStyle(.roundedBorder).font(.system(size: Theme.uiSize(12), design: .monospaced))
                if let e = error {
                    Text(e).font(.system(size: Theme.uiSize(10))).foregroundColor(AgentStatus.bloqueado.color)
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
                .font(.system(size: Theme.uiSize(11))).foregroundColor(Theme.dim)
            HStack {
                TextField("~/meus-projetos/minha-api", text: $path)
                    .textFieldStyle(.roundedBorder).font(.system(size: Theme.uiSize(12), design: .monospaced))
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
                Text(e).font(.system(size: Theme.uiSize(10))).foregroundColor(AgentStatus.bloqueado.color)
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
            Image(systemName: icon).font(.system(size: Theme.uiSize(12))).foregroundColor(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: Theme.uiSize(11), weight: .bold)).foregroundColor(Theme.text)
                Text(text).font(.system(size: Theme.uiSize(10.5))).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                    Text("O FLUXO").font(.system(size: Theme.uiSize(9), weight: .black)).foregroundColor(Theme.accent)
                    row("folder", "1 · Escolha o projeto",
                        "Pasta local ou repositório do GitHub. Cada agente trabalha numa cópia isolada — nada muda no seu projeto sem sua aprovação.")
                    row("play.fill", "2 · Inicie o maestro",
                        "Ele abre já dentro do seu projeto, sabendo que é um orquestrador. Fale em português: “cria um builder pra fazer X e um reviewer pra auditar”.")
                    row("person.3.fill", "3 · Acompanhe os agentes",
                        "Cada card mostra a tela ao vivo. Você recebe notificação do macOS quando alguém termina ou trava.")
                    row("checkmark.seal", "4 · Revise e aprove",
                        "Terminou? Clique em diff pra ver o trabalho e em aprovar pra aplicar no projeto. A confirmação final é digitada no Terminal — merge nunca é automático.")

                    Divider().background(Theme.cardBorder)
                    Text("OS STATUS").font(.system(size: Theme.uiSize(9), weight: .black)).foregroundColor(Theme.accent)
                    row("circle.fill", "cinza — trabalhando", "o agente está executando a tarefa", tint: Theme.dim)
                    row("circle.fill", "azul — plano aguardando", "ele escreveu o plano e parou; leia e clique em aprovar plano", tint: AgentStatus.aguardando.color)
                    row("circle.fill", "verde — concluído", "hora de revisar o diff e aprovar", tint: AgentStatus.concluido.color)
                    row("circle.fill", "vermelho — bloqueado", "o agente precisa de você; leia as notas dele", tint: AgentStatus.bloqueado.color)

                    Divider().background(Theme.cardBorder)
                    Text("BOM SABER").font(.system(size: Theme.uiSize(9), weight: .black)).foregroundColor(Theme.accent)
                    row("arrow.up.and.down.and.arrow.left.and.right", "Organizar o canvas",
                        "Arraste um card pelo punho ≡ do canto superior esquerdo para movê-lo, e pelo canto inferior direito para redimensionar — o card maior mostra mais do terminal, e os cabos acompanham. Duplo clique no punho devolve um card ao lugar; “realinhar” no topo devolve todos. As posições ficam salvas.")
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
                    Text("DÚVIDAS FREQUENTES").font(.system(size: Theme.uiSize(9), weight: .black)).foregroundColor(Theme.accent)
                    row("questionmark.circle", "O maestro pode estragar meu projeto?",
                        "Não. Cada agente trabalha numa cópia isolada (git worktree). Seu projeto original só muda quando você clica em aprovar e confirma no Terminal.")
                    row("questionmark.circle", "Fechei o app — perdi tudo?",
                        "Não. Os agentes continuam rodando no tmux em segundo plano. Reabra o app e está tudo lá.")
                    row("questionmark.circle", "Um agente travou, e agora?",
                        "Leia as notas dele (botão notas), destrave mandando uma instrução no campo do card — ou descarte e crie outro com uma tarefa mais específica.")
                    row("questionmark.circle", "Preciso saber git ou terminal?",
                        "Quase nada: o único momento de terminal é a confirmação do aprovar, que já abre pronto — você só digita o nome do agente.")

                    Divider().background(Theme.cardBorder)
                    Text("SOBRE").font(.system(size: Theme.uiSize(9), weight: .black)).foregroundColor(Theme.accent)
                    row("circle.hexagongrid.fill", "Orquestra",
                        "Orquestrador local de agentes de código (Claude Code e Codex). Open source, licença MIT — github.com/rodrigolinss/orquestra")
                    HStack {
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(URL(string:
                                "https://nevoaai.com/?utm_source=orquestra&utm_medium=about_tab&utm_campaign=opensource_orchestrator")!)
                        } label: {
                            Text("powered by nevoaai.com")
                                .font(.system(size: Theme.uiSize(10), weight: .medium, design: .monospaced))
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
    @State private var tab: Aba = .painel
    @State private var pinchBase: CGFloat = 0
    @State private var centerTick = 0
    @ObservedObject private var scale = UIScale.shared
    @ObservedObject private var layout = AgentLayout.shared

    var body: some View {
        VStack(spacing: 0) {
            // barra superior
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill").foregroundColor(Theme.accent)
                Text("orquestra").font(.system(size: Theme.uiSize(14), weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Button {
                    NSWorkspace.shared.open(URL(string:
                        "https://nevoaai.com/?utm_source=orquestra&utm_medium=app_badge&utm_campaign=opensource_orchestrator")!)
                } label: {
                    Text("powered by nevoaai.com")
                        .font(.system(size: Theme.uiSize(9), weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.nevoa.opacity(0.9))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Theme.nevoa.opacity(0.35), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                // abas: painel | ajustes | ajuda · sobre
                HStack(spacing: 2) {
                    ForEach(Aba.allCases) { a in
                        Button { tab = a } label: {
                            Text(a.titulo)
                                .font(.system(size: Theme.uiSize(10), weight: tab == a ? .semibold : .regular))
                                .foregroundColor(tab == a ? Theme.text : Theme.dim)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(tab == a ? Color.white.opacity(0.08) : .clear)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 8)
                if let repo = orch.repo {
                    Text(repo).font(.system(size: Theme.uiSize(10), design: .monospaced))
                        .foregroundColor(Theme.dim).lineLimit(1)
                }
                Spacer()
                // liberdade ligada tem que ficar a vista o tempo todo: e o modo
                // em que os agentes decidem sozinhos
                if orch.autoYes {
                    Button { tab = .ajustes } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").font(.system(size: Theme.uiSize(8)))
                            Text("liberdade").font(.system(size: Theme.uiSize(9), weight: .semibold))
                        }
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.accent).cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("modo liberdade ativo: os agentes recebem “sim” automático. Clique para ajustar.")
                }
                // zoom da interface — tipografia pequena era reclamacao legitima
                HStack(spacing: 2) {
                    Button(action: { scale.zoomOut() }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: Theme.uiSize(11)))
                            .foregroundColor(scale.canZoomOut ? Theme.dim : Theme.dim.opacity(0.3))
                    }
                    .buttonStyle(.plain).disabled(!scale.canZoomOut)
                    .help("diminuir o texto (⌘−)")

                    Button(action: { scale.reset() }) {
                        Text(scale.label)
                            .font(.system(size: Theme.uiSize(9), design: .monospaced))
                            .foregroundColor(Theme.dim)
                            .frame(minWidth: Theme.uiSize(30))
                    }
                    .buttonStyle(.plain)
                    .help("voltar ao tamanho padrão (⌘0)")

                    Button(action: { scale.zoomIn() }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: Theme.uiSize(11)))
                            .foregroundColor(scale.canZoomIn ? Theme.dim : Theme.dim.opacity(0.3))
                    }
                    .buttonStyle(.plain).disabled(!scale.canZoomIn)
                    .help("aumentar o texto (⌘+)")
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .cornerRadius(5)

                if tab == .painel {
                    // zoom do canvas: − / % / +  (⌘− e ⌘= no teclado, pinça no trackpad)
                    HStack(spacing: 2) {
                        Button { layout.setZoom(layout.zoom - 0.1) } label: {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.system(size: Theme.uiSize(9)))
                                .foregroundColor(Theme.dim)
                                .padding(.horizontal, 5).padding(.vertical, 4)
                                .background(Color.white.opacity(0.06)).cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("-", modifiers: .command)
                        .help("afastar o canvas (⌘−)")
                        Button { layout.setZoom(1.0) } label: {
                            Text("\(Int(layout.zoom * 100))%")
                                .font(.system(size: Theme.uiSize(9), design: .monospaced))
                                .foregroundColor(abs(layout.zoom - 1.0) < 0.01 ? Theme.dim : Theme.accent)
                                .frame(minWidth: 34)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06)).cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("0", modifiers: .command)
                        .help("zoom do canvas — clique para voltar a 100% (⌘0)")
                        Button { layout.setZoom(layout.zoom + 0.1) } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: Theme.uiSize(9)))
                                .foregroundColor(Theme.dim)
                                .padding(.horizontal, 5).padding(.vertical, 4)
                                .background(Color.white.opacity(0.06)).cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("=", modifiers: .command)
                        .help("aproximar o canvas (⌘=)")
                    }
                }
                if tab == .painel {
                    SmallButton(label: "centralizar", icon: "scope",
                                help: "traz a visão de volta para o maestro (útil depois de navegar longe)") {
                        centerTick += 1
                    }
                }
                if tab == .painel, layout.isCustomized {
                    SmallButton(label: "realinhar", icon: "square.grid.2x2",
                                help: "devolve todos os cards ao tamanho e à posição automáticos") {
                        withAnimation(.easeOut(duration: 0.2)) { layout.resetAll() }
                        centerTick += 1
                    }
                }
                if tab == .painel, orch.project != nil {
                    SmallButton(label: "arquivos", icon: "sidebar.left",
                                tint: showFiles ? Theme.accent : Theme.dim,
                                help: "abre o navegador de arquivos: veja o projeto e o que cada agente mexeu (bolinha verde = recente)") {
                        showFiles.toggle()
                        if !showFiles { openFile = nil }
                    }
                }
                if tab == .painel, orch.project != nil {
                    SmallButton(label: "encerrar sessão", icon: "stop.circle",
                                help: "desliga maestro e agentes para você trocar de contexto — o trabalho fica salvo") {
                        sheet = SheetTarget(name: "", kind: .stop)
                    }
                }
                if tab == .painel {
                    SmallButton(label: "projeto", icon: "folder",
                                help: "escolher a pasta ou repositório do GitHub em que a equipe vai trabalhar") { showInit = true }
                    SmallButton(label: "novo agente", icon: "plus", tint: Theme.accent,
                                help: "cria um agente manualmente — ou peça ao maestro em português, que ele cria sozinho") { showNew = true }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.card)

            // medidor: uso do Claude Code na maquina toda (nao so os agentes daqui)
            if tab == .painel, let u = orch.usage {
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
                .font(.system(size: Theme.uiSize(9), design: .monospaced))
                .foregroundColor(Theme.dim)
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(Theme.card.opacity(0.5))
                .help("Mede TODO o uso do Claude Code nesta máquina (qualquer sessão, não só os agentes do orquestra). Valores em $ são equivalente de API — no plano Max é régua de consumo, não cobrança. A janela de 5h é o ciclo do plano.")
            }

            Divider().background(Theme.cardBorder)

            // um nvo que falha precisa aparecer: antes o erro morria numa
            // variavel e o clique parecia nao fazer nada
            if let err = orch.lastError, !err.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: Theme.uiSize(11))).foregroundColor(Theme.bg)
                    Text(err)
                        .font(.system(size: Theme.uiSize(10), design: .monospaced))
                        .foregroundColor(Theme.bg)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: { orch.lastError = nil }) {
                        Image(systemName: "xmark").font(.system(size: Theme.uiSize(9), weight: .bold))
                            .foregroundColor(Theme.bg)
                    }
                    .buttonStyle(.plain)
                    .help("dispensar")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color(red: 1.0, green: 0.42, blue: 0.42))
            }

            if tab == .ajuda {
                HelpView()
            } else if tab == .ajustes {
                AjustesView(orch: orch)
            } else {
            HStack(spacing: 0) {
            if showFiles {
                FileBrowser(orch: orch) { openFile = $0 }
                Divider().background(Theme.cardBorder)
            }
            // rola nos dois eixos: o canvas cresce conforme voce espalha os cards.
            // O GeometryReader existe para anular a centralizacao implicita do
            // ScrollView: conteudo menor que a janela seria centralizado, e cada
            // crescimento do canvas re-centralizaria tudo, "empurrando" os cards
            // de volta durante o arraste — em ultrawide isso travava o lado.
            GeometryReader { viewport in
            ScrollViewReader { scroller in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 40) {
                    // canvas livre com origem fixa no canto superior esquerdo:
                    // nada e centralizado, entao arrastar um card nunca desloca
                    // os outros. Maestro e agentes vivem no mesmo plano.
                    let canvas = layout.canvasSize(names: orch.agents.map { $0.name })
                    ZStack(alignment: .topLeading) {
                        // fundo clicavel: arrastar o vazio move a visao (pan)
                        PanArea()
                            .frame(width: canvas.width, height: canvas.height)
                            .help("arraste o fundo para mover a visão do canvas")
                        // marcador invisivel no centro do maestro, com frame de
                        // layout REAL (spacers, nao .position): e o alvo do
                        // scrollTo que centraliza a visao ao abrir e no realinhar
                        HStack(spacing: 0) {
                            Spacer().frame(width: max(0, layout.maestroBox.x + layout.maestroBox.w / 2))
                            VStack(spacing: 0) {
                                Spacer().frame(height: max(0, layout.maestroBox.y + layout.maestroBox.h / 2))
                                Color.clear.frame(width: 1, height: 1).id("foco-maestro")
                            }
                        }
                        .allowsHitTesting(false)
                        MaestroNode(orch: orch)
                        // o cartao de passo ACOMPANHA o maestro: fica ancorado
                        // logo acima dele, onde quer que ele esteja
                        if orch.project == nil {
                            StepCard(step: "1",
                                     title: "Escolha o projeto",
                                     detail: "Uma pasta do seu Mac ou um repositório do GitHub. Os agentes só trabalham dentro dele, cada um numa cópia isolada — seus arquivos ficam intactos até você aprovar.",
                                     buttonLabel: "escolher projeto", buttonIcon: "folder") {
                                showInit = true
                            }
                            .frame(width: layout.maestroBox.w)
                            .position(x: layout.maestroBox.x + layout.maestroBox.w / 2,
                                      y: max(30, layout.maestroBox.y - 38))
                        } else if !orch.maestroRunning {
                            StepCard(step: "2",
                                     title: "Inicie o maestro",
                                     detail: "O maestro é o agente chefe: você fala com ele em português e ele cria, acompanha e coordena os agentes que constroem de verdade.",
                                     buttonLabel: "iniciar maestro", buttonIcon: "play.fill") {
                                orch.startMaestro()
                            }
                            .frame(width: layout.maestroBox.w)
                            .position(x: layout.maestroBox.x + layout.maestroBox.w / 2,
                                      y: max(30, layout.maestroBox.y - 38))
                        }
                        ForEach(Array(orch.agents.enumerated()), id: \.element.id) { idx, a in
                            AgentNode(orch: orch, agent: a, index: idx,
                                onNotes: { sheet = SheetTarget(name: a.name, kind: .notes) },
                                onDiff: {
                                    diffText = "carregando…"
                                    sheet = SheetTarget(name: a.name, kind: .diff)
                                    orch.diff(a.name) { diffText = $0 }
                                },
                                onKill: { sheet = SheetTarget(name: a.name, kind: .kill) },
                                onDone: { sheet = SheetTarget(name: a.name, kind: .done) })
                        }
                        if orch.agents.isEmpty {
                            Text(orch.maestroRunning
                                 ? "3º passo: peça uma equipe ao maestro no campo acima — ou use os exemplos"
                                 : "os agentes que o maestro criar aparecem aqui, conectados a ele")
                                .font(.system(size: Theme.uiSize(11), design: .monospaced))
                                .foregroundColor(Theme.dim)
                                .position(x: layout.maestroBox.x + layout.maestroBox.w / 2,
                                          y: layout.maestroBox.y + layout.maestroBox.h + 46)
                        }
                    }
                    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                    // cabos desenhados ATRAS dos cards, resolvidos no espaco do
                    // canvas: seguem cada card em tempo real durante o arraste
                    .backgroundPreferenceValue(NodeAnchors.self) { anchors in
                        GeometryReader { proxy in
                            if let m = anchors["maestro"] {
                                let mp = proxy[m]
                                // Cada agente liga ao PAI dele, nao ao maestro: e o
                                // cabo que mostra quem delegou o que. Subagente cujo
                                // pai ja saiu cai de volta no maestro, para nao
                                // sumir da arvore.
                                let links: [(CGPoint, CGPoint, Int)] = orch.agents.compactMap { a in
                                    guard let dest = anchors["agent-\(a.name)"] else { return nil }
                                    let origem: CGPoint = {
                                        if !a.parent.isEmpty, let pa = anchors["agent-\(a.parent)"] {
                                            return proxy[pa]
                                        }
                                        return mp
                                    }()
                                    return (origem, proxy[dest], a.depth)
                                }
                                ZStack(alignment: .topLeading) {
                                    Path { p in
                                        for (from, to, _) in links {
                                            // fio com folga: o caimento cresce com a
                                            // distancia, como um cabo real pendurado
                                            let dx = to.x - from.x
                                            let dy = to.y - from.y
                                            let dist = (dx * dx + dy * dy).squareRoot()
                                            let sag = max(26, min(150, dist * 0.22))
                                            p.move(to: from)
                                            p.addCurve(to: to,
                                                control1: CGPoint(x: from.x + dx * 0.12, y: from.y + sag),
                                                control2: CGPoint(x: to.x - dx * 0.12, y: to.y - sag * 0.35))
                                        }
                                    }
                                    .stroke(Theme.cable, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                    // conectores nas pontas, como plugues
                                    Circle().fill(Theme.accent.opacity(0.6))
                                        .frame(width: 6, height: 6).position(mp)
                                    ForEach(Array(links.enumerated()), id: \.offset) { _, l in
                                        Circle().fill(Theme.accent.opacity(0.6))
                                            .frame(width: 6, height: 6).position(l.1)
                                    }
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    // zoom do canvas: escala visual a partir do canto e ajusta o
                    // tamanho do conteudo, para a rolagem cobrir a area escalada
                    .scaleEffect(layout.zoom, anchor: .topLeading)
                    .frame(width: canvas.width * layout.zoom,
                           height: canvas.height * layout.zoom,
                           alignment: .topLeading)
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
                // conteudo nunca menor que a janela, ancorado no canto: sem
                // centralizacao, o canvas so cresce para a direita/baixo e o
                // arraste lateral e 100% livre em qualquer largura de tela
                .frame(minWidth: viewport.size.width,
                       minHeight: viewport.size.height,
                       alignment: .topLeading)
                // as posicoes PADRAO nascem centralizadas na janela: originX
                // desloca apenas cards nunca movidos, e muda so em resize —
                // nunca durante um gesto, entao nada e "puxado de volta"
                .onAppear {
                    // 1400 de folga a esquerda: e o espaco para arrastar cards
                    // para la — a visao abre centrada no maestro, entao a folga
                    // so aparece quando voce vai ate ela
                    layout.originX = 1400 + max(0, (viewport.size.width - 48 - 1076) / 2)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        scroller.scrollTo("foco-maestro", anchor: .center)
                    }
                }
                .onChange(of: viewport.size.width) { w in
                    layout.originX = 1400 + max(0, (w - 48 - 1076) / 2)
                }
                .onChange(of: centerTick) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        scroller.scrollTo("foco-maestro", anchor: .center)
                    }
                }
            }
            // pinca do trackpad: zoom incremental em cima do valor atual
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if pinchBase == 0 { pinchBase = layout.zoom }
                        layout.setZoom(pinchBase * value)
                    }
                    .onEnded { _ in pinchBase = 0 }
            )
            }
            }
            .background(Theme.bg)
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
            case .done:
                DoneSheet(name: s.name, orch: orch)
            case .stop:
                StopSheet(orch: orch)
            }
        }
        .sheet(isPresented: $showNew) { NewAgentSheet(orch: orch) }
        .sheet(isPresented: $showInit) { InitSheet(orch: orch) }
    }
}

@main
struct OrquestraApp: App {
    @ObservedObject private var scale = UIScale.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.automatic)
        .commands {
            // zoom pelos atalhos que todo mundo ja tem no dedo
            CommandGroup(after: .toolbar) {
                Button("Aumentar o texto") { scale.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!scale.canZoomIn)
                Button("Diminuir o texto") { scale.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!scale.canZoomOut)
                Button("Tamanho padrão") { scale.reset() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}
