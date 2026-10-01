import AppKit
import ApplicationServices
import ServiceManagement

let isFrench = Locale.preferredLanguages.first?.hasPrefix("fr") ?? false
func tr(_ en: String, _ fr: String) -> String { isFrench ? fr : en }

struct ExtraItem {
    let key: String
    let pid: pid_t
    let element: AXUIElement
    let label: String
    let icon: NSImage?
    let x: CGFloat
}

func axAttr<T>(_ el: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func axPoint(_ el: AXUIElement, _ name: String) -> CGPoint {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success,
          let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return .zero }
    var p = CGPoint.zero
    var s = CGSize.zero
    if AXValueGetValue(v as! AXValue, .cgPoint, &p) { return p }
    if AXValueGetValue(v as! AXValue, .cgSize, &s) { return CGPoint(x: s.width, y: s.height) }
    return .zero
}

func collectExtras(_ apps: [NSRunningApplication]) -> [ExtraItem] {
    var results = [[ExtraItem]](repeating: [], count: apps.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: apps.count) { i in
        let found = extras(of: apps[i])
        lock.lock(); results[i] = found; lock.unlock()
    }
    return results.flatMap { $0 }.sorted { $0.x < $1.x }
}

func extras(of app: NSRunningApplication) -> [ExtraItem] {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(axApp, 0.15)
    guard let bar: AXUIElement = axAttr(axApp, "AXExtrasMenuBar"),
          let children: [AXUIElement] = axAttr(bar, kAXChildrenAttribute) else { return [] }
    let appName = app.localizedName ?? "?"
    let icon = app.icon.map { img -> NSImage in
        let copy = img.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
    let isControlCenter = app.bundleIdentifier == "com.apple.controlcenter"
    let appKey = app.bundleIdentifier ?? appName
    var items: [ExtraItem] = []
    for child in children {
        let ident: String? = axAttr(child, kAXIdentifierAttribute)
        let title: String? = axAttr(child, kAXTitleAttribute)
        let desc: String? = axAttr(child, kAXDescriptionAttribute)
        let help: String? = axAttr(child, kAXHelpAttribute)
        let pos = axPoint(child, kAXPositionAttribute)
        let size = axPoint(child, kAXSizeAttribute)
        // Control Center exposes unused modules as 0×0 elements.
        guard size.x > 1 && size.y > 1 else { continue }

        let detail = [title, desc, help]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let label: String
        if let detail, isControlCenter || detail.lowercased().hasPrefix(appName.lowercased()) {
            label = detail
        } else if let detail {
            label = "\(appName) — \(detail)"
        } else {
            label = appName
        }
        // Titles change (timers, sync status), so key on the stable identifier or the slot within the app.
        let slot = ident.flatMap { $0.split(separator: "\n").first.map(String.init) } ?? String(items.count)
        items.append(ExtraItem(key: "\(appKey)#\(slot)", pid: app.processIdentifier, element: child,
                               label: label, icon: icon, x: pos.x))
    }
    return items
}

enum Prefs {
    static var order: [String] {
        get { UserDefaults.standard.stringArray(forKey: "order") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "order") }
    }
    static var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "hidden") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "hidden") }
    }
}

/// Saved order first, then anything new in menu bar order.
func applyUserOrder(_ items: [ExtraItem]) -> [ExtraItem] {
    let rank = Dictionary(Prefs.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    let known = items.filter { rank[$0.key] != nil }.sorted { rank[$0.key]! < rank[$1.key]! }
    let unknown = items.filter { rank[$0.key] == nil }
    return known + unknown
}

final class OrderWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let rowType = NSPasteboard.PasteboardType("com.alexisdahan.Viji.row")
    let window: NSWindow
    let table = NSTableView()
    var rows: [ExtraItem]
    var hidden: Set<String>
    var onClose: (() -> Void)?
    var fetch: (() -> [ExtraItem])?

    init(items: [ExtraItem]) {
        rows = applyUserOrder(items)
        hidden = Prefs.hidden
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = tr("List order", "Ordre de la liste")
        window.isReleasedWhenClosed = false
        window.delegate = self

        let show = NSTableColumn(identifier: .init("show"))
        show.title = tr("Show", "Afficher")
        show.width = 60
        let name = NSTableColumn(identifier: .init("name"))
        name.title = tr("Drag rows to reorder", "Glisse les lignes pour changer l'ordre")
        table.addTableColumn(show)
        table.addTableColumn(name)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        table.registerForDraggedTypes([Self.rowType])
        table.draggingDestinationFeedbackStyle = .gap

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let reset = NSButton(title: tr("Sync with menu bar", "Synchroniser"), target: self, action: #selector(syncWithBar))
        let done = NSButton(title: "OK", target: self, action: #selector(closeWindow))
        done.keyEquivalent = "\r"

        let content = window.contentView!
        for v in [scroll, reset, done] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -12),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            reset.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            reset.centerYAnchor.constraint(equalTo: done.centerYAnchor),
        ])
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func save() {
        Prefs.order = rows.map(\.key)
        Prefs.hidden = hidden
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row]
        if tableColumn?.identifier.rawValue == "show" {
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleShown(_:)))
            box.state = hidden.contains(item.key) ? .off : .on
            box.tag = row
            return box
        }
        let cell = NSTableCellView()
        let image = NSImageView(image: item.icon ?? NSImage())
        let text = NSTextField(labelWithString: item.label)
        text.lineBreakMode = .byTruncatingTail
        for v in [image, text] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let pb = NSPasteboardItem()
        pb.setString(String(row), forType: Self.rowType)
        return pb
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        if op == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let str = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.rowType),
              let from = Int(str), rows.indices.contains(from) else { return false }
        let moved = rows.remove(at: from)
        let to = from < row ? row - 1 : row
        rows.insert(moved, at: to)
        tableView.reloadData()
        save()
        return true
    }

    @objc func toggleShown(_ sender: NSButton) {
        let key = rows[sender.tag].key
        if sender.state == .on { hidden.remove(key) } else { hidden.insert(key) }
        save()
    }

    @objc func syncWithBar() {
        rows = (fetch?() ?? rows).sorted { $0.x < $1.x }
        table.reloadData()
        save()
    }

    @objc func closeWindow() { window.close() }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

func templateImage(_ draw: @escaping () -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
        NSColor.black.set()
        draw()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Viji"
    return image
}

let openEyeImage = templateImage {
    let eye = NSBezierPath()
    eye.move(to: NSPoint(x: 1.5, y: 9))
    eye.curve(to: NSPoint(x: 18.5, y: 9), controlPoint1: NSPoint(x: 6, y: 15.5), controlPoint2: NSPoint(x: 14, y: 15.5))
    eye.curve(to: NSPoint(x: 1.5, y: 9), controlPoint1: NSPoint(x: 14, y: 2.5), controlPoint2: NSPoint(x: 6, y: 2.5))
    eye.close()
    eye.lineWidth = 1.6
    eye.lineJoinStyle = .round
    eye.stroke()
    let iris = NSBezierPath(ovalIn: NSRect(x: 6.6, y: 5.6, width: 6.8, height: 6.8))
    iris.lineWidth = 1.6
    iris.stroke()
    NSBezierPath(ovalIn: NSRect(x: 8.4, y: 7.4, width: 3.2, height: 3.2)).fill()
}

let closedEyeImage = templateImage {
    let p0 = NSPoint(x: 2, y: 12.5), p1 = NSPoint(x: 6.5, y: 6.5), p2 = NSPoint(x: 13.5, y: 6.5), p3 = NSPoint(x: 18, y: 12.5)
    let lid = NSBezierPath()
    lid.move(to: p0)
    lid.curve(to: p3, controlPoint1: p1, controlPoint2: p2)
    lid.lineWidth = 1.6
    lid.lineCapStyle = .round
    lid.stroke()
    // Lashes point outward along the lid's normal.
    for t in [0.18, 0.34, 0.5, 0.66, 0.82] as [CGFloat] {
        let u = 1 - t
        let x = u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x
        let y = u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
        let dx = 3*u*u*(p1.x-p0.x) + 6*u*t*(p2.x-p1.x) + 3*t*t*(p3.x-p2.x)
        let dy = 3*u*u*(p1.y-p0.y) + 6*u*t*(p2.y-p1.y) + 3*t*t*(p3.y-p2.y)
        let len = (dx*dx + dy*dy).squareRoot()
        let nx = dy / len, ny = -dx / len
        let lash = NSBezierPath()
        lash.move(to: NSPoint(x: x, y: y))
        lash.line(to: NSPoint(x: x + nx * 2.6, y: y + ny * 2.6))
        lash.lineWidth = 1.4
        lash.lineCapStyle = .round
        lash.stroke()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var extras: [ExtraItem] = []
    var hostPids = Set<pid_t>()
    let scanQueue = DispatchQueue(label: "scan", qos: .userInitiated)
    var orderWindow: OrderWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "Viji"
        setEye(open: false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didSetupLoginItem") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "didSetupLoginItem")
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            // Apps usually install their status item a moment after launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.scanAllApps() }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scanAllApps()
        }
        scanAllApps()
    }

    func otherApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != me }
    }

    /// Only queries apps known to own a status item, unless the first scan hasn't finished yet.
    func currentExtras() -> [ExtraItem] {
        let apps = otherApps()
        return collectExtras(hostPids.isEmpty ? apps : apps.filter { hostPids.contains($0.processIdentifier) })
    }

    func scanAllApps() {
        guard AXIsProcessTrusted() else { return }
        let apps = otherApps()
        scanQueue.async {
            let pids = Set(collectExtras(apps).map(\.pid))
            DispatchQueue.main.async { self.hostPids = pids }
        }
    }

    func setEye(open: Bool) {
        statusItem.button?.image = open ? openEyeImage : closedEyeImage
    }

    func menuWillOpen(_ menu: NSMenu) { setEye(open: true) }

    func menuDidClose(_ menu: NSMenu) { setEye(open: false) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AXIsProcessTrusted() {
            let item = NSMenuItem(title: tr("Grant Accessibility access…", "Autoriser l'accès Accessibilité…"), action: #selector(openAXSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let hidden = Prefs.hidden
            extras = applyUserOrder(currentExtras()).filter { !hidden.contains($0.key) }
            scanAllApps()
            if extras.isEmpty {
                menu.addItem(NSMenuItem(title: tr("No menu bar icons found", "Aucune icône trouvée"), action: nil, keyEquivalent: ""))
            }
            for (i, extra) in extras.enumerated() {
                let item = NSMenuItem(title: extra.label, action: #selector(pressExtra(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                item.image = extra.icon
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: tr("Edit order…", "Modifier l'ordre…"), action: #selector(editOrder), keyEquivalent: ",")
        edit.target = self
        menu.addItem(edit)
        let login = NSMenuItem(title: tr("Open at login", "Ouvrir au démarrage"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: tr("Quit Viji", "Quitter"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func pressExtra(_ sender: NSMenuItem) {
        guard extras.indices.contains(sender.tag) else { return }
        let element = extras[sender.tag].element
        // Our menu must finish closing before another menu can open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if AXUIElementPerformAction(element, kAXPressAction as CFString) != .success {
                AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
            }
        }
    }

    @objc func editOrder() {
        if let existing = orderWindow {
            existing.show()
            return
        }
        let controller = OrderWindowController(items: currentExtras())
        controller.onClose = { [weak self] in self?.orderWindow = nil }
        controller.fetch = { [weak self] in self?.currentExtras() ?? [] }
        orderWindow = controller
        controller.show()
    }

    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    @objc func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
