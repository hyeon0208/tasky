import AppKit
import Quartz

struct SavedFolder: Codable, Equatable {
    var id = UUID()
    var bookmark: Data
    var name: String
}

/// 저장한 폴더 목록. 북마크로 기억해 옮기거나 이름을 바꿔도 따라간다.
/// 북마크 풀기는 느릴 수 있어 한 번 푼 위치를 기억해 둔다(그리는 중에 다시 풀지 않는다).
final class DrawerStore {
    static let shared = DrawerStore()
    static let limit = 12

    private(set) var folders: [SavedFolder] = []
    private var resolved: [UUID: URL] = [:]
    var pinned = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: "drawerFolders"),
           let saved = try? JSONDecoder().decode([SavedFolder].self, from: data) { folders = saved }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(folders), forKey: "drawerFolders")
    }

    /// 서랍을 열 때 한 번 부른다. 없어진 폴더는 nil.
    func refresh() {
        resolved = [:]
        var changed = false
        for i in folders.indices {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: folders[i].bookmark, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            resolved[folders[i].id] = url
            if stale, let fresh = try? url.bookmarkData() { folders[i].bookmark = fresh; changed = true }
        }
        if changed { save() }
    }

    func url(of f: SavedFolder) -> URL? { resolved[f.id] }

    /// 성공하면 nil, 아니면 사용자에게 보여줄 이유
    @discardableResult
    func add(_ url: URL) -> String? {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return "폴더만 넣을 수 있어요" }
        if resolved.values.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { return "이미 서랍에 있어요" }
        guard folders.count < Self.limit else { return "서랍에는 \(Self.limit)개까지 넣을 수 있어요" }
        guard let bookmark = try? url.bookmarkData() else { return "이 폴더는 기억할 수 없어요" }
        let f = SavedFolder(bookmark: bookmark, name: url.lastPathComponent)
        folders.append(f)
        resolved[f.id] = url
        save()
        return nil
    }

    func remove(at i: Int) {
        resolved[folders[i].id] = nil
        folders.remove(at: i)
        save()
    }

    func move(from: Int, to: Int) {
        let f = folders.remove(at: from)
        folders.insert(f, at: to > from ? to - 1 : to)
        save()
    }

    /// Finder 규칙: 같은 디스크는 이동, 다른 디스크는 복사, ⌥를 누르면 복사. 실패한 개수를 돌려준다.
    func receive(_ urls: [URL], into dir: URL, copy forceCopy: Bool) -> Int {
        let fm = FileManager.default
        let destVolume = try? dir.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        var failed = 0
        for src in urls where src.deletingLastPathComponent().standardizedFileURL != dir.standardizedFileURL
                              && src.standardizedFileURL != dir.standardizedFileURL {
            let srcVolume = try? src.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            let copy = forceCopy || srcVolume == nil || srcVolume != destVolume
            var target = dir.appendingPathComponent(src.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: target.path) {
                let ext = src.pathExtension, base = src.deletingPathExtension().lastPathComponent
                target = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                n += 1
            }
            do { try copy ? fm.copyItem(at: src, to: target) : fm.moveItem(at: src, to: target) } catch { failed += 1 }
        }
        return failed
    }
}

/// 칼럼 탐색의 한 항목. 하위 목록은 처음 펼칠 때 한 번만 읽는다.
final class FileNode: NSObject {
    let url: URL
    let isFolder: Bool
    let name: String
    private var cached: [FileNode]?
    private(set) var denied = false

    init(url: URL, isFolder: Bool) {
        self.url = url
        self.isFolder = isFolder
        name = FileManager.default.displayName(atPath: url.path)
    }

    var children: [FileNode] {
        if let cached { return cached }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            cached = urls.map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                return FileNode(url: u, isFolder: v?.isDirectory == true && v?.isPackage != true)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            denied = true
            cached = []
        }
        return cached!
    }

    func reload() { cached = nil; denied = false }

    lazy var icon: NSImage = {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = CGSize(width: 18, height: 18)
        return image
    }()
}

/// 칼럼 탐색의 미리보기 칸. NSBrowser가 고른 파일을 representedObject로 넘겨준다.
final class PreviewController: NSViewController {
    private let preview = QLPreviewView(frame: CGRect(x: 0, y: 0, width: 260, height: 300), style: .compact)!
    private let caption = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: 360))
        preview.autoresizingMask = [.width, .height]
        preview.frame = CGRect(x: 10, y: 50, width: 260, height: 300)
        preview.shouldCloseWithWindow = false
        caption.frame = CGRect(x: 10, y: 10, width: 260, height: 32)
        caption.autoresizingMask = [.width]
        caption.alignment = .center
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 2
        caption.lineBreakMode = .byTruncatingMiddle
        container.addSubview(preview)
        container.addSubview(caption)
        view = container
    }

    override var representedObject: Any? {
        didSet {
            guard let node = representedObject as? FileNode else { return }
            _ = view
            preview.previewItem = node.url as NSURL
            let v = try? node.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = v?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
            let date = v?.contentModificationDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
            caption.stringValue = "\(node.name)\n\(size) · \(date)"
        }
    }
}

/// 스페이스로 Quick Look을 띄우는 칼럼 탐색기
final class DrawerBrowser: NSBrowser {
    var onEscape: () -> Void = {}
    /// 처리했으면 true (⌘⌫, ⌘C, ⌘V, ⌘D, ⌘O, Return)
    var onKey: (NSEvent) -> Bool = { _ in false }
    override func cancelOperation(_ sender: Any?) { onEscape() }

    var selectedFiles: [URL] {
        (selectionIndexPaths.compactMap { item(at: $0) as? FileNode }).filter { !$0.isFolder }.map(\.url)
    }

    override func keyDown(with event: NSEvent) {
        if onKey(event) { return }
        if event.charactersIgnoringModifiers == " " {
            let panel = QLPreviewPanel.shared()!
            if panel.isVisible { panel.orderOut(nil) } else if !selectedFiles.isEmpty { panel.makeKeyAndOrderFront(nil) }
            return
        }
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
}

extension DrawerBrowser: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selectedFiles.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { selectedFiles[index] as NSURL }
}

/// 폴더 서랍: 왼쪽은 저장한 폴더, 오른쪽은 Finder 칼럼 보기처럼 폴더를 누르면 다음 칸에 펼쳐진다.
final class DrawerController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSBrowserDelegate, NSMenuDelegate {
    let view: NSView
    private let store = DrawerStore.shared
    private let table = NSTableView()
    private let browser = DrawerBrowser()
    private let message = NSTextField(labelWithString: "")
    private let pinButton = NSButton()
    private let pathControl = NSPathControl()
    private var root: FileNode?
    private let onClose: () -> Void
    private static let tablePasteType = NSPasteboard.PasteboardType("tasky.folder-row")

    init(size: CGSize, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        view = effect
        super.init()
        store.refresh()
        build(size: size)
        rebuildChips()
        if !store.folders.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) } else { showRoot(nil) }
    }

    // MARK: 칩 줄과 최근 파일 (F27 8번)

    private let chips = ChipBar()
    private let recentTable = NSTableView()
    private let recentScroll = NSScrollView()
    private var recent: [RecentFiles.Item] = []
    private var showingRecent = false

    private func rebuildChips() {
        let sel = showingRecent ? -1 : table.selectedRow
        var views: [NSView] = [chip("최근", symbol: "clock", on: sel == -1) { [weak self] in self?.showRecent() }]
        for (i, f) in store.folders.enumerated() {
            let b = chip(f.name, symbol: store.url(of: f) == nil ? "folder.badge.questionmark" : "folder.fill", on: sel == i) { [weak self] in
                guard let self else { return }
                self.showingRecent = false
                if self.table.selectedRow == i { self.tableViewSelectionDidChange(Notification(name: .init(""))) }
                else { self.table.selectRowIndexes([i], byExtendingSelection: false) }
            }
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem("Finder에서 보기") { [weak self] in self?.reveal(row: i) })
            menu.addItem(ClosureMenuItem("서랍에서 빼기") { [weak self] in self?.remove(row: i) })
            b.menu = menu
            views.append(b)
        }
        let add = chip("", symbol: "plus", on: false) { [weak self] in self?.addFolder() }
        add.toolTip = "폴더 추가(폴더를 이 줄에 끌어 놓아도 돼요)"
        views.append(add)
        chips.setViews(views, in: .leading)
    }

    private func chip(_ title: String, symbol: String, on: Bool, _ action: @escaping () -> Void) -> ClosureButton {
        let b = ClosureButton(title, action)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title.isEmpty ? "추가" : nil)
        b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        b.isBordered = false; b.wantsLayer = true
        b.layer?.cornerRadius = 12
        b.layer?.backgroundColor = (on ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.08)).cgColor
        b.contentTintColor = on ? .white : .labelColor
        b.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " \(title) ", attributes: [.foregroundColor: on ? NSColor.white : NSColor.labelColor, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if title.isEmpty { b.widthAnchor.constraint(equalToConstant: 28).isActive = true }
        return b
    }

    private func showRecent() {
        showingRecent = true
        browser.isHidden = true; recentScroll.isHidden = false
        pathControl.url = nil
        message.stringValue = "고정 폴더에서 최근 7일 동안 바뀐 파일"
        rebuildChips()
        let roots = store.folders.compactMap { store.url(of: $0) }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = RecentFiles.collect(roots: roots, now: Date())
            DispatchQueue.main.async { [weak self] in
                guard let self, self.showingRecent else { return }
                self.recent = items
                self.recentTable.reloadData()
                if items.isEmpty { self.message.stringValue = roots.isEmpty ? "먼저 ‘+’로 자주 가는 폴더를 넣어 주세요" : "최근 7일 동안 바뀐 파일이 없어요" }
            }
        }
    }

    private func hideRecent() {
        showingRecent = false
        browser.isHidden = false; recentScroll.isHidden = true
    }

    @objc private func openRecent() {
        let r = recentTable.clickedRow
        if recent.indices.contains(r) { NSWorkspace.shared.open(recent[r].url) }
    }

    static let sideWidth: CGFloat = 0   // F27 8번 A: 왼쪽 목록 대신 위 칩 줄(목록 표는 선택 상태로만 쓴다)
    private static let chipBar: CGFloat = 44
    static let columnWidth: CGFloat = 300
    private static let bar: CGFloat = 56

    /// 칼럼이 늘거나 줄 때 서랍 너비를 바꿔 달라고 요청한다.
    var onWantWidth: (CGFloat) -> Void = { _ in }

    private func build(size: CGSize) {
        let sideWidth = Self.sideWidth, bar = Self.bar

        // 왼쪽: 저장한 폴더
        let column = NSTableColumn(identifier: .init("folder"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 26
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([.fileURL, Self.tablePasteType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Finder에서 보기") { [weak self] in self?.revealClicked() })
        menu.addItem(ClosureMenuItem("서랍에서 빼기") { [weak self] in self?.removeClicked() })
        table.menu = menu
        let scroll = NSScrollView(frame: CGRect(x: 0, y: bar, width: sideWidth, height: size.height - bar))
        scroll.autoresizingMask = [.height]
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.isHidden = true
        view.addSubview(scroll)

        // 위: [최근] [고정 폴더…] [+] 칩 줄. 폴더를 끌어 놓으면 추가
        chips.frame = CGRect(x: 12, y: size.height - Self.chipBar + 8, width: size.width - 24, height: 28)
        chips.autoresizingMask = [.width, .minYMargin]
        chips.orientation = .horizontal; chips.spacing = 6
        chips.onDrop = { [weak self] urls in
            guard let self else { return }
            self.message.stringValue = urls.compactMap { self.store.add($0) }.first ?? ""
            self.table.reloadData(); self.rebuildChips()
            self.table.selectRowIndexes([self.store.folders.count - 1], byExtendingSelection: false)
        }
        view.addSubview(chips)
        let chipLine = NSBox(frame: CGRect(x: 0, y: size.height - Self.chipBar, width: size.width, height: 1))
        chipLine.boxType = .separator; chipLine.autoresizingMask = [.width, .minYMargin]
        view.addSubview(chipLine)

        // 오른쪽: 칼럼 탐색. 칼럼 너비는 고정이고, 칼럼이 늘면 서랍이 넓어진다.
        browser.frame = CGRect(x: sideWidth + 1, y: bar, width: size.width - sideWidth - 1, height: size.height - bar - Self.chipBar - 2)
        browser.autoresizingMask = [.width, .height]
        browser.delegate = self
        browser.onEscape = { [weak self] in self?.onClose() }
        browser.isTitled = false
        browser.hasHorizontalScroller = true
        browser.separatesColumns = true
        browser.allowsMultipleSelection = true
        // 칼럼마다 넉넉한 고정 폭. 칼럼 사이 경계를 끌어 폭을 바꿀 수도 있다.
        browser.columnResizingType = .userColumnResizing
        browser.minColumnWidth = 200
        browser.setDefaultColumnWidth(Self.columnWidth)
        browser.target = self
        browser.action = #selector(browserClicked)
        browser.doubleAction = #selector(openSelected)
        browser.registerForDraggedTypes([.fileURL])
        browser.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        browser.onKey = { [weak self] in self?.handleKey($0) ?? false }
        let itemMenu = NSMenu()
        itemMenu.delegate = self
        browser.menu = itemMenu
        view.addSubview(browser)

        // '최근' 목록(브라우저 자리에 겹쳐 보인다)
        recentScroll.frame = browser.frame
        recentScroll.autoresizingMask = [.width, .height]
        recentScroll.drawsBackground = false; recentScroll.hasVerticalScroller = true
        recentTable.addTableColumn(NSTableColumn(identifier: .init("recent")))
        recentTable.headerView = nil; recentTable.rowHeight = 40; recentTable.style = .plain
        recentTable.backgroundColor = .clear
        recentTable.dataSource = self; recentTable.delegate = self
        recentTable.target = self; recentTable.doubleAction = #selector(openRecent)
        recentTable.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        recentScroll.documentView = recentTable
        recentScroll.isHidden = true
        view.addSubview(recentScroll)
        let line = NSBox(frame: CGRect(x: sideWidth, y: bar - 1, width: size.width - sideWidth, height: 1))
        line.boxType = .separator
        line.autoresizingMask = [.width]
        view.addSubview(line)

        // 하단: 지금 보고 있는 경로. 경로의 칸을 누르면 그 폴더로 간다.
        pathControl.frame = CGRect(x: sideWidth + 8, y: 26, width: size.width - sideWidth - 90, height: 22)
        pathControl.autoresizingMask = [.width]
        pathControl.pathStyle = .standard
        pathControl.controlSize = .small
        pathControl.focusRingType = .none
        pathControl.target = self
        pathControl.action = #selector(pathClicked)
        view.addSubview(pathControl)

        message.frame = CGRect(x: sideWidth + 12, y: 6, width: size.width - sideWidth - 24, height: 16)
        message.autoresizingMask = [.width]
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 11)
        message.lineBreakMode = .byTruncatingTail
        view.addSubview(message)

        let finder = NSButton(image: NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Finder에서 열기")!,
                              target: self, action: #selector(openInFinder))
        finder.isBordered = false
        finder.toolTip = "Finder에서 열기"
        finder.frame = CGRect(x: size.width - 72, y: 24, width: 26, height: 24)
        finder.autoresizingMask = [.minXMargin]
        view.addSubview(finder)

        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "서랍 고정")
        pinButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "서랍 고정 풀기")
        pinButton.setButtonType(.toggle)
        pinButton.isBordered = false
        pinButton.state = store.pinned ? .on : .off
        pinButton.toolTip = "서랍 고정"
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.frame = CGRect(x: size.width - 40, y: 24, width: 26, height: 24)
        pinButton.autoresizingMask = [.minXMargin]
        view.addSubview(pinButton)

        // 네 변과 네 모서리 어디서든 크기를 바꾼다(테두리 없는 창이라 직접 처리)
        for edge in ResizeEdge.Kind.allCases {
            let e = ResizeEdge(kind: edge, in: CGRect(origin: .zero, size: size))
            view.addSubview(e)
        }
    }

    // MARK: 경로와 너비

    /// 지금 고른 항목(없으면 시작 폴더)
    private var currentURL: URL? {
        guard let path = browser.selectionIndexPath, path.count > 0,
              let node = browser.item(at: path) as? FileNode else { return root?.url }
        return node.url
    }

    @objc private func browserClicked() { updateLayout() }

    /// 고른 깊이만큼 칼럼이 보이도록 필요하면 서랍을 넓히고, 하단 경로를 갱신한다.
    /// 칼럼 수는 지금 너비에 맞춰 정한다(사용자가 크기를 바꾸면 따라간다).
    func updateLayout() {
        let need = (browser.selectionIndexPath?.count ?? 0) + 1
        if need > Int(browser.bounds.width / Self.columnWidth) {
            onWantWidth(Self.sideWidth + 1 + CGFloat(need) * Self.columnWidth)
        }
        pathControl.url = currentURL
        browser.scrollColumnToVisible(browser.lastColumn)
    }

    @objc private func pathClicked() {
        guard let url = pathControl.clickedPathItem?.url else { return }
        navigate(to: url)
    }

    /// 경로로 이동. 시작 폴더 안이면 그 깊이까지 칼럼을 펼치고, 바깥(위쪽)이면 그 폴더를 새 시작점으로 삼는다.
    private func navigate(to url: URL) {
        guard let root else { return }
        let rootParts = root.url.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        if parts.starts(with: rootParts) {
            var node = root
            var indexes: [Int] = []
            for name in parts.dropFirst(rootParts.count) {
                guard let i = node.children.firstIndex(where: { $0.url.lastPathComponent == name }) else { break }
                indexes.append(i)
                node = node.children[i]
            }
            if indexes.isEmpty { browser.loadColumnZero() } else { browser.selectionIndexPath = IndexPath(indexes: indexes) }
        } else {
            showRoot(FileNode(url: url, isFolder: true))
        }
        updateLayout()
    }

    // MARK: 저장한 폴더 목록

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === recentTable ? recent.count : store.folders.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === recentTable { return recentCell(recent[row]) }
        let f = store.folders[row]
        let missing = store.url(of: f) == nil
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: missing ? "folder.badge.questionmark" : "folder.fill",
                                              accessibilityDescription: nil)!)
        icon.contentTintColor = missing ? .secondaryLabelColor : .controlAccentColor
        let label = NSTextField(labelWithString: f.name)
        label.textColor = missing ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 6
        stack.frame = CGRect(x: 6, y: 3, width: 160, height: 20)
        cell.addSubview(stack)
        return cell
    }

    private func recentCell(_ item: RecentFiles.Item) -> NSView {
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: item.url.path))
        icon.frame = CGRect(x: 8, y: 4, width: 32, height: 32)
        let name = NSTextField(labelWithString: item.url.lastPathComponent)
        name.font = .systemFont(ofSize: 13, weight: .semibold); name.lineBreakMode = .byTruncatingMiddle
        name.frame = CGRect(x: 48, y: 20, width: 420, height: 17)
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "ko_KR"); f.unitsStyle = .short
        let sub = NSTextField(labelWithString: item.folder + " · " + f.localizedString(for: item.date, relativeTo: Date()))
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor
        sub.frame = CGRect(x: 48, y: 4, width: 420, height: 15)
        [icon, name, sub].forEach(cell.addSubview)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === recentTable { return }
        hideRecent()
        defer { rebuildChips() }
        let row = table.selectedRow
        guard row >= 0 else { showRoot(nil); return }
        let f = store.folders[row]
        guard let url = store.url(of: f) else {
            showRoot(nil)
            message.stringValue = "‘\(f.name)’ 폴더를 찾지 못했어요. 빼고 다시 넣어 주세요."
            return
        }
        showRoot(FileNode(url: url, isFolder: true))
    }

    // 목록 순서 바꾸기와, Finder에서 폴더를 끌어와 추가하기
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        if tableView === recentTable { return recent[row].url as NSURL }   // 최근 파일은 끌어서 꺼낸다
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.tablePasteType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)
        return info.draggingSource as? NSTableView === table ? .move : .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        if let s = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.tablePasteType), let from = Int(s) {
            store.move(from: from, to: row)
            table.reloadData(); rebuildChips()
            return true
        }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        message.stringValue = urls.compactMap { store.add($0) }.first ?? ""
        table.reloadData()
        table.selectRowIndexes([store.folders.count - 1], byExtendingSelection: false)
        return true
    }

    @objc private func addFolder() {   // 칩 줄의 '+'
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "서랍에 넣기"
        store.pinned = true            // 고르는 동안 서랍이 닫히지 않게
        NSApp.activate()
        let ok = panel.runModal() == .OK
        store.pinned = pinButton.state == .on
        guard ok else { return }
        message.stringValue = panel.urls.compactMap { store.add($0) }.first ?? ""
        table.reloadData(); rebuildChips()
        table.selectRowIndexes([store.folders.count - 1], byExtendingSelection: false)
    }

    private func revealClicked() { reveal(row: table.clickedRow) }
    private func reveal(row: Int) {
        guard row >= 0, row < store.folders.count, let url = store.url(of: store.folders[row]) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func removeClicked() { remove(row: table.clickedRow) }
    private func remove(row: Int) {
        guard row >= 0, row < store.folders.count else { return }
        store.remove(at: row)
        table.reloadData(); rebuildChips()
        if !store.folders.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) } else { showRoot(nil) }
    }

    // MARK: 칼럼 탐색

    private func showRoot(_ node: FileNode?) {
        root = node
        message.stringValue = node == nil && store.folders.isEmpty ? "위 ‘+’로 자주 가는 폴더를 넣어 주세요" : ""
        browser.loadColumnZero()
        if let node, node.denied { message.stringValue = Self.deniedMessage }
        updateLayout()
    }

    private static let deniedMessage = "macOS가 이 폴더를 막았어요. 시스템 설정 > 개인정보 보호 및 보안 > 파일 및 폴더에서 허용해 주세요."

    func rootItem(for browser: NSBrowser) -> Any? { root }

    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = (item as? FileNode) ?? root else { return 0 }
        let n = node.children.count
        if node.denied { message.stringValue = Self.deniedMessage }
        return n
    }

    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        ((item as? FileNode) ?? root)!.children[index]
    }

    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool { !((item as? FileNode)?.isFolder ?? true) }

    /// 아이콘 + 이름. 폴더·파일을 아이콘으로 구분한다(폴더는 오른쪽에 › 표시도 붙는다).
    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        guard let node = item as? FileNode else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = node.icon
        attachment.bounds = CGRect(x: 0, y: -4, width: 18, height: 18)
        let s = NSMutableAttributedString(attachment: attachment)
        s.append(NSAttributedString(string: "  " + node.name))
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingMiddle
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: s.length))
        return s
    }

    /// 파일을 고르면 다음 칸에 미리보기
    func browser(_ browser: NSBrowser, previewViewControllerForLeafItem item: Any) -> NSViewController? {
        previewController
    }
    private lazy var previewController = PreviewController()

    /// 더블클릭: 파일은 기본 앱으로 연다. 폴더는 이미 한 번 클릭으로 펼쳐지므로 아무것도 하지 않는다(Finder를 띄우지 않음).
    @objc private func openSelected() {
        let files = browser.selectionIndexPaths.compactMap { browser.item(at: $0) as? FileNode }.filter { !$0.isFolder }
        for file in files { NSWorkspace.shared.open(file.url) }
    }

    @objc private func openInFinder() {
        let current = (browser.selectionIndexPaths.last.flatMap { browser.item(at: $0) as? FileNode })?.url ?? root?.url
        if let current { NSWorkspace.shared.activateFileViewerSelecting([current]) }
    }

    @objc private func togglePin() { store.pinned = pinButton.state == .on }

    // MARK: Finder 같은 기본 동작 (오른쪽 클릭 메뉴와 단축키)

    private func parentNode(ofColumn column: Int) -> FileNode? {
        column <= 0 ? root : browser.parentForItems(inColumn: column) as? FileNode
    }

    /// 지금 고른 항목들과 그 항목들이 있는 폴더·칼럼
    private var selection: (nodes: [FileNode], parent: FileNode?, column: Int) {
        let paths = browser.selectionIndexPaths
        let nodes = paths.compactMap { browser.item(at: $0) as? FileNode }
        guard let last = paths.last, last.count > 0 else { return ([], root, 0) }
        let column = last.count - 1
        return (nodes, parentNode(ofColumn: column), column)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let column = max(browser.clickedColumn, 0)
        guard let parent = parentNode(ofColumn: column) else { return }
        let row = browser.clickedRow
        var nodes: [FileNode] = []
        if row >= 0, row < parent.children.count {
            let clicked = parent.children[row]
            let selected = selection.nodes
            nodes = selected.contains(clicked) ? selected : [clicked]
        }
        func add(_ title: String, _ action: @escaping () -> Void) { menu.addItem(ClosureMenuItem(title, action)) }

        if !nodes.isEmpty {
            add("열기") { [weak self] in self?.open(nodes) }
            if nodes.count == 1, !nodes[0].isFolder {
                let apps = NSWorkspace.shared.urlsForApplications(toOpen: nodes[0].url)
                if !apps.isEmpty {
                    let item = NSMenuItem(title: "다음으로 열기", action: nil, keyEquivalent: "")
                    let sub = NSMenu()
                    for app in apps.prefix(15) {
                        let a = ClosureMenuItem(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")) {
                            NSWorkspace.shared.open([nodes[0].url], withApplicationAt: app, configuration: .init())
                        }
                        let icon = NSWorkspace.shared.icon(forFile: app.path)
                        icon.size = CGSize(width: 16, height: 16)
                        a.image = icon
                        sub.addItem(a)
                    }
                    item.submenu = sub
                    menu.addItem(item)
                }
            }
            add("빠른 보기") { [weak self] in self?.quickLook(nodes) }
            add("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting(nodes.map(\.url)) }
            menu.addItem(.separator())
            if nodes.count == 1 { add("이름 변경…") { [weak self] in self?.rename(nodes[0], in: parent, column: column) } }
            add("복제") { [weak self] in self?.duplicate(nodes, in: parent, column: column) }
            add("휴지통으로 이동") { [weak self] in self?.trash(nodes, in: parent, column: column) }
            menu.addItem(.separator())
            add(nodes.count == 1 ? "‘\(nodes[0].name)’ 복사" : "\(nodes.count)개 항목 복사") { [weak self] in self?.copy(nodes) }
            add("경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(nodes.map(\.url.path).joined(separator: "\n"), forType: .string)
            }
            menu.addItem(.separator())
        }
        add("새로운 폴더") { [weak self] in self?.newFolder(in: parent, column: column) }
        if canPaste { add("항목 붙여넣기") { [weak self] in self?.paste(into: parent, column: column) } }
        add("Finder에서 이 폴더 보기") { NSWorkspace.shared.activateFileViewerSelecting([parent.url]) }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        let sel = selection
        guard let parent = sel.parent else { return false }
        switch (cmd, e.keyCode, e.charactersIgnoringModifiers?.lowercased()) {
        case (true, 51, _) where !sel.nodes.isEmpty: trash(sel.nodes, in: parent, column: sel.column)   // ⌘⌫
        case (true, _, "c") where !sel.nodes.isEmpty: copy(sel.nodes)
        case (true, _, "v"):
            // 고른 것이 폴더면 그 안에, 아니면 지금 칼럼의 폴더에
            if sel.nodes.count == 1, sel.nodes[0].isFolder { paste(into: sel.nodes[0], column: sel.column + 1) }
            else { paste(into: parent, column: sel.column) }
        case (true, _, "d") where !sel.nodes.isEmpty: duplicate(sel.nodes, in: parent, column: sel.column)
        case (true, _, "o") where !sel.nodes.isEmpty: open(sel.nodes)
        case (false, 36, _) where sel.nodes.count == 1: rename(sel.nodes[0], in: parent, column: sel.column)   // Return
        default: return false
        }
        return true
    }

    private func open(_ nodes: [FileNode]) {
        if nodes.count == 1, nodes[0].isFolder { navigate(to: nodes[0].url) } else { nodes.filter { !$0.isFolder }.forEach { NSWorkspace.shared.open($0.url) } }
    }

    private func quickLook(_ nodes: [FileNode]) {
        if let first = nodes.first { navigate(to: first.url) }
        let panel = QLPreviewPanel.shared()!
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    private func copy(_ nodes: [FileNode]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(nodes.map { $0.url as NSURL })
    }

    private var canPaste: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func paste(into folder: FileNode, column: Int) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        // Finder처럼 붙여넣기는 복사. 같은 폴더면 ‘ 2’를 붙여 새로 만든다.
        var failed = 0
        for src in urls {
            do { try FileManager.default.copyItem(at: src, to: uniqueURL(for: src.lastPathComponent, in: folder.url)) } catch { failed += 1 }
        }
        message.stringValue = failed > 0 ? "\(failed)개를 붙여넣지 못했어요" : ""
        refresh(folder, column: column)
    }

    private func duplicate(_ nodes: [FileNode], in parent: FileNode, column: Int) {
        for n in nodes {
            let ext = n.url.pathExtension
            let base = n.url.deletingPathExtension().lastPathComponent + " 복사본"
            try? FileManager.default.copyItem(at: n.url, to: uniqueURL(for: ext.isEmpty ? base : "\(base).\(ext)", in: parent.url))
        }
        refresh(parent, column: column)
    }

    /// 휴지통으로 옮긴다(되돌릴 수 있다). 영구 삭제는 하지 않는다.
    private func trash(_ nodes: [FileNode], in parent: FileNode, column: Int) {
        var failed = 0
        for n in nodes { do { try FileManager.default.trashItem(at: n.url, resultingItemURL: nil) } catch { failed += 1 } }
        if failed == 0 { NSSound(named: "Funk")?.play() }
        message.stringValue = failed > 0 ? "\(failed)개를 휴지통으로 옮기지 못했어요" : ""
        refresh(parent, column: column)
    }

    private func rename(_ node: FileNode, in parent: FileNode, column: Int) {
        let alert = NSAlert()
        alert.messageText = "이름 변경"
        let field = NSTextField(string: node.url.lastPathComponent)
        field.frame = CGRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        alert.window.initialFirstResponder = field
        // 확장자 앞까지만 선택 (Finder와 같이)
        DispatchQueue.main.async {
            let base = node.url.deletingPathExtension().lastPathComponent
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (node.isFolder ? node.url.lastPathComponent : base).utf16.count)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != node.url.lastPathComponent, !name.contains("/") else { return }
        do {
            try FileManager.default.moveItem(at: node.url, to: parent.url.appendingPathComponent(name))
            message.stringValue = ""
        } catch {
            message.stringValue = "이름을 바꾸지 못했어요: 같은 이름이 있거나 권한이 없어요"
        }
        refresh(parent, column: column)
    }

    private func newFolder(in parent: FileNode, column: Int) {
        let url = uniqueURL(for: "새로운 폴더", in: parent.url)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) } catch {
            message.stringValue = "폴더를 만들지 못했어요"
        }
        refresh(parent, column: column)
    }

    private func uniqueURL(for name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        var url = dir.appendingPathComponent(name)
        let ext = url.pathExtension, base = url.deletingPathExtension().lastPathComponent
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// 바뀐 폴더를 다시 읽어 그 칼럼을 새로 그린다.
    private func refresh(_ folder: FileNode, column: Int) {
        folder.reload()
        if column <= 0 { browser.loadColumnZero() } else { browser.reloadColumn(column) }
        updateLayout()
    }

    // 끌어내기
    func browser(_ browser: NSBrowser, canDragRowsWith rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent) -> Bool { true }

    func browser(_ browser: NSBrowser, writeRowsWith rowIndexes: IndexSet, inColumn column: Int, to pasteboard: NSPasteboard) -> Bool {
        guard let parent = column == 0 ? root : browser.parentForItems(inColumn: column) as? FileNode else { return false }
        let urls = rowIndexes.map { parent.children[$0].url as NSURL }
        pasteboard.clearContents()
        return pasteboard.writeObjects(urls)
    }

    // 끌어 넣기: 폴더 위에 놓으면 그 폴더로, 빈 곳에 놓으면 그 칼럼의 폴더로
    private func dropTarget(row: Int, column: Int, operation: NSBrowser.DropOperation) -> FileNode? {
        guard let parent = column <= 0 ? root : browser.parentForItems(inColumn: column) as? FileNode ?? root else { return nil }
        if operation == .on, row >= 0, row < parent.children.count, parent.children[row].isFolder { return parent.children[row] }
        return parent
    }

    func browser(_ browser: NSBrowser, validateDrop info: NSDraggingInfo, proposedRow row: UnsafeMutablePointer<Int>,
                 column: UnsafeMutablePointer<Int>, dropOperation: UnsafeMutablePointer<NSBrowser.DropOperation>) -> NSDragOperation {
        guard dropTarget(row: row.pointee, column: column.pointee, operation: dropOperation.pointee) != nil else { return [] }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func browser(_ browser: NSBrowser, acceptDrop info: NSDraggingInfo, atRow row: Int, column: Int,
                 dropOperation: NSBrowser.DropOperation) -> Bool {
        guard let target = dropTarget(row: row, column: column, operation: dropOperation) else { return false }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let failed = store.receive(urls, into: target.url, copy: NSEvent.modifierFlags.contains(.option))
        message.stringValue = failed > 0 ? "\(failed)개를 넣지 못했어요" : ""
        target.reload()
        // 원본이 다른 칼럼에 보이고 있었다면 그쪽 목록도 다시 읽는다
        root?.reload()
        browser.loadColumnZero()
        updateLayout()
        return true
    }
}

/// 창 가장자리의 크기 조절 영역. 변은 8pt 두께, 모서리는 16pt 정사각형.
/// F27 8번: 고정 폴더들에서 최근 바뀐 파일(깊이 3, 숨김 제외, 최신 순, 최대 200개)
enum RecentFiles {
    struct Item { let url: URL; let folder: String; let date: Date }
    static func collect(roots: [URL], now: Date, days: Int = 7, depth: Int = 3, limit: Int = 200) -> [Item] {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        var out: [Item] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > depth { e.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let d = v.contentModificationDate, d >= since, d <= now.addingTimeInterval(60) else { continue }
                // /var ↔ /private/var 같은 링크 차이를 없애고 '고정 폴더 이름/하위'로
                let base = root.resolvingSymlinksInPath().deletingLastPathComponent().path
                let dir = url.resolvingSymlinksInPath().deletingLastPathComponent().path
                let rel = (dir.hasPrefix(base) ? String(dir.dropFirst(base.count)) : url.deletingLastPathComponent().lastPathComponent).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                out.append(Item(url: url, folder: rel, date: d))
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }
}

/// 폴더를 끌어 놓을 수 있는 칩 줄
final class ChipBar: NSStackView {
    var onDrop: ([URL]) -> Void = { _ in }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop(urls)
        return !urls.isEmpty
    }
}

final class ResizeEdge: NSView {
    enum Kind: CaseIterable { case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
    private let kind: Kind
    private var start: (mouse: CGPoint, frame: CGRect)?
    private static let edge: CGFloat = 8, corner: CGFloat = 16

    init(kind: Kind, in b: CGRect) {
        self.kind = kind
        let e = Self.edge, c = Self.corner
        let frame: CGRect, mask: NSView.AutoresizingMask
        switch kind {
        case .left: (frame, mask) = (CGRect(x: 0, y: c, width: e, height: b.height - 2 * c), [.height, .maxXMargin])
        case .right: (frame, mask) = (CGRect(x: b.width - e, y: c, width: e, height: b.height - 2 * c), [.height, .minXMargin])
        case .bottom: (frame, mask) = (CGRect(x: c, y: 0, width: b.width - 2 * c, height: e), [.width, .maxYMargin])
        case .top: (frame, mask) = (CGRect(x: c, y: b.height - e, width: b.width - 2 * c, height: e), [.width, .minYMargin])
        case .bottomLeft: (frame, mask) = (CGRect(x: 0, y: 0, width: c, height: c), [.maxXMargin, .maxYMargin])
        case .bottomRight: (frame, mask) = (CGRect(x: b.width - c, y: 0, width: c, height: c), [.minXMargin, .maxYMargin])
        case .topLeft: (frame, mask) = (CGRect(x: 0, y: b.height - c, width: c, height: c), [.maxXMargin, .minYMargin])
        case .topRight: (frame, mask) = (CGRect(x: b.width - c, y: b.height - c, width: c, height: c), [.minXMargin, .minYMargin])
        }
        super.init(frame: frame)
        autoresizingMask = mask
    }
    required init?(coder: NSCoder) { fatalError() }

    private var cursor: NSCursor {
        switch kind {
        case .left, .right: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        default: .crosshair
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = (NSEvent.mouseLocation, window.frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start else { return }
        let dx = NSEvent.mouseLocation.x - start.mouse.x, dy = NSEvent.mouseLocation.y - start.mouse.y
        let minSize = window.minSize
        var f = start.frame
        if [.left, .topLeft, .bottomLeft].contains(kind) {
            let w = max(minSize.width, f.width - dx); f.origin.x = f.maxX - w; f.size.width = w
        }
        if [.right, .topRight, .bottomRight].contains(kind) { f.size.width = max(minSize.width, f.width + dx) }
        if [.bottom, .bottomLeft, .bottomRight].contains(kind) {
            let h = max(minSize.height, f.height - dy); f.origin.y = f.maxY - h; f.size.height = h
        }
        if [.top, .topLeft, .topRight].contains(kind) { f.size.height = max(minSize.height, f.height + dy) }
        window.setFrame(f, display: true)
    }

    override func mouseUp(with event: NSEvent) { start = nil }
}
