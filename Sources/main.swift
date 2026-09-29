import AppKit
import UniformTypeIdentifiers
import Darwin

var appName: String { L("app.name") }
let legacyFileList = NSPasteboard.PasteboardType("NSFilenamesPboardType")

func droppedFileURLs(from board: NSPasteboard) -> [URL] {
    let modern = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter { $0.isFileURL }
    if !modern.isEmpty { return modern }
    return (board.propertyList(forType: legacyFileList) as? [String] ?? []).filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
}

func advertisesFiles(_ board: NSPasteboard) -> Bool {
    board.availableType(from: [.fileURL, legacyFileList]) != nil ||
        board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
}

final class RoundedGlassView: NSVisualEffectView {
    var materialOpacity: CGFloat = 1 { didSet { updateBackdropMask() } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = true
        updateBackdropMask()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateBackdropMask()
    }
    private func updateBackdropMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let rect = NSRect(origin: .zero, size: bounds.size)
        let opacity = materialOpacity
        // A layer corner radius alone does not clip the WindowServer backdrop.
        // Mask the native visual effect as well as ordinary foreground layers.
        maskImage = NSImage(size: rect.size, flipped: false) { _ in
            NSColor.black.withAlphaComponent(opacity).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).fill()
            return true
        }
        window?.invalidateShadow()
    }
}

final class SettingsContentView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

/// Hold an OS lock for the lifetime of the process, including across app copies.
final class InstanceLock {
    private var descriptor: Int32 = -1
    func acquire(at path: String) -> Bool {
        guard descriptor == -1 else { return true }
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); return false }
        descriptor = fd
        return true
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle
    return field
}

final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .small
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            imagePosition = .imageOnly
        }
        target = self
        self.action = #selector(run)
        actionBlock = action
        toolTip = title
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func run() { actionBlock?() }
}

final class ShelfView: NSView, NSDraggingSource {
    weak var owner: AppDelegate?
    var highlighted = false { didSet { needsDisplay = true } }
    var sessionURLs: [URL] = []
    private var mouseStart: NSPoint?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, legacyFileList])
        setAccessibilityLabel(L("shelf.accessibility"))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit != nil, owner?.isExporting != true, highlighted || owner?.currentDragIsFile == true {
            return self // One continuous drop surface, including rows and controls.
        }
        if hit?.superview === self, hit is NSTextField || hit is NSImageView { return self }
        return hit
    }

    override func draw(_ dirtyRect: NSRect) {
        // Leave the backdrop visible; the parent supplies native behind-window blur.
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
        rim.lineWidth = 1
        rim.stroke()
        let box = NSRect(x: 18, y: 65, width: bounds.width - 36, height: bounds.height - 115)
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor.withAlphaComponent(0.10)).setFill()
        let path = NSBezierPath(roundedRect: box, xRadius: 15, yRadius: 15)
        path.fill()
        (highlighted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = highlighted ? 2 : 1
        if owner?.files.isEmpty != false {
            let dashes: [CGFloat] = [5, 5]
            path.setLineDash(dashes, count: 2, phase: 0)
        }
        path.stroke()
    }

    private func urls(_ sender: NSDraggingInfo) -> [URL] {
        droppedFileURLs(from: sender.draggingPasteboard)
    }
    private func updateDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? ShelfView !== self, !(sender.draggingSource is FileRow), owner?.isExporting != true,
              advertisesFiles(sender.draggingPasteboard) else { highlighted = false; return [] }
        // Accept advertised types before lazy pasteboard providers deliver data.
        // Never report move: this destination retains references, not ownership.
        let allowed = sender.draggingSourceOperationMask
        let operation: NSDragOperation = allowed.contains(.copy) ? .copy : (allowed.contains(.link) ? .link : (allowed.contains(.generic) ? .generic : []))
        highlighted = !operation.isEmpty
        return operation
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !updateDrop(sender).isEmpty && !urls(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !updateDrop(sender).isEmpty else { return false }
        let incoming = urls(sender)
        highlighted = false
        guard !incoming.isEmpty else { return false }
        owner?.add(incoming)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y < 58 {
            window?.performDrag(with: event)
        } else { mouseStart = point }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let mouseStart, hypot(convert(event.locationInWindow, from: nil).x - mouseStart.x, convert(event.locationInWindow, from: nil).y - mouseStart.y) > 4,
              let owner, !owner.files.isEmpty else { return }
        self.mouseStart = nil
        sessionURLs = owner.files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !sessionURLs.isEmpty else { return }
        owner.isExporting = true
        let point = convert(event.locationInWindow, from: nil)
        let items = sessionURLs.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(NSRect(x: point.x + CGFloat(index % 4) * 3, y: point.y, width: 42, height: 42), contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        owner?.finishExport(sessionURLs, operation: operation)
        sessionURLs = []
    }
}

final class FileRow: NSView, NSDraggingSource {
    let url: URL
    weak var owner: AppDelegate?
    override var isFlipped: Bool { true }
    init(url: URL, owner: AppDelegate, width: CGFloat) {
        self.url = url
        self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 57))
        let icon = NSImageView(frame: NSRect(x: 12, y: 10, width: 34, height: 34))
        icon.image = NSWorkspace.shared.icon(forFile: url.path)
        addSubview(icon)
        let name = label(url.lastPathComponent, size: 12, weight: .medium)
        name.frame = NSRect(x: 56, y: 10, width: width - 92, height: 18)
        addSubview(name)
        let directory = label(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), size: 10, color: .secondaryLabelColor)
        directory.frame = NSRect(x: 56, y: 30, width: width - 92, height: 15)
        addSubview(directory)
        let remove = ActionButton(L("file.remove"), symbol: "xmark") { [weak owner] in owner?.remove([url]) }
        remove.frame = NSRect(x: width - 31, y: 18, width: 23, height: 23)
        remove.isBordered = false
        addSubview(remove)
        toolTip = url.path
        setAccessibilityLabel(L("file.accessibility", url.lastPathComponent))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit is NSTextField || hit is NSImageView { return self }
        return hit
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            owner?.showMissingFile()
            return
        }
        owner?.isExporting = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40), contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        owner?.finishExport([url], operation: operation)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var shelf: ShelfView!
    var glass: RoundedGlassView!
    var container: NSView!
    var appearancePanel: NSPanel?
    var transparencySlider: NSSlider?
    var transparencyLabel: NSTextField?
    var transparency = 25.0
    let instanceLock = InstanceLock()
    private let revealNotification = Notification.Name("com.loki.qingfang.revealShelf")
    var files: [URL] = []
    var isExporting = false
    var timer: Timer?
    var xDetector = ShakeDetector()
    var yDetector = ShakeDetector()
    var wasPressed = false
    var idlePasteboardCount = NSPasteboard(name: .drag).changeCount
    var currentDragIsFile = false
    var triggered = false
    var cooldownUntil: TimeInterval = 0
    var performRevealHaptic: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let testing = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--snapshot")
        if testing, let index = CommandLine.arguments.firstIndex(of: "--language"), index + 1 < CommandLine.arguments.count,
           let language = AppLanguage(rawValue: CommandLine.arguments[index + 1]) {
            Localization.shared.select(language, persist: false)
        }
        if !testing {
            // Respect an earlier process, including versions without a lock. Order
            // simultaneous launches by launch time and PID so they do not both exit.
            let current = NSRunningApplication.current
            let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.loki.qingfang")
                .filter {
                    guard $0.processIdentifier != current.processIdentifier, !$0.isTerminated else { return false }
                    let otherDate = $0.launchDate ?? .distantPast
                    let currentDate = current.launchDate ?? .distantFuture
                    return otherDate < currentDate || (otherDate == currentDate && $0.processIdentifier < current.processIdentifier)
                }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.loki.qingfang", isDirectory: true)
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch {
                let alert = NSAlert()
                alert.messageText = L("error.initialize")
                alert.informativeText = L("error.supportDirectory", error.localizedDescription)
                alert.addButton(withTitle: L("help.ok"))
                alert.runModal()
                NSApp.terminate(nil)
                return
            }
            guard existing.isEmpty, instanceLock.acquire(at: directory.appendingPathComponent("instance.lock").path) else {
                DistributedNotificationCenter.default().postNotificationName(revealNotification, object: nil, userInfo: nil, deliverImmediately: true)
                NSApp.terminate(nil)
                return
            }
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(revealExistingShelf(_:)), name: revealNotification, object: nil)
        }
        setupPanel()
        setTransparency(UserDefaults.standard.object(forKey: "glassTransparency") as? Double ?? 25, persist: false)
        setupMenu()
        if CommandLine.arguments.contains("--self-test") {
            runFunctionalChecks()
            NSApp.terminate(nil)
            return
        }
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.samplePointer() }
        RunLoop.main.add(timer!, forMode: .common)
        if CommandLine.arguments.contains("--snapshot") {
            renderSnapshot()
            return
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showShelf(nil)
        }
    }

    func setupPanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = appName
        shelf = ShelfView(frame: NSRect(x: 0, y: 0, width: 360, height: 280))
        shelf.owner = self
        glass = RoundedGlassView(frame: shelf.bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        shelf.autoresizingMask = [.width, .height]
        container = NSView(frame: shelf.bounds)
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = true
        container.addSubview(glass)
        container.addSubview(shelf)
        panel.contentView = container
        rebuild()
    }

    func setupMenu() {
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        statusItem.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: appName)
        statusItem.button?.toolTip = L("menu.tooltip")
        statusItem.button?.setAccessibilityLabel(appName)
        let menu = NSMenu()
        for (title, action, key) in [(L("menu.show"), #selector(showShelf(_:)), "s"), (L("menu.appearance"), #selector(showAppearance), ","), (L("menu.help"), #selector(showHelp), ""), (L("menu.clear"), #selector(clearShelf), "")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        let languageItem = NSMenuItem(title: L("menu.language"), action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for language in AppLanguage.allCases {
            let title = language == .system ? L("language.system") : (language == .english ? "English" : "简体中文")
            let item = NSMenuItem(title: title, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.rawValue
            item.target = self
            item.state = Localization.shared.language == language ? .on : .off
            languages.addItem(item)
        }
        languageItem.submenu = languages
        menu.addItem(languageItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc func changeLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let language = AppLanguage(rawValue: rawValue) else { return }
        setLanguage(language)
    }

    func setLanguage(_ language: AppLanguage, persist: Bool = true) {
        Localization.shared.select(language, persist: persist)
        panel.title = appName
        shelf.setAccessibilityLabel(L("shelf.accessibility"))
        rebuild()
        setupMenu()
        if let settings = appearancePanel {
            settings.title = L("appearance.title")
            rebuildAppearance()
        }
    }

    func rebuild() {
        shelf.subviews.forEach { $0.removeFromSuperview() }
        let title = label(appName, size: 17, weight: .semibold)
        title.frame = NSRect(x: 22, y: 18, width: 108, height: 24)
        shelf.addSubview(title)
        let subtitle = label(files.isEmpty ? L("shelf.subtitle.empty") : (files.count == 1 ? L("shelf.subtitle.one") : L("shelf.subtitle.many", files.count)), size: 10, color: .secondaryLabelColor)
        subtitle.frame = NSRect(x: 136, y: 23, width: 140, height: 18)
        shelf.addSubview(subtitle)
        let settings = ActionButton(L("shelf.settings"), symbol: "slider.horizontal.3") { [weak self] in self?.showAppearance() }
        settings.frame = NSRect(x: 281, y: 18, width: 25, height: 25)
        settings.isBordered = false
        shelf.addSubview(settings)
        let close = ActionButton(L("shelf.hide"), symbol: "xmark") { [weak self] in self?.panel.orderOut(nil) }
        close.frame = NSRect(x: 314, y: 18, width: 25, height: 25)
        close.isBordered = false
        shelf.addSubview(close)
        if files.isEmpty {
            let icon = NSImageView(frame: NSRect(x: 158, y: 91, width: 44, height: 44))
            icon.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: L("shelf.drop.accessibility"))
            icon.contentTintColor = .controlAccentColor
            shelf.addSubview(icon)
            let primary = label(L("shelf.drop.title"), size: 15, weight: .medium)
            primary.alignment = .center
            primary.frame = NSRect(x: 40, y: 148, width: 280, height: 22)
            shelf.addSubview(primary)
            let secondary = label(L("shelf.drop.subtitle"), size: 11, color: .secondaryLabelColor)
            secondary.alignment = .center
            secondary.frame = NSRect(x: 40, y: 180, width: 280, height: 18)
            shelf.addSubview(secondary)
        } else {
            let scroll = NSScrollView(frame: NSRect(x: 22, y: 70, width: 316, height: 154))
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 306, height: max(154, CGFloat(files.count) * 57)))
            for (index, url) in files.enumerated() {
                let row = FileRow(url: url, owner: self, width: 306)
                row.frame.origin.y = CGFloat(index) * 57
                document.addSubview(row)
            }
            scroll.documentView = document
            shelf.addSubview(scroll)
        }
        let footer = label(files.isEmpty ? L("shelf.footer.empty") : L("shelf.footer.filled"), size: 10, color: .secondaryLabelColor)
        footer.frame = NSRect(x: 22, y: 245, width: 270, height: 16)
        shelf.addSubview(footer)
        if !files.isEmpty {
            let clear = ActionButton(L("menu.clear"), symbol: "trash") { [weak self] in self?.clearShelf() }
            clear.frame = NSRect(x: 312, y: 240, width: 27, height: 25)
            clear.isBordered = false
            shelf.addSubview(clear)
        }
        shelf.needsDisplay = true
    }

    func add(_ urls: [URL]) {
        for url in urls {
            let normalized = url.standardizedFileURL
            if !files.contains(where: { $0.path == normalized.path }) { files.append(normalized) }
        }
        rebuild()
    }
    func remove(_ urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        files.removeAll { paths.contains($0.path) }
        rebuild()
    }
    func finishExport(_ urls: [URL], operation: NSDragOperation) {
        isExporting = false
        guard !operation.isEmpty else { return }
        remove(urls)
        if files.isEmpty { panel.orderOut(nil) }
    }
    @objc func clearShelf() { files.removeAll(); rebuild() }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func showShelf(_ sender: Any?) { show(at: NSEvent.mouseLocation) }
    func setTransparency(_ value: Double, persist: Bool = true) {
        transparency = min(80, max(0, value.isFinite ? value : 25))
        glass.materialOpacity = 1 - transparency / 100
        transparencySlider?.doubleValue = transparency
        transparencyLabel?.stringValue = "\(Int(transparency.rounded()))%"
        if persist { UserDefaults.standard.set(transparency, forKey: "glassTransparency") }
    }
    @objc func transparencyChanged(_ sender: NSSlider) { setTransparency(sender.doubleValue) }
    @objc func showAppearance() {
        if appearancePanel == nil {
            let settings = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 164), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = L("appearance.title")
            settings.isReleasedWhenClosed = false
            settings.level = .floating
            settings.contentView = SettingsContentView(frame: NSRect(x: 0, y: 0, width: 380, height: 164))
            appearancePanel = settings
            rebuildAppearance()
        }
        setTransparency(transparency, persist: false)
        if !panel.isVisible { showShelf(nil) }
        appearancePanel?.center()
        appearancePanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func rebuildAppearance() {
        guard let content = appearancePanel?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        let title = label(L("appearance.transparency"), size: 14, weight: .medium)
        title.frame = NSRect(x: 22, y: 114, width: 230, height: 22)
        content.addSubview(title)
        let percent = label("", size: 13, weight: .medium, color: .secondaryLabelColor)
        percent.alignment = .right
        percent.frame = NSRect(x: 306, y: 114, width: 50, height: 22)
        content.addSubview(percent)
        transparencyLabel = percent
        let slider = NSSlider(value: transparency, minValue: 0, maxValue: 80, target: self, action: #selector(transparencyChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 22, y: 77, width: 334, height: 24)
        slider.setAccessibilityLabel(L("appearance.transparency"))
        content.addSubview(slider)
        transparencySlider = slider
        let hint = label(L("appearance.hint"), size: 10, color: .secondaryLabelColor)
        hint.frame = NSRect(x: 22, y: 47, width: 335, height: 20)
        content.addSubview(hint)
        let reset = ActionButton(L("appearance.reset")) { [weak self] in self?.setTransparency(25) }
        reset.frame = NSRect(x: 274, y: 12, width: 86, height: 26)
        content.addSubview(reset)
        setTransparency(transparency, persist: false)
    }
    @objc func revealExistingShelf(_ notification: Notification) { showShelf(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showShelf(nil)
        return true
    }

    @discardableResult
    func show(at point: NSPoint) -> Bool {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return false }
        let size = panel.frame.size
        let origin = NSPoint(x: max(visible.minX + 12, min(point.x - size.width / 2, visible.maxX - size.width - 12)), y: max(visible.minY + 12, min(point.y - size.height - 22, visible.maxY - size.height - 12)))
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        return panel.isVisible
    }

    func samplePointer() {
        processPointer(pressed: NSEvent.pressedMouseButtons & 1 != 0, point: NSEvent.mouseLocation,
                       time: ProcessInfo.processInfo.systemUptime, board: NSPasteboard(name: .drag))
    }

    func processPointer(pressed: Bool, point: NSPoint, time: TimeInterval, board: NSPasteboard) {
        if !pressed {
            wasPressed = false
            triggered = false
            currentDragIsFile = false
            idlePasteboardCount = board.changeCount
            xDetector.reset()
            yDetector.reset()
            return
        }
        if !wasPressed { wasPressed = true; xDetector.reset(); yDetector.reset() }
        guard !triggered, !isExporting, time >= cooldownUntil else { return }
        if !currentDragIsFile, board.changeCount != idlePasteboardCount {
            currentDragIsFile = advertisesFiles(board)
        }
        guard currentDragIsFile else { return }
        let now = time
        let x = xDetector.sample(point.x, time: now)
        let y = yDetector.sample(point.y, time: now)
        if x || y {
            triggered = true
            cooldownUntil = now + 1
            if !panel.isVisible, show(at: point) { performRevealHaptic() }
        }
    }
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = L("help.title")
        alert.informativeText = L("help.body")
        alert.addButton(withTitle: L("help.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func showMissingFile() {
        let alert = NSAlert()
        alert.messageText = L("error.missing.title")
        alert.informativeText = L("error.missing.body")
        alert.addButton(withTitle: L("help.ok"))
        alert.runModal()
    }
    func runFunctionalChecks() {
        var hapticCount = 0
        performRevealHaptic = { hapticCount += 1 }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("qingfang-test-" + UUID().uuidString)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("测试 file.txt")
        try! Data("fixture".utf8).write(to: file)
        let lockPath = root.appendingPathComponent("instance.lock").path
        var firstLock: InstanceLock? = InstanceLock()
        let secondLock = InstanceLock()
        precondition(firstLock!.acquire(at: lockPath))
        precondition(!secondLock.acquire(at: lockPath), "a second instance cannot own the same lock")
        firstLock = nil
        precondition(secondLock.acquire(at: lockPath), "process exit releases the instance lock")
        precondition(panel.contentView === container && shelf.superview === container && glass.superview === container)
        precondition(glass.blendingMode == .behindWindow && glass.state == .active && !panel.isOpaque)
        let mask = NSBitmapImageRep(data: glass.maskImage!.tiffRepresentation!)!
        for (x, y) in [(0, 0), (mask.pixelsWide - 1, 0), (0, mask.pixelsHigh - 1), (mask.pixelsWide - 1, mask.pixelsHigh - 1)] {
            precondition(mask.colorAt(x: x, y: y)!.alphaComponent == 0, "all backdrop corners must be transparent")
        }
        precondition(abs(mask.colorAt(x: mask.pixelsWide / 2, y: mask.pixelsHigh / 2)!.alphaComponent - glass.materialOpacity) < 0.01)
        add([file, root, file])
        precondition(files.count == 2, "duplicate removal and folder support")
        let rows = (shelf.subviews.compactMap { $0 as? NSScrollView }.first!.documentView!.subviews).compactMap { $0 as? FileRow }
        precondition(rows.count == 2)
        precondition(rows[0].hitTest(NSPoint(x: 65, y: 15)) === rows[0], "file labels must initiate row dragging")
        remove([file])
        precondition(files.count == 1 && files[0].path == root.standardizedFileURL.path)
        clearShelf()
        precondition(fm.fileExists(atPath: file.path), "clearing never deletes files")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let origin = NSPoint(x: 400, y: 500)
        processPointer(pressed: false, point: origin, time: 1, board: board)
        board.clearContents()
        board.writeObjects([file as NSURL, root as NSURL])
        precondition((board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.count ?? 0) == 2)
        panel.orderOut(nil)
        for (i, dx) in [0.0, 30, -30, 30, -30, 30, -30, 30].enumerated() {
            processPointer(pressed: true, point: NSPoint(x: origin.x + dx, y: origin.y), time: 2 + Double(i) * 0.1, board: board)
        }
        precondition(panel.isVisible && triggered, "fresh native file pasteboard plus three shakes opens panel")
        precondition(hapticCount == 1, "a successful shake reveal produces one haptic")
        for i in 0..<16 {
            processPointer(pressed: true, point: NSPoint(x: i.isMultiple(of: 2) ? 430 : 370, y: 500), time: 3 + Double(i) * 0.1, board: board)
        }
        precondition(hapticCount == 1, "continued movement in the same drag must not repeat feedback")
        panel.orderOut(nil)
        processPointer(pressed: false, point: origin, time: 5, board: board)
        for (i, dx) in [0.0, 30, -30, 30, -30, 30, -30, 30].enumerated() {
            processPointer(pressed: true, point: NSPoint(x: origin.x + dx, y: origin.y), time: 6 + Double(i) * 0.1, board: board)
        }
        precondition(!panel.isVisible, "stale drag pasteboard must not trigger")
        processPointer(pressed: false, point: origin, time: 9, board: board)
        board.clearContents()
        board.setString("text drag", forType: .string)
        for (i, dx) in [0.0, 30, -30, 30, -30, 30, -30, 30].enumerated() {
            processPointer(pressed: true, point: NSPoint(x: origin.x + dx, y: origin.y), time: 10 + Double(i) * 0.1, board: board)
        }
        precondition(!panel.isVisible, "text drag must not trigger")
        add([file, root])
        show(at: origin)
        let originalPanel = panel
        show(at: origin)
        precondition(panel === originalPanel, "all reveals reuse one panel")
        isExporting = true
        finishExport([file], operation: [])
        precondition(files.count == 2 && panel.isVisible && !isExporting, "cancelled export preserves the shelf")
        finishExport([file], operation: .copy)
        precondition(files.count == 1 && panel.isVisible, "partial export leaves remaining files visible")
        finishExport([root], operation: .move)
        precondition(files.isEmpty && !panel.isVisible, "last successful export hides the shelf")
        add([file, root])
        show(at: origin)
        finishExport([file, root], operation: .copy)
        precondition(files.isEmpty && !panel.isVisible, "batch export hides the empty shelf")
        precondition(FileManager.default.fileExists(atPath: file.path), "export callbacks never delete original files")
        precondition(hapticCount == 1, "manual reveals and rejected gestures must not produce feedback")
        let savedTransparency = transparency
        setTransparency(80, persist: false)
        let translucentMask = NSBitmapImageRep(data: glass.maskImage!.tiffRepresentation!)!
        precondition(abs(translucentMask.colorAt(x: translucentMask.pixelsWide / 2, y: translucentMask.pixelsHigh / 2)!.alphaComponent - 0.2) < 0.01)
        precondition(shelf.alphaValue == 1 && panel.alphaValue == 1)
        setTransparency(-20, persist: false)
        precondition(transparency == 0 && glass.materialOpacity == 1)
        setTransparency(savedTransparency, persist: false)

        let drop = TestDraggingInfo(board: board)
        board.clearContents()
        board.setString("not a file", forType: .string)
        precondition(shelf.draggingEntered(drop).isEmpty)
        board.clearContents()
        board.writeObjects([file as NSURL, root as NSURL])
        precondition(shelf.draggingUpdated(drop) == .copy, "a rejected initial entry must recover when data arrives")
        precondition(shelf.prepareForDragOperation(drop) && shelf.performDragOperation(drop))
        precondition(files.count == 2, "native destination callbacks accept multiple files")
        shelf.highlighted = true
        for point in [NSPoint(x: 25, y: 25), NSPoint(x: 292, y: 30), NSPoint(x: 325, y: 30), NSPoint(x: 90, y: 90), NSPoint(x: 322, y: 250)] {
            precondition(shelf.hitTest(point) === shelf, "all window controls and rows remain a drop surface")
        }
        shelf.draggingExited(drop)
        precondition(shelf.draggingUpdated(drop) == .copy, "reentry recovers highlighting")
        drop.draggingSource = shelf
        precondition(shelf.draggingUpdated(drop).isEmpty && !shelf.performDragOperation(drop), "self drops are rejected")
        drop.draggingSource = nil
        board.clearContents()
        board.setPropertyList([file.path], forType: legacyFileList)
        precondition(shelf.draggingEntered(drop) == .copy && droppedFileURLs(from: board).count == 1)
        drop.draggingSourceOperationMask = .move
        precondition(shelf.draggingUpdated(drop).isEmpty, "reference-only shelf never consumes source ownership")
        drop.draggingSourceOperationMask = .copy
        shelf.draggingEnded(drop)
        clearShelf()

        show(at: origin)
        let fixedFrame = panel.frame
        processPointer(pressed: false, point: origin, time: 20, board: board)
        board.clearContents()
        board.writeObjects([file as NSURL])
        for (i, dx) in [0.0, 30, -30, 30, -30, 30, -30, 30].enumerated() {
            processPointer(pressed: true, point: NSPoint(x: 700 + dx, y: 600), time: 21 + Double(i) * 0.1, board: board)
        }
        precondition(panel.frame == fixedFrame && hapticCount == 1, "visible shelf must not jump away during another drag")
        panel.orderOut(nil)
        let savedLanguage = Localization.shared.language
        add([file, root])
        showAppearance()
        let savedFrame = panel.frame
        let savedSettingsFrame = appearancePanel!.frame
        let originalStatusItem = statusItem
        let savedFiles = files
        for language in [AppLanguage.english, .simplifiedChinese] {
            setLanguage(language, persist: false)
            precondition(files == savedFiles && panel.frame == savedFrame && panel.isVisible)
            precondition(statusItem === originalStatusItem, "switching languages must reuse the menu bar item")
            precondition(panel.title == appName && appearancePanel!.title == L("appearance.title"))
            precondition(appearancePanel!.isVisible && appearancePanel!.frame == savedSettingsFrame)
            precondition(transparency == savedTransparency && transparencySlider!.doubleValue == savedTransparency)
            precondition(statusItem.menu!.items[0].title == L("menu.show"))
            let languageItems = statusItem.menu!.items.first { $0.submenu != nil }!.submenu!.items
            precondition(languageItems.filter { $0.state == .on }.count == 1)
            precondition(languageItems.first { $0.state == .on }!.representedObject as? String == language.rawValue)
            let translatedRows = shelf.subviews.compactMap { $0 as? NSScrollView }.first!.documentView!.subviews.compactMap { $0 as? FileRow }
            precondition(translatedRows[0].subviews.compactMap { $0 as? ActionButton }.first!.toolTip == L("file.remove"))
        }
        setLanguage(savedLanguage, persist: false)
        clearShelf()
        panel.orderOut(nil)
        appearancePanel?.orderOut(nil)
        print("PASS: live language switching preserves files, windows, transparency and a single menu bar item; translates rows and settings")
        print("PASS: file/folder references, deduplication, drag hit testing, clear safety, native pasteboard, shake-to-panel integration, stale pasteboard rejection, text rejection")
        print("PASS: single-instance lock and release, single panel, glass backdrop, cancelled/partial/final/batch export visibility")
        print("PASS: four transparent backdrop corners, one haptic per shake reveal, no haptic for manual/rejected/repeated gestures")
        print("PASS: background-only transparency, native drop callbacks, delayed data recovery, full-window drop routing, reentry, legacy file lists, stable visible window")
    }
    func renderSnapshot() {
        if let value = ProcessInfo.processInfo.environment["SNAPSHOT_TRANSPARENCY"].flatMap(Double.init) {
            setTransparency(value, persist: false)
        }
        if CommandLine.arguments.contains("--filled") {
            add([URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), URL(fileURLWithPath: "/System/Library")])
        }
        panel.setFrameOrigin(NSPoint(x: 200, y: 200))
        panel.orderFrontRegardless()
        if CommandLine.arguments.contains("--appearance") { showAppearance() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            let target = CommandLine.arguments.contains("--appearance") ? appearancePanel!.contentView! : container!
            guard let bitmap = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { NSApp.terminate(nil); return }
            target.cacheDisplay(in: target.bounds, to: bitmap)
            let path = ProcessInfo.processInfo.environment["SNAPSHOT_PATH"] ?? "/tmp/driftshelf-preview.png"
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Native destination protocol fixture; used only by --self-test.
final class TestDraggingInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    let draggingPasteboard: NSPasteboard
    var draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(board: NSPasteboard) { draggingPasteboard = board }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
