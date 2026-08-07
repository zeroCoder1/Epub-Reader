//
//  ReaderViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//

import UIKit
import WebKit
import SwiftSoup

class ReaderViewController: UIViewController, WKNavigationDelegate, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UITableViewDataSource, UITableViewDelegate, ThemesSettingsViewControllerDelegate, CustomizeThemeViewControllerDelegate, UIGestureRecognizerDelegate {
    private var pageViewController: UIPageViewController!
    private let epubURL: URL
    private var spineItems: [EPUBSpineItem] = []
    private var currentSpineIndex = 0
    private var currentPage = 0
    private var totalPages = 0
    private var totalPagesPerSpine: [Int] = [] // Track pages per chapter
    private var baseURL: URL?
    // Reusable webviews returned by discarded page VCs; kept warm so same-chapter turns skip reload.
    private var idleWebViews: [WKWebView] = []
    private var webViewChapter: [ObjectIdentifier: Int] = [:] // chapter currently loaded in a webview
    private var webViewTargetPage: [ObjectIdentifier: Int] = [:] // page a webview should show once it finishes loading
    private var readyWebViews: Set<ObjectIdentifier> = [] // webviews that finished loading + paginating
    private var lastReaderLayoutSize: CGSize = .zero // detects rotation/size changes to invalidate layouts
    // Offscreen pass that paginates every chapter so the book's total page count is accurate.
    private var precomputeWebView: WKWebView?
    private var precomputeIndex = 0
    private var didScheduleInitialPrecompute = false
    private var precomputeWorkItem: DispatchWorkItem?
    private var isPageCurlEnabled = UserDefaults.standard.bool(forKey: "isPageCurlEnabled")
    private let pageLabel = UILabel()
    private var pageLabelShowsTotal = false
    private var bookmarks: [Bookmark] = []
    private var highlights: [Highlight] = []
    private var pendingHighlightNavigation: Highlight? // Highlight to scroll to once its spine finishes paginating
    private var pendingBookmarkNavigation: Bookmark? // Bookmark to scroll to once its spine finishes paginating
    private var spreads: [Spread] = [] // fixed-layout viewing units (one or two pages each)
    private let tocTableView = UITableView()
    private let highlightsTableView = UITableView()
    private var tocItems: [EPUBTOCItem] = []
    private let bookmarksTableView = UITableView()
    private var pendingLoadErrorMessage: String?
    private let chapterProgressLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let floatingMenuButton = UIButton(type: .system)
    private var floatingMenuShowsBookmark = false
    private let menuBackdropView = UIControl()
    private let commandPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let panelContentStack = UIStackView()
    private let panelHeaderButton = UIButton(type: .system)
    private let panelHeaderLabel = UILabel()
    private var orientationLocked = false
    private let searchButton = UIButton(type: .system)
    private let themeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let transitionButton = UIButton(type: .system)
    private let highlightsButton = UIButton(type: .system)
    private let quickBookmarkButton = UIButton(type: .system)
    private var panelItemViews: [UIView] = []
    private var coverImage: UIImage?
    private var bookMetadata: EPUBMetadata?
    private var isChromeVisible = false
    private var lastChromeToggleTimestamp: TimeInterval = 0
    private var hasAppeared = false
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    // dc:identifier of the open book, set during parse. Persistence is keyed by this so
    // state survives renaming the file; falls back to the filename when the OPF omits it.
    private var bookIdentifier: String?
    // Stable per-book key. UserDefaults keys can't contain arbitrary characters cleanly,
    // so identifiers are reduced to an alphanumeric-safe form.
    private var bookKey: String {
        if let id = bookIdentifier, !id.isEmpty {
            let safe = id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
            return "id_" + String(safe)
        }
        return epubURL.lastPathComponent
    }
    // Key used before identity was identifier-based; read once to migrate old data forward.
    private var legacyBookKey: String { epubURL.lastPathComponent }
    private var bookmarksStorageKey: String { "savedBookmarks_\(bookKey)" }
    private var highlightsStorageKey: String { "savedHighlights_\(bookKey)" }
    private var readingPositionStorageKey: String { "lastReadPosition_\(bookKey)" }
    
    init(epubURL: URL) {
        self.epubURL = epubURL
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.97, alpha: 1)
        setupNavigationBar()
        setupPageLabel()
        setupReaderChrome()
        
        setupTOCView()
        setupHighlightsView()
        setupBookmarksView()
        setChromeVisible(false, animated: false)

        // EPUB parsing (ZIP extraction + XML) is heavy; run it off the main thread so the
        // reader opens without blocking the UI, then build the pages when it completes.
        loadEPUBAsync()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        highlightsTableView.reloadData()
        bookmarksTableView.reloadData()

        // Parse may have failed before the view was on screen; present it now.
        if let message = pendingLoadErrorMessage {
            pendingLoadErrorMessage = nil
            showLoadErrorAndReturnToLibrary(message: message)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Catch the final location (e.g. after a TOC/bookmark jump that doesn't animate a turn).
        saveReadingPosition()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // On size changes (e.g. rotation) cached column layouts are invalid; drop the warm pool.
        let sizeChanged = lastReaderLayoutSize != .zero && lastReaderLayoutSize != view.bounds.size
        // Update before any re-entrant work below so nested layout passes don't re-trigger this.
        lastReaderLayoutSize = view.bounds.size
        if sizeChanged {
            invalidateWebViewPool()
            // Fixed-layout pairing depends on orientation; rebuild spreads and re-show the current one.
            if isFixedLayoutBook {
                rebuildSpreads()
                if let si = spreadIndex(containingSpine: currentSpineIndex),
                   let vc = createSpreadViewController(spreadIndex: si) {
                    currentSpineIndex = spreads[si].left
                    pageViewController.setViewControllers([vc], direction: .forward, animated: false)
                }
            }
        }
        ensureReaderChromeAboveContent()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Check if page curl setting changed
        let newPageCurlSetting = UserDefaults.standard.bool(forKey: "isPageCurlEnabled")
        if newPageCurlSetting != isPageCurlEnabled {
            isPageCurlEnabled = newPageCurlSetting
            // Recreate page view controller with new style
            recreatePageViewController()
        }
    }
    
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard builder.system == .context else { return }

        let readerSelectionMenu = UIMenu(
            title: "",
            options: .displayInline,
            children: [
                UICommand(title: "Highlight", action: #selector(highlightSelectedText)),
                UICommand(title: "Bookmark", action: #selector(bookmarkFromMenu))
            ]
        )

        builder.insertChild(readerSelectionMenu, atStartOfMenu: .standardEdit)
    }
    
    @objc func highlightSelectedText() {
        guard let currentPageVC = pageViewController.viewControllers?.first as? PageContentViewController else {
            return
        }
        
        // Get the highlight color from settings
        let highlightColor = UserDefaults.standard.string(forKey: "highlightColor") ?? "yellow"
        
        let webView = currentPageVC.webView
        let highlightJS = """
        (function() {
            var doc = window.document;
            var selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) return null;
            var range = selection.getRangeAt(0);
            var selectedText = selection.toString();
            if (!selectedText) return null;

            var textContent = doc.body.textContent || doc.body.innerText;

            // Compute the absolute UTF-16 offset of the selection start within body.textContent.
            function absoluteOffset(container, offsetInNode) {
                var walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, null, false);
                var total = 0, node;
                while (node = walker.nextNode()) {
                    if (node === container) return total + offsetInNode;
                    total += node.textContent.length;
                }
                return -1;
            }
            var startOffset = -1;
            if (range.startContainer.nodeType === 3) {
                startOffset = absoluteOffset(range.startContainer, range.startOffset);
            }
            if (startOffset === -1) { startOffset = textContent.indexOf(selectedText); }

            var contextStart = Math.max(0, startOffset - 50);
            var contextEnd = Math.min(textContent.length, startOffset + selectedText.length + 50);
            var textContext = textContent.substring(contextStart, contextEnd);
            var relativePosition = textContent.length > 0 ? startOffset / textContent.length : 0;

            var span = doc.createElement('span');
            span.className = 'highlight';
            span.style.backgroundColor = '\(highlightColor)';
            span.style.color = 'black';
            try { range.surroundContents(span); }
            catch(e) { var contents = range.extractContents(); span.appendChild(contents); range.insertNode(span); }
            selection.removeAllRanges();

            return { text: selectedText, context: textContext, position: relativePosition, start: startOffset, length: selectedText.length };
        })();
        """
        
        webView.evaluateJavaScript(highlightJS) { result, error in
            if let result = result as? [String: Any],
               let text = result["text"] as? String,
               let context = result["context"] as? String,
               let position = result["position"] as? Double,
               let start = result["start"] as? Int,
               !text.isEmpty {

                let length = (result["length"] as? Int) ?? text.utf16.count
                let highlight = Highlight(
                    spineIndex: self.currentSpineIndex,
                    pageNumber: self.currentPage,
                    text: text,
                    range: NSRange(location: max(0, start), length: length),
                    color: highlightColor,
                    textContext: context,
                    relativePosition: position,
                    startOffset: start >= 0 ? start : nil
                )
                
                self.highlights.append(highlight)
                self.saveHighlights()
                print("Highlight saved: \(text) with color: \(highlightColor)")
            }
        }
    }

    private func recreatePageViewController() {
        // Settings/style changed: cached layouts are stale, so drop the warm pool.
        invalidateWebViewPool()
        // Remove old page view controller
        pageViewController.willMove(toParent: nil)
        pageViewController.view.removeFromSuperview()
        pageViewController.removeFromParent()
        
        // Create new one with updated settings
        setupPageViewController()
    }

    private func setupPageViewController() {
        var transition = ReaderPageTransition(rawValue: UserDefaults.standard.string(forKey: "pageTransition") ?? "slide") ?? .slide
        // Page curl can't flip its direction for RTL, so fall back to slide for RTL books.
        if isRTL, transition == .curl { transition = .slide }
        let style: UIPageViewController.TransitionStyle = (transition == .curl) ? .pageCurl : .scroll
        let orientation: UIPageViewController.NavigationOrientation = (transition == .scroll) ? .vertical : .horizontal
        pageViewController = UIPageViewController(transitionStyle: style, navigationOrientation: orientation, options: nil)
        pageViewController.dataSource = self
        pageViewController.delegate = self
        // Right-to-left books turn pages the other way: flip the horizontal paging direction
        // so "next" (in reading order) reveals from the left. Vertical scroll mode is unaffected.
        pageViewController.view.semanticContentAttribute =
            (isRTL && orientation == .horizontal) ? .forceRightToLeft : .unspecified
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.frame = view.bounds
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Load the initial page — a spread for fixed-layout books, a column page otherwise.
        let initial: PageContentViewController?
        if isFixedLayoutBook {
            rebuildSpreads()
            let si = spreadIndex(containingSpine: currentSpineIndex) ?? 0
            initial = createSpreadViewController(spreadIndex: si)
            if si < spreads.count { currentSpineIndex = spreads[si].left }
        } else {
            initial = createPageViewController(for: currentPage)
        }
        if let initial {
            pageViewController.setViewControllers([initial], direction: .forward, animated: false)
        } else {
            pendingLoadErrorMessage = "No readable chapter was found in this EPUB spine."
        }

        ensureReaderChromeAboveContent()
    }

    private func ensureReaderChromeAboveContent() {
        view.bringSubviewToFront(menuBackdropView)
        view.bringSubviewToFront(commandPanel)
        view.bringSubviewToFront(tocTableView)
        view.bringSubviewToFront(highlightsTableView)
        view.bringSubviewToFront(bookmarksTableView)
        view.bringSubviewToFront(pageLabel)
        view.bringSubviewToFront(chapterProgressLabel)
        view.bringSubviewToFront(closeButton)
        view.bringSubviewToFront(floatingMenuButton)
    }
    
    private func setupTOCView() {
        guard tocTableView.superview == nil else { return }
        tocTableView.isHidden = true
        tocTableView.dataSource = self
        tocTableView.delegate = self
        tocTableView.register(UITableViewCell.self, forCellReuseIdentifier: "TOCCell")
        view.addSubview(tocTableView)
        tocTableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tocTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tocTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tocTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tocTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    private func setupHighlightsView() {
        guard highlightsTableView.superview == nil else { return }
        highlightsTableView.isHidden = true
        highlightsTableView.dataSource = self
        highlightsTableView.delegate = self
        highlightsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "HighlightCell")
        view.addSubview(highlightsTableView)
        highlightsTableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            highlightsTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            highlightsTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            highlightsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            highlightsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    private func setupBookmarksView() {
        guard bookmarksTableView.superview == nil else { return }
        bookmarksTableView.isHidden = true
        bookmarksTableView.dataSource = self
        bookmarksTableView.delegate = self
        bookmarksTableView.register(UITableViewCell.self, forCellReuseIdentifier: "BookmarkCell")
        view.addSubview(bookmarksTableView)
        bookmarksTableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bookmarksTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bookmarksTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bookmarksTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bookmarksTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupPageLabel() {
        view.addSubview(pageLabel)
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            pageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        pageLabel.textAlignment = .center
        pageLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        pageLabel.textColor = UIColor(white: 0.35, alpha: 0.85)
    }
    
    private func setupNavigationBar() {
        navigationItem.hidesBackButton = true
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    private func setupReaderChrome() {
        setupTopChrome()
        setupBottomChrome()
    }

    private func setupTopChrome() {
        chapterProgressLabel.text = ""
        chapterProgressLabel.textAlignment = .center
        chapterProgressLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        chapterProgressLabel.textColor = UIColor(white: 0.45, alpha: 0.9)
        chapterProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chapterProgressLabel)

        closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.85)
        closeButton.tintColor = UIColor(white: 0.35, alpha: 1.0)
        closeButton.layer.cornerRadius = 22
        closeButton.clipsToBounds = true
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        closeButton.addTarget(self, action: #selector(closeReader), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            chapterProgressLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            chapterProgressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18)
        ])
    }

    private func setupBottomChrome() {
        floatingMenuButton.backgroundColor = UIColor(white: 1.0, alpha: 0.92)
        floatingMenuButton.tintColor = UIColor(white: 0.10, alpha: 1.0)
        floatingMenuButton.layer.cornerRadius = 22
        floatingMenuButton.clipsToBounds = true
        floatingMenuButton.setImage(UIImage(systemName: "list.bullet", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        floatingMenuButton.addTarget(self, action: #selector(toggleCommandPanel), for: .touchUpInside)
        floatingMenuButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenuButton)

        menuBackdropView.alpha = 0
        menuBackdropView.isHidden = true
        menuBackdropView.backgroundColor = .clear
        menuBackdropView.addTarget(self, action: #selector(hideCommandPanel), for: .touchUpInside)
        menuBackdropView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuBackdropView)

        commandPanel.effect = nil
        commandPanel.backgroundColor = .clear
        commandPanel.alpha = 0
        commandPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(commandPanel)

        panelContentStack.axis = .vertical
        panelContentStack.spacing = 8
        panelContentStack.alignment = .fill
        panelContentStack.translatesAutoresizingMaskIntoConstraints = false
        commandPanel.contentView.addSubview(panelContentStack)

        configurePanelButtons()

        NSLayoutConstraint.activate([
            menuBackdropView.topAnchor.constraint(equalTo: view.topAnchor),
            menuBackdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            menuBackdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            menuBackdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            floatingMenuButton.widthAnchor.constraint(equalToConstant: 44),
            floatingMenuButton.heightAnchor.constraint(equalToConstant: 44),
            floatingMenuButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            floatingMenuButton.bottomAnchor.constraint(equalTo: pageLabel.topAnchor, constant: -12),

            commandPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            commandPanel.widthAnchor.constraint(equalToConstant: 250),
            commandPanel.bottomAnchor.constraint(equalTo: floatingMenuButton.topAnchor, constant: -12),

            panelContentStack.topAnchor.constraint(equalTo: commandPanel.contentView.topAnchor),
            panelContentStack.bottomAnchor.constraint(equalTo: commandPanel.contentView.bottomAnchor),
            panelContentStack.leadingAnchor.constraint(equalTo: commandPanel.contentView.leadingAnchor),
            panelContentStack.trailingAnchor.constraint(equalTo: commandPanel.contentView.trailingAnchor)
        ])
    }

    private func configurePanelButtons() {
        panelHeaderButton.addTarget(self, action: #selector(toggleTOC), for: .touchUpInside)
        searchButton.addTarget(self, action: #selector(showSearchNotReady), for: .touchUpInside)
        themeButton.addTarget(self, action: #selector(showThemeAndSettingsPanel), for: .touchUpInside)

        configureRoundActionButton(shareButton, symbol: "square.and.arrow.up", action: #selector(shareCurrentBook))
        configureRoundActionButton(transitionButton, symbol: "rotate.right", action: #selector(toggleOrientationLock))
        configureRoundActionButton(highlightsButton, symbol: "highlighter", action: #selector(showHighlightsList))
        configureRoundActionButton(quickBookmarkButton, symbol: "bookmark", action: #selector(toggleBookmarkCurrentPage))

        let headerRow = makeGlassRow(button: panelHeaderButton, label: panelHeaderLabel, title: "Contents · ", symbol: "list.bullet", height: 48, cornerRadius: 24)
        let searchRow = makeGlassRow(button: searchButton, label: UILabel(), title: "Search Book", symbol: "magnifyingglass", height: 48, cornerRadius: 24)
        let themeRow = makeGlassRow(button: themeButton, label: UILabel(), title: "Themes & Settings", symbol: "textformat.size", height: 48, cornerRadius: 24)

        let actionStack = UIStackView()
        actionStack.axis = .horizontal
        actionStack.spacing = 8
        actionStack.distribution = .fillEqually
        [shareButton, transitionButton, highlightsButton,quickBookmarkButton]
            .map { glassWrap($0, height: 50, cornerRadius: 25) }
            .forEach { actionStack.addArrangedSubview($0) }

        panelItemViews = [headerRow, searchRow, themeRow, actionStack]
        panelItemViews.forEach { panelContentStack.addArrangedSubview($0) }

        updateOrientationLockButtonState()
        updateBookmarkButtonState()
    }

    private func makeGlassRow(button: UIButton, label: UILabel, title: String, symbol: String, height: CGFloat, cornerRadius: CGFloat) -> UIVisualEffectView {
        let container = makeGlassContainer(cornerRadius: cornerRadius)
        label.text = title
        label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .label
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        container.contentView.addSubview(label)
        container.contentView.addSubview(icon)
        container.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: height),
            label.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 18),
            label.centerYAnchor.constraint(equalTo: container.contentView.centerYAnchor),
            icon.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -18),
            icon.centerYAnchor.constraint(equalTo: container.contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            button.topAnchor.constraint(equalTo: container.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor)
        ])
        return container
    }

    private func makeGlassContainer(cornerRadius: CGFloat) -> UIVisualEffectView {
        let effectView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            effectView = UIVisualEffectView(effect: glass)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        }
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        return effectView
    }

    private func glassWrap(_ button: UIButton, height: CGFloat, cornerRadius: CGFloat) -> UIVisualEffectView {
        button.backgroundColor = .clear
        let container = makeGlassContainer(cornerRadius: cornerRadius)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: height),
            button.topAnchor.constraint(equalTo: container.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor)
        ])
        return container
    }

    private func configureRoundActionButton(_ button: UIButton, symbol: String, action: Selector) {
        button.tintColor = .label
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func closeReader() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func toggleCommandPanel() {
        if commandPanel.alpha > 0 {
            hideCommandPanel()
        } else {
            showCommandPanel()
        }
    }

    private func showCommandPanel() {
        updatePanelProgress()
        menuBackdropView.isHidden = false
        menuBackdropView.alpha = 1
        view.layoutIfNeeded()
        commandPanel.transform = collapsedPanelTransform()
        commandPanel.alpha = 0
        let count = panelItemViews.count
        for (i, item) in panelItemViews.enumerated() {
            item.alpha = 0
            UIView.animate(withDuration: 0.28, delay: 0.06 + Double(count - 1 - i) * 0.05, options: [.curveEaseOut]) {
                item.alpha = 1
            }
        }
        floatingMenuButton.isUserInteractionEnabled = false
        closeButton.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.6, options: [.curveEaseOut], animations: {
            self.commandPanel.transform = .identity
            self.commandPanel.alpha = 1
            self.floatingMenuButton.alpha = 0
            self.closeButton.alpha = 0
        })
    }

    // Scale/translate so the panel collapses into its bottom-right corner (above the menu button).
    private func collapsedPanelTransform() -> CGAffineTransform {
        let s: CGFloat = 0.05
        let w = commandPanel.bounds.width, h = commandPanel.bounds.height
        return CGAffineTransform(translationX: (1 - s) * w / 2, y: (1 - s) * h / 2).scaledBy(x: s, y: s)
    }

    @objc private func hideCommandPanel() {
        guard !menuBackdropView.isHidden else { return }
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseIn], animations: {
            self.commandPanel.transform = self.collapsedPanelTransform()
            self.commandPanel.alpha = 0
            self.menuBackdropView.alpha = 0
            self.floatingMenuButton.alpha = 1
            self.closeButton.alpha = 1
        }, completion: { _ in
            self.menuBackdropView.isHidden = true
            self.commandPanel.transform = .identity
            self.panelItemViews.forEach { $0.alpha = 1 }
            self.floatingMenuButton.isUserInteractionEnabled = true
            self.closeButton.isUserInteractionEnabled = true
        })
    }

    @objc private func handleReaderTap() {
        let now = CACurrentMediaTime()
        if now - lastChromeToggleTimestamp < 0.25 {
            return
        }
        lastChromeToggleTimestamp = now

        if commandPanel.alpha > 0 {
            hideCommandPanel()
        }
        setChromeVisible(!isChromeVisible, animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    private func setChromeVisible(_ visible: Bool, animated: Bool) {
        isChromeVisible = visible
        pageLabelShowsTotal = visible
        updatePageLabel()
        let updates = {
            self.chapterProgressLabel.alpha = visible ? 1 : 0
            self.closeButton.alpha = visible ? 1 : 0
            self.floatingMenuButton.alpha = visible ? 1 : 0
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: updates)
        } else {
            updates()
        }

        chapterProgressLabel.isUserInteractionEnabled = visible
        closeButton.isUserInteractionEnabled = visible
        floatingMenuButton.isUserInteractionEnabled = visible
    }

    @objc private func showSearchNotReady() {
        let alert = UIAlertController(title: "Search", message: "Search UI will be added next.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func showThemeAndSettingsPanel() {
        hideCommandPanel()
        let themesVC = ThemesSettingsViewController()
        themesVC.delegate = self
        themesVC.modalPresentationStyle = .overFullScreen
        themesVC.modalTransitionStyle = .crossDissolve
        present(themesVC, animated: true)
    }

    func themesViewController(_ controller: ThemesSettingsViewController, didSelectDarkMode isDarkMode: Bool) {
        applyDarkMode(isDarkMode)
    }

    func themesViewController(_ controller: ThemesSettingsViewController, didSelectTheme theme: ReaderTheme) {
        UserDefaults.standard.set(theme.backgroundHex, forKey: "backgroundColor")
        UserDefaults.standard.set(theme.textHex, forKey: "textColor")
        UserDefaults.standard.set(theme.darkBackgroundHex, forKey: "darkBackgroundColor")
        UserDefaults.standard.set(theme.darkTextHex, forKey: "darkTextColor")
        UserDefaults.standard.set(theme.bold ? "bold" : "normal", forKey: "fontWeight")
        reapplyReaderSettings()
    }

    func themesViewController(_ controller: ThemesSettingsViewController, didChangeFontSizeBy delta: Int) {
        let current = UserDefaults.standard.integer(forKey: "fontSize") > 0 ? UserDefaults.standard.integer(forKey: "fontSize") : 16
        let newSize = min(32, max(12, current + delta))
        UserDefaults.standard.set(newSize, forKey: "fontSize")
        reapplyReaderSettings()
    }

    func themesViewController(_ controller: ThemesSettingsViewController, didSelectTransition transition: ReaderPageTransition) {
        UserDefaults.standard.set(transition.rawValue, forKey: "pageTransition")
        isPageCurlEnabled = (transition == .curl)
        UserDefaults.standard.set(isPageCurlEnabled, forKey: "isPageCurlEnabled")
        recreatePageViewController()
    }

    private func reapplyReaderSettings() {
        // Theme/typography changed: invalidate warm pool so adjacent pages reload with new settings.
        invalidateWebViewPool()
        if let currentPageVC = pageViewController.viewControllers?.first as? PageContentViewController {
            applySettings(to: currentPageVC.webView)
            scrollToPage(in: currentPageVC.webView, pageIndex: currentPage)
        }
    }

    func themesViewControllerDidRequestCustomize(_ controller: ThemesSettingsViewController) {
        controller.dismiss(animated: true) {
            let customizeVC = CustomizeThemeViewController()
            customizeVC.delegate = self
            customizeVC.modalPresentationStyle = .pageSheet
            if let sheet = customizeVC.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
            }
            self.present(customizeVC, animated: true)
        }
    }

    func customizeThemeDidUpdate(_ controller: CustomizeThemeViewController) {
        reapplyReaderSettings()
    }

    @objc private func shareCurrentBook() {
        hideCommandPanel()
        let activityVC = UIActivityViewController(activityItems: [epubURL], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    @objc private func showTransitionOptions() {
        hideCommandPanel()
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Slide", style: .default) { _ in self.setTransitionMode(false) })
        alert.addAction(UIAlertAction(title: "Curl", style: .default) { _ in self.setTransitionMode(true) })
        alert.addAction(UIAlertAction(title: "Fast Fade", style: .default) { _ in self.setTransitionMode(false) })
        alert.addAction(UIAlertAction(title: "Scroll", style: .default) { _ in self.setTransitionMode(false) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func setTransitionMode(_ usePageCurl: Bool) {
        UserDefaults.standard.set(usePageCurl, forKey: "isPageCurlEnabled")
        isPageCurlEnabled = usePageCurl
        recreatePageViewController()
    }

    @objc private func showHighlightsList() {
        hideCommandPanel()
        guard !highlights.isEmpty || !bookmarks.isEmpty else {
            let alert = UIAlertController(title: "Nothing Saved Yet", message: "You haven't highlighted or bookmarked anything in this book yet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        // Derive page numbers from each highlight's stable position, not the stored snapshot.
        let pageNumbers: [Int?] = highlights.map { derivedGlobalPage(forSpineIndex: $0.spineIndex, relativePosition: $0.relativePosition) }
        // Match the page the bookmark will actually navigate to: derive from the relative
        // anchor when present, else the stored page number.
        let bookmarkPageNumbers: [Int?] = bookmarks.map { bookmark in
            if let relativePosition = bookmark.relativePosition {
                return derivedGlobalPage(forSpineIndex: bookmark.spineIndex, relativePosition: relativePosition)
            }
            return globalPageNumber(forSpineIndex: bookmark.spineIndex) + bookmark.pageNumber
        }
        let vc = HighlightsListViewController(highlights: highlights,
                                             pageNumbers: pageNumbers,
                                             bookmarks: bookmarks,
                                             bookmarkPageNumbers: bookmarkPageNumbers,
                                             currentSpineIndex: currentSpineIndex,
                                             bookTitle: title ?? "",
                                             coverImage: coverImage,
                                             onSelect: { [weak self] highlight in
            self?.openHighlight(highlight)
        }, onDelete: { [weak self] highlight in
            self?.deleteHighlight(highlight)
        }, onSelectBookmark: { [weak self] bookmark in
            self?.openBookmark(bookmark)
        }, onDeleteBookmark: { [weak self] bookmark in
            self?.deleteBookmark(bookmark)
        })
        vc.modalPresentationStyle = .pageSheet
        present(vc, animated: true)
    }

    private func openBookmark(_ bookmark: Bookmark) {
        if isFixedLayoutBook { showSpine(bookmark.spineIndex); return }
        currentSpineIndex = bookmark.spineIndex
        // Exact anchor: if the bookmark stored a text offset, jump to whatever page now holds
        // that text (font-size independent), mirroring how highlights navigate.
        if bookmark.startOffset != nil {
            pendingBookmarkNavigation = bookmark
            currentPage = 0
            if let newPage = createPageViewController(for: 0, spineIndex: currentSpineIndex) {
                pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
            }
            updatePageLabel()
            return
        }
        // Legacy bookmarks: prefer the relative anchor when the chapter is already paginated,
        // otherwise fall back to the stored page number.
        let paginated = currentSpineIndex < totalPagesPerSpine.count && totalPagesPerSpine[currentSpineIndex] > 1
        if paginated, let relativePosition = bookmark.relativePosition {
            let pages = max(1, totalPagesPerSpine[currentSpineIndex])
            currentPage = min(pages - 1, Int((min(max(relativePosition, 0), 1) * Double(pages)).rounded(.down)))
        } else {
            currentPage = bookmark.pageNumber
        }
        if let newPage = createPageViewController(for: currentPage, spineIndex: currentSpineIndex) {
            pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
        }
        updatePageLabel()
    }

    // Scrolls an already-paginated webview to a bookmark's exact page (from its text offset)
    // and syncs reader state. Falls back to the relative/page anchor if the offset is unlocatable.
    private func scrollToBookmark(_ bookmark: Bookmark, in webView: WKWebView, pages: Int) {
        computePage(forOffset: bookmark.startOffset ?? -1, length: 1, in: webView) { computed in
            var target = computed
            if target < 0 {
                if let relativePosition = bookmark.relativePosition {
                    target = Int((min(max(relativePosition, 0), 1) * Double(pages)).rounded(.down))
                } else {
                    target = bookmark.pageNumber
                }
            }
            target = min(max(0, target), pages - 1)
            self.scrollToPage(in: webView, pageIndex: target) {
                webView.alpha = 1
            }
            if let vc = self.findPageViewController(for: webView) {
                vc.pageIndex = target
                vc.targetPageIndex = target
                self.pageViewController.setViewControllers([vc], direction: .forward, animated: false)
            }
            self.currentSpineIndex = bookmark.spineIndex
            self.currentPage = target
            self.totalPages = pages
            self.updatePageLabel()
        }
    }

    private func deleteBookmark(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: {
            $0.spineIndex == bookmark.spineIndex &&
            $0.pageNumber == bookmark.pageNumber &&
            $0.date == bookmark.date
        }) else { return }
        bookmarks.remove(at: index)
        saveBookmarks()
        updateBookmarkButtonState()
    }

    private func deleteHighlight(_ highlight: Highlight) {
        guard let index = highlights.firstIndex(where: {
            $0.spineIndex == highlight.spineIndex &&
            $0.date == highlight.date &&
            $0.text == highlight.text &&
            NSEqualRanges($0.range, highlight.range)
        }) else { return }
        let wasOnCurrentSpine = highlights[index].spineIndex == currentSpineIndex
        highlights.remove(at: index)
        saveHighlights()
        if wasOnCurrentSpine, let newPage = createPageViewController(for: currentPage, spineIndex: currentSpineIndex) {
            pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
        }
    }

    private func openHighlight(_ highlight: Highlight) {
        if isFixedLayoutBook { showSpine(highlight.spineIndex); return }
        currentSpineIndex = highlight.spineIndex
        currentPage = 0
        pendingHighlightNavigation = highlight
        if let newPage = createPageViewController(for: 0, spineIndex: currentSpineIndex) {
            pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
        }
        updatePageLabel()
    }

    private func applyDarkMode(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "isDarkMode")
        invalidateWebViewPool()
        if let currentPageVC = pageViewController.viewControllers?.first as? PageContentViewController {
            applySettings(to: currentPageVC.webView)
            scrollToPage(in: currentPageVC.webView, pageIndex: currentPage)
        }
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    @objc private func toggleOrientationLock() {
        orientationLocked.toggle()
        if orientationLocked {
            let current = view.window?.windowScene?.interfaceOrientation ?? .portrait
            AppDelegate.orientationLock = maskFor(current)
        } else {
            AppDelegate.orientationLock = .all
        }
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: AppDelegate.orientationLock)) { _ in }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
        updateOrientationLockButtonState()
    }

    private func maskFor(_ orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    private func updateOrientationLockButtonState() {
        let name = orientationLocked ? "lock.rotation" : "rotate.right"
        transitionButton.setImage(UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        transitionButton.tintColor = orientationLocked ? .black : .label
    }

    private func isCurrentPageBookmarked() -> Bool {
        return bookmarks.contains { $0.spineIndex == currentSpineIndex && $0.pageNumber == currentPage }
    }

    // Fraction (0...1) of the current page within its chapter, so bookmarks can be
    // re-derived after repagination.
    private func currentRelativePosition() -> Double {
        guard currentSpineIndex >= 0, currentSpineIndex < totalPagesPerSpine.count else { return 0 }
        let pages = max(1, totalPagesPerSpine[currentSpineIndex])
        return Double(currentPage) / Double(pages)
    }

    // JS that returns the UTF-16 offset (into body.textContent) of the first text at the
    // top-left of the currently visible page, or -1 if none is found (e.g. an image page).
    private func topOfPageOffsetJS() -> String {
        return """
        (function() {
            var doc = window.document, body = doc.body;
            if (!body) return -1;
            var cs = window.getComputedStyle(body);
            var padL = parseFloat(cs.paddingLeft) || 0;
            var padR = parseFloat(cs.paddingRight) || 0;
            var padT = parseFloat(cs.paddingTop) || 0;
            var usableW = (body.clientWidth || 0) - padL - padR;
            var maxY = body.clientHeight || 400;
            // Probe INSIDE the visible column (not the left edge, where a caret resolves to the
            // previous column's boundary and lands us one page early). Any hit here is on the
            // current page, which is what determines the target page.
            var xs = [padL + usableW * 0.35, padL + usableW * 0.15, padL + usableW * 0.55];
            var range = null;
            for (var y = padT + 2; y < maxY && !range; y += 16) {
                for (var i = 0; i < xs.length; i++) {
                    var r = doc.caretRangeFromPoint ? doc.caretRangeFromPoint(xs[i], y) : null;
                    if (r && r.startContainer && r.startContainer.nodeType === 3
                        && r.startContainer.textContent.trim().length > 0) { range = r; break; }
                }
            }
            if (!range) return -1;
            var walker = doc.createTreeWalker(body, NodeFilter.SHOW_TEXT, null, false);
            var total = 0, node, target = range.startContainer;
            while (node = walker.nextNode()) {
                if (node === target) return total + range.startOffset;
                total += node.textContent.length;
            }
            return -1;
        })();
        """
    }

    // Builds a bookmark for the current location, capturing an exact text-offset anchor from
    // the visible webview when possible, then hands it to `completion`.
    private func makeCurrentBookmark(completion: @escaping (Bookmark) -> Void) {
        let spineIndex = currentSpineIndex
        let pageNumber = currentPage
        let relative = currentRelativePosition()
        let build: (Int?) -> Bookmark = { offset in
            Bookmark(spineIndex: spineIndex, pageNumber: pageNumber, date: Date(),
                     relativePosition: relative, startOffset: offset)
        }
        guard let webView = (pageViewController.viewControllers?.first as? PageContentViewController)?.webView else {
            completion(build(nil)); return
        }
        webView.evaluateJavaScript(topOfPageOffsetJS()) { result, _ in
            let offset = (result as? Int).flatMap { $0 >= 0 ? $0 : nil }
            completion(build(offset))
        }
    }

    @objc private func toggleBookmarkCurrentPage() {
        if let idx = bookmarks.firstIndex(where: { $0.spineIndex == currentSpineIndex && $0.pageNumber == currentPage }) {
            bookmarks.remove(at: idx)
            saveBookmarks()
            updateBookmarkButtonState()
        } else {
            makeCurrentBookmark { [weak self] bookmark in
                guard let self = self else { return }
                self.bookmarks.append(bookmark)
                self.saveBookmarks()
                self.updateBookmarkButtonState()
            }
        }
    }

    private func updateBookmarkButtonState() {
        let on = isCurrentPageBookmarked()
        let name = on ? "bookmark.fill" : "bookmark"
        quickBookmarkButton.setImage(UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        quickBookmarkButton.tintColor = on ? .systemRed : .label
        updateFloatingMenuIcon(bookmarked: on)
    }

    private func updateFloatingMenuIcon(bookmarked: Bool) {
        guard floatingMenuShowsBookmark != bookmarked else { return }
        floatingMenuShowsBookmark = bookmarked
        let name = bookmarked ? "bookmark.fill" : "list.bullet"
        let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        let tint: UIColor = bookmarked ? .systemRed : UIColor(white: 0.10, alpha: 1.0)
        UIView.transition(with: floatingMenuButton, duration: 0.3, options: .transitionCrossDissolve, animations: {
            self.floatingMenuButton.setImage(image, for: .normal)
            self.floatingMenuButton.tintColor = tint
        })
    }

    

    @objc func bookmarkFromMenu() {
        addBookmark()
    }

    // Add bookmark
    @objc func addBookmark() {
        makeCurrentBookmark { [weak self] bookmark in
            guard let self = self else { return }
            self.bookmarks.append(bookmark)
            self.saveBookmarks()
            print("Bookmark added: \(bookmark)")

            // Show confirmation
            let alert = UIAlertController(title: "Bookmark Added", message: "Page bookmarked successfully", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    // Save bookmarks to UserDefaults
    private func saveBookmarks() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(bookmarks) {
            UserDefaults.standard.set(encoded, forKey: bookmarksStorageKey)
            print("Bookmarks saved: \(bookmarks.count) total")
        }
    }

    // Reads per-book data under the current (identifier-based) key, migrating any data still
    // stored under the legacy filename key so highlights/bookmarks saved before this change survive.
    private func loadPerBookData<T: Decodable>(_ type: T.Type, primaryKey: String) -> T? {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        if let data = defaults.object(forKey: primaryKey) as? Data,
           let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        // Fall back to the legacy filename-keyed value and migrate it forward.
        guard bookKey != legacyBookKey else { return nil }
        let legacyKey = primaryKey.replacingOccurrences(of: "_\(bookKey)", with: "_\(legacyBookKey)")
        if let data = defaults.object(forKey: legacyKey) as? Data,
           let value = try? decoder.decode(T.self, from: data) {
            defaults.set(data, forKey: primaryKey)
            return value
        }
        return nil
    }

    // Load bookmarks from UserDefaults
    private func loadBookmarks() {
        if let loadedBookmarks = loadPerBookData([Bookmark].self, primaryKey: bookmarksStorageKey) {
            bookmarks = loadedBookmarks
            print("Bookmarks loaded: \(bookmarks.count) total")
        }
    }

    // Load highlights from UserDefaults
    private func loadHighlights() {
        if let loadedHighlights = loadPerBookData([Highlight].self, primaryKey: highlightsStorageKey) {
            highlights = loadedHighlights
            print("Highlights loaded: \(highlights.count) total")
        }
    }

    // Restore the last-read spine/page into currentSpineIndex/currentPage before the
    // initial page view controller is built. setupPageViewController reads these.
    private func loadReadingPosition() {
        guard let position = loadPerBookData(ReadingPosition.self, primaryKey: readingPositionStorageKey) else { return }
        guard position.spineIndex >= 0, position.spineIndex < spineItems.count else { return }
        currentSpineIndex = position.spineIndex
        currentPage = max(0, position.pageNumber)
        print("Reading position restored: spine \(currentSpineIndex), page \(currentPage)")
    }

    // Persist the current spine/page as the last-read position.
    private func saveReadingPosition() {
        guard !spineItems.isEmpty else { return }
        let position = ReadingPosition(spineIndex: currentSpineIndex, pageNumber: currentPage, date: Date())
        if let encoded = try? JSONEncoder().encode(position) {
            UserDefaults.standard.set(encoded, forKey: readingPositionStorageKey)
        }
    }

    // Save highlights to UserDefaults
    private func saveHighlights() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(highlights) {
            UserDefaults.standard.set(encoded, forKey: highlightsStorageKey)
            print("Highlights saved: \(highlights.count) total")
        }
    }

    // Apply saved highlights to a WebView
    // Encodes a Swift string as a safe JS string literal (handles quotes, newlines, unicode).
    private func jsString(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }

    private func applySavedHighlights(to webView: WKWebView) {
        // Use the webView's own spine, not currentSpineIndex, which can shift during transitions.
        let spine = findPageViewController(for: webView)?.spineIndex ?? currentSpineIndex
        let spineHighlights = highlights.filter { $0.spineIndex == spine }
        guard !spineHighlights.isEmpty else { return }

        let itemsJS = spineHighlights.enumerated().map { index, h in
            let start = h.startOffset ?? -1
            return "{id:\(index),text:\(jsString(h.text)),context:\(jsString(h.textContext)),position:\(h.relativePosition),color:\(jsString(h.color)),start:\(start),len:\(h.range.length)}"
        }.joined(separator: ",")

        let highlightJS = """
        (function() {
            var doc = window.document;
            var items = [\(itemsJS)];
            var textContent = doc.body.textContent || doc.body.innerText;

            // Exact offset lookup: returns {node, offset} for an absolute textContent index.
            function locate(offset) {
                var walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, null, false);
                var total = 0, node;
                while (node = walker.nextNode()) {
                    var len = node.textContent.length;
                    if (total + len >= offset) return { node: node, offset: offset - total };
                    total += len;
                }
                return null;
            }

            // Fallback for legacy highlights without a stored offset.
            function findIndex(it) {
                var idx = -1;
                if (it.context && it.context.length > 0) {
                    var ci = textContent.indexOf(it.context);
                    if (ci !== -1) {
                        var r = it.context.indexOf(it.text);
                        if (r !== -1) idx = ci + r;
                    }
                }
                if (idx === -1 && it.position != null) {
                    var est = Math.floor(textContent.length * it.position);
                    var w = 200;
                    var s = Math.max(0, est - w);
                    var e = Math.min(textContent.length, est + w);
                    var local = textContent.substring(s, e).indexOf(it.text);
                    if (local !== -1) idx = s + local;
                }
                if (idx === -1) idx = textContent.indexOf(it.text);
                return idx;
            }

            function wrap(startIdx, length, color, id) {
                var s = locate(startIdx), e = locate(startIdx + length);
                if (!s || !e) return;
                var range = doc.createRange();
                range.setStart(s.node, s.offset);
                range.setEnd(e.node, e.offset);
                var span = doc.createElement('span');
                span.style.backgroundColor = color;
                span.style.color = 'black';
                span.className = 'saved-highlight';
                span.setAttribute('data-highlight-id', id);
                try { range.surroundContents(span); }
                catch(e2) { var c = range.extractContents(); span.appendChild(c); range.insertNode(span); }
            }

            items.forEach(function(it) {
                if (!it.text || doc.querySelector('[data-highlight-id="' + it.id + '"]')) return;
                var startIdx = (it.start != null && it.start >= 0) ? it.start : findIndex(it);
                if (startIdx === -1) return;
                var length = (it.len && it.len > 0) ? it.len : it.text.length;
                wrap(startIdx, length, it.color, it.id);
            });
            return true;
        })();
        """

        webView.evaluateJavaScript(highlightJS, completionHandler: nil)
    }
    
    @objc private func toggleBookmarks() {
        hideCommandPanel()
        bookmarksTableView.isHidden = !bookmarksTableView.isHidden
        tocTableView.isHidden = true
        highlightsTableView.isHidden = true
        bookmarksTableView.reloadData()
    }

    @objc private func toggleTOC() {
        hideCommandPanel()
        let mapping = tocItems.map { spineIndex(forTOCItem: $0) }
        let pageNumbers = mapping.map { $0.map { globalPageNumber(forSpineIndex: $0) } }
        let currentItemIndex = mapping.lastIndex(where: { ($0 ?? Int.max) <= currentSpineIndex })
        let summary = "Page \(getCurrentGlobalPageNumber()) of \(max(1, getTotalGlobalPages()))"
        let tocVC = TableOfContentsViewController(items: tocItems,
                                                 pageNumbers: pageNumbers,
                                                 currentItemIndex: currentItemIndex,
                                                 bookTitle: title ?? "",
                                                 metadata: bookMetadata,
                                                 coverImage: coverImage,
                                                 pageSummary: summary) { [weak self] item in
            self?.navigate(toTOCItem: item)
        }
        tocVC.modalPresentationStyle = .pageSheet
        present(tocVC, animated: true)
    }

    private func spineIndex(forTOCItem item: EPUBTOCItem) -> Int? {
        var cleanHref = item.href
        if cleanHref.hasPrefix("./") { cleanHref = String(cleanHref.dropFirst(2)) }
        let fileHref = cleanHref.components(separatedBy: "#")[0]
        return spineItems.firstIndex(where: { spine in
            let spineHref = spine.href.components(separatedBy: "#")[0]
            return spineHref == fileHref || spineHref.hasSuffix(fileHref) || fileHref.hasSuffix(spineHref)
        })
    }

    private func globalPageNumber(forSpineIndex spineIndex: Int) -> Int {
        var page = 1
        for i in 0..<spineIndex where i < totalPagesPerSpine.count && isLinearSpine(i) { page += totalPagesPerSpine[i] }
        return page
    }

    // Derives a global page from a stable in-chapter position and the current pagination.
    private func derivedGlobalPage(forSpineIndex spineIndex: Int, relativePosition: Double) -> Int {
        let spineTotal = (spineIndex >= 0 && spineIndex < totalPagesPerSpine.count) ? max(1, totalPagesPerSpine[spineIndex]) : 1
        let clamped = min(max(relativePosition, 0), 1)
        let pageInSpine = min(spineTotal - 1, Int((clamped * Double(spineTotal)).rounded(.down)))
        return globalPageNumber(forSpineIndex: spineIndex) + pageInSpine
    }

    private func navigate(toTOCItem item: EPUBTOCItem) {
        guard let index = spineIndex(forTOCItem: item) else { return }
        if isFixedLayoutBook { showSpine(index); return }
        currentSpineIndex = index
        currentPage = 0
        if let newPage = createPageViewController(for: currentPage, spineIndex: currentSpineIndex) {
            pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
        }
        updatePageLabel()
    }
    
    @objc private func toggleHighlights() {
        hideCommandPanel()
        highlightsTableView.isHidden = !highlightsTableView.isHidden
        tocTableView.isHidden = true
        bookmarksTableView.isHidden = true
        highlightsTableView.reloadData()
    }

    // Everything needed to build the reader UI, produced off the main thread.
    private struct ParsedBook {
        let metadata: EPUBMetadata
        let spine: [EPUBSpineItem]
        let toc: [EPUBTOCItem]
        let baseURL: URL
        let coverImage: UIImage?
    }

    private enum ReaderLoadError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    // Parses the EPUB on a background queue, then applies the result (or shows an error) on main.
    private func loadEPUBAsync() {
        showLoadingIndicator()
        let url = epubURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<ParsedBook, Error>
            do {
                guard let parsed = try EPUBParser.parseEPUB(at: url) else {
                    throw ReaderLoadError.message("Failed to parse EPUB package data.")
                }
                guard !parsed.spine.isEmpty else {
                    throw ReaderLoadError.message("EPUB parsed, but no spine items were found.")
                }
                var cover: UIImage? = nil
                if let coverURL = parsed.metadata.coverImageURL, let data = try? Data(contentsOf: coverURL) {
                    cover = UIImage(data: data)
                }
                outcome = .success(ParsedBook(metadata: parsed.metadata, spine: parsed.spine,
                                              toc: parsed.toc, baseURL: parsed.baseURL, coverImage: cover))
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async {
                guard let self = self else {
                    // Reader was dismissed mid-parse: don't leak the extraction we just created.
                    if case .success(let book) = outcome { EPUBParser.cleanupExtraction(at: book.baseURL) }
                    return
                }
                self.hideLoadingIndicator()
                switch outcome {
                case .success(let book):
                    self.applyParsedBook(book)
                case .failure(let error):
                    let message = (error as? LocalizedError)?.errorDescription ?? "Failed to open this EPUB."
                    if self.hasAppeared {
                        self.showLoadErrorAndReturnToLibrary(message: message)
                    } else {
                        self.pendingLoadErrorMessage = message
                    }
                }
            }
        }
    }

    // Main-thread: install the parsed book and build the reading UI.
    private func applyParsedBook(_ book: ParsedBook) {
        title = book.metadata.title
        bookIdentifier = book.metadata.identifier
        bookMetadata = book.metadata
        spineItems = book.spine
        tocItems = book.toc
        baseURL = book.baseURL
        coverImage = book.coverImage
        totalPagesPerSpine = Array(repeating: 1, count: book.spine.count)

        // Start on the first linear chapter (a book can open with non-linear front matter).
        currentSpineIndex = spineItems.firstIndex(where: { $0.linear }) ?? 0

        let fxlCount = spineItems.filter { $0.isFixedLayout }.count
        print("FXL diagnostic: \(fxlCount)/\(spineItems.count) spine items are fixed-layout; rendition:spread=\(bookMetadata?.renditionSpread ?? "nil"); page-progression=\(bookMetadata?.pageProgressionDirection ?? "ltr (default)")")

        // Identity is now known, so per-book state keys are valid.
        loadHighlights()
        loadBookmarks()
        loadReadingPosition()
        setupPageViewController()
        tocTableView.reloadData()
        highlightsTableView.reloadData()
        bookmarksTableView.reloadData()
    }

    private func showLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        if loadingIndicator.superview == nil {
            view.addSubview(loadingIndicator)
            NSLayoutConstraint.activate([
                loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
        view.bringSubviewToFront(loadingIndicator)
        loadingIndicator.startAnimating()
    }

    private func hideLoadingIndicator() {
        loadingIndicator.stopAnimating()
    }

    deinit {
        precomputeWorkItem?.cancel()
        // Remove this book's extracted files when the reader goes away.
        if let baseURL = baseURL {
            EPUBParser.cleanupExtraction(at: baseURL)
        }
    }
    
    private func createPageViewController(for pageIndex: Int, spineIndex: Int? = nil) -> PageContentViewController? {
        guard let baseURL = baseURL else { return nil }
        let targetSpineIndex = spineIndex ?? currentSpineIndex
        guard targetSpineIndex >= 0, targetSpineIndex < spineItems.count else { return nil }
        let chapterURL = baseURL.appendingPathComponent(spineItems[targetSpineIndex].href)
        guard FileManager.default.fileExists(atPath: chapterURL.path) else {
            print("Missing spine file: \(chapterURL.path)")
            return nil
        }

        // Prefer a pooled webview already showing this chapter: reuse it and just move columns.
        var reusedWarm = false
        let webView: WKWebView
        if let idx = idleWebViews.firstIndex(where: {
            webViewChapter[ObjectIdentifier($0)] == targetSpineIndex && readyWebViews.contains(ObjectIdentifier($0))
        }) {
            webView = idleWebViews.remove(at: idx)
            reusedWarm = true
        } else if let shell = idleWebViews.popLast() {
            // Reuse an idle webview shell (skips process spin-up) but reload the new chapter.
            webView = shell
            webViewChapter[ObjectIdentifier(webView)] = targetSpineIndex
            readyWebViews.remove(ObjectIdentifier(webView))
            webView.alpha = 0
            webView.loadFileURL(chapterURL, allowingReadAccessTo: baseURL)
        } else {
            webView = makeReaderWebView()
            webViewChapter[ObjectIdentifier(webView)] = targetSpineIndex
            webView.alpha = 0
            webView.loadFileURL(chapterURL, allowingReadAccessTo: baseURL)
        }

        // Record the target so didFinish scrolls to the right page even before this VC is attached.
        webViewChapter[ObjectIdentifier(webView)] = targetSpineIndex
        webViewTargetPage[ObjectIdentifier(webView)] = pageIndex

        let pageVC = PageContentViewController(webView: webView, pageIndex: pageIndex, spineIndex: targetSpineIndex, delegate: self)
        pageVC.targetPageIndex = pageIndex

        if reusedWarm {
            if let pending = pendingHighlightNavigation, pending.spineIndex == targetSpineIndex {
                // Honor a pending highlight jump instead of the raw requested page.
                pendingHighlightNavigation = nil
                let pages = max(1, totalPagesPerSpine[targetSpineIndex])
                webView.alpha = 1
                scrollToHighlight(pending, in: webView, pages: pages)
            } else if let pending = pendingBookmarkNavigation, pending.spineIndex == targetSpineIndex {
                // Honor a pending bookmark jump instead of the raw requested page.
                pendingBookmarkNavigation = nil
                let pages = max(1, totalPagesPerSpine[targetSpineIndex])
                webView.alpha = 1
                scrollToBookmark(pending, in: webView, pages: pages)
            } else {
                // Chapter is already laid out, but the warm webview still shows its previous
                // page. Scroll to the target first, then reveal, so we don't flash the old page
                // (e.g. jumping back to a chapter briefly showed page 1 before the last page).
                webView.alpha = 0
                scrollToPage(in: webView, pageIndex: pageIndex) {
                    webView.alpha = 1
                }
            }
        }
        return pageVC
    }

    // Builds a reader webview with reader gesture/appearance config.
    private func makeReaderWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.navigationDelegate = self
        let webTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleReaderTap))
        webTapGesture.cancelsTouchesInView = false
        webTapGesture.delegate = self
        webView.addGestureRecognizer(webTapGesture)
        return webView
    }

    // Called from a discarded PageContentViewController: return its webview to the warm pool.
    func recycleWebView(_ webView: WKWebView) {
        webView.removeFromSuperview()
        if !idleWebViews.contains(webView) {
            idleWebViews.append(webView)
        }
        // Cap the pool so memory stays bounded; evict the oldest warm webviews.
        while idleWebViews.count > 4 {
            let evicted = idleWebViews.removeFirst()
            webViewChapter.removeValue(forKey: ObjectIdentifier(evicted))
            webViewTargetPage.removeValue(forKey: ObjectIdentifier(evicted))
            readyWebViews.remove(ObjectIdentifier(evicted))
        }
    }

    // Drops cached layouts (settings/theme/size changed) so webviews reload with new state.
    private func invalidateWebViewPool() {
        idleWebViews.removeAll()
        webViewChapter.removeAll()
        webViewTargetPage.removeAll()
        readyWebViews.removeAll()
        // Page counts depend on the same layout, so recompute the book's total.
        schedulePrecompute()
    }

    // Debounced restart of the offscreen pagination pass (settings can change rapidly).
    private func schedulePrecompute() {
        precomputeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startPrecompute() }
        precomputeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // Loads every chapter offscreen, paginates it, and records its page count.
    private func startPrecompute() {
        guard !spineItems.isEmpty, baseURL != nil else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let webView: WKWebView
        if let existing = precomputeWebView {
            webView = existing
        } else {
            webView = makeReaderWebView()
            webView.isUserInteractionEnabled = false
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(webView, at: 0)
            precomputeWebView = webView
        }
        webView.alpha = 0
        webView.frame = bounds
        precomputeIndex = 0
        loadNextPrecomputeChapter()
    }

    private func loadNextPrecomputeChapter() {
        guard let webView = precomputeWebView, let baseURL = baseURL else { return }
        while precomputeIndex < spineItems.count {
            let url = baseURL.appendingPathComponent(spineItems[precomputeIndex].href)
            if FileManager.default.fileExists(atPath: url.path) {
                webView.loadFileURL(url, allowingReadAccessTo: baseURL)
                return
            }
            precomputeIndex += 1
        }
        // Reached the end: tear down the offscreen webview and refresh the label.
        precomputeWebView?.removeFromSuperview()
        precomputeWebView = nil
        updatePageLabel()
    }

    private func showLoadErrorAndReturnToLibrary(message: String) {
        let alert = UIAlertController(title: "Unable to Open EPUB", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Back", style: .default) { _ in
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
    
    // Keep chapter loads inside the reader; route taps on external links (http/https/mailto/tel)
    // out to the system so they can't hijack the reading WebView with no way back.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased()
        // File loads (chapters, in-book anchors) and blank pages stay in the reader.
        if scheme == "file" || scheme == "about" || scheme == nil {
            decisionHandler(.allow)
            return
        }
        // Anything else is an outbound link: hand it to the OS, never the reading WebView.
        if navigationAction.navigationType == .linkActivated
            || scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel" {
            decisionHandler(.cancel)
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            return
        }
        decisionHandler(.allow)
    }

    // The WebKit content process can be killed under memory pressure, leaving a blank page.
    // Reload the chapter the crashed webview was showing so the reader recovers on its own.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let id = ObjectIdentifier(webView)
        readyWebViews.remove(id)
        guard let baseURL = baseURL,
              let spineIndex = webViewChapter[id],
              spineIndex >= 0, spineIndex < spineItems.count else { return }
        let chapterURL = baseURL.appendingPathComponent(spineItems[spineIndex].href)
        guard FileManager.default.fileExists(atPath: chapterURL.path) else { return }
        webView.loadFileURL(chapterURL, allowingReadAccessTo: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === precomputeWebView {
            webView.evaluateJavaScript(renderingJS(forSpineIndex: precomputeIndex)) { _, _ in
                webView.evaluateJavaScript("(window.getTotalPages ? window.getTotalPages() : 1)") { result, _ in
                    let pages = ((result as? Int).flatMap { $0 > 0 ? $0 : nil }) ?? 1
                    if self.precomputeIndex >= 0, self.precomputeIndex < self.totalPagesPerSpine.count {
                        self.totalPagesPerSpine[self.precomputeIndex] = pages
                    }
                    self.updatePageLabel()
                    self.precomputeIndex += 1
                    self.loadNextPrecomputeChapter()
                }
            }
            return
        }
        // Prefer the target captured at creation; the VC may not be attached yet when pre-fetched.
        let id = ObjectIdentifier(webView)
        let pageVC = self.findPageViewController(for: webView)
        let spineIndex = self.webViewChapter[id] ?? pageVC?.spineIndex ?? self.currentSpineIndex
        webView.evaluateJavaScript(renderingJS(forSpineIndex: spineIndex)) { _, _ in
            let targetPage = self.webViewTargetPage[id] ?? pageVC?.targetPageIndex ?? self.currentPage
            self.webViewChapter[id] = spineIndex
            self.readyWebViews.insert(id)
            self.applySavedHighlights(to: webView)
            self.calculateTotalPages(for: webView, spineIndex: spineIndex, requestedPage: targetPage)
        }
    }

    private func findPageViewController(for webView: WKWebView) -> PageContentViewController? {
        if let currentVC = pageViewController.viewControllers?.first as? PageContentViewController,
           currentVC.webView == webView {
            return currentVC
        }
        for child in pageViewController.children {
            if let vc = child as? PageContentViewController, vc.webView == webView {
                return vc
            }
        }
        return nil
    }

    private func isVisibleWebView(_ webView: WKWebView) -> Bool {
        return (pageViewController.viewControllers?.first as? PageContentViewController)?.webView == webView
    }
    
    private func calculateTotalPages(for webView: WKWebView, spineIndex: Int, requestedPage: Int) {
        webView.evaluateJavaScript("(window.getTotalPages ? window.getTotalPages() : 1)") { (totalPages, error) in
            let pages = ((totalPages as? Int).flatMap { $0 > 0 ? $0 : nil }) ?? 1
            self.totalPagesPerSpine[spineIndex] = pages

            // If we're opening a highlight in this spine, scroll to its exact page once paginated.
            if let pending = self.pendingHighlightNavigation, pending.spineIndex == spineIndex, self.isVisibleWebView(webView) {
                self.pendingHighlightNavigation = nil
                self.scrollToHighlight(pending, in: webView, pages: pages)
                return
            }
            // Same for a pending bookmark jump.
            if let pending = self.pendingBookmarkNavigation, pending.spineIndex == spineIndex, self.isVisibleWebView(webView) {
                self.pendingBookmarkNavigation = nil
                self.scrollToBookmark(pending, in: webView, pages: pages)
                return
            }

            let targetPage = min(max(0, requestedPage), pages - 1)
            self.scrollToPage(in: webView, pageIndex: targetPage) {
                webView.alpha = 1
            }
            if self.isVisibleWebView(webView) {
                self.currentSpineIndex = spineIndex
                self.currentPage = targetPage
                self.totalPages = pages
                self.updatePageLabel()
                if !self.didScheduleInitialPrecompute {
                    self.didScheduleInitialPrecompute = true
                    self.schedulePrecompute()
                }
            }
        }
    }

    // Scrolls an already-paginated webview to a highlight's exact page and syncs reader state.
    private func scrollToHighlight(_ highlight: Highlight, in webView: WKWebView, pages: Int) {
        computeHighlightPage(in: webView, highlight: highlight) { computed in
            var target = computed
            if target < 0 {
                let rel = min(max(highlight.relativePosition, 0), 1)
                target = Int((rel * Double(pages)).rounded(.down))
            }
            target = min(max(0, target), pages - 1)
            self.scrollToPage(in: webView, pageIndex: target) {
                webView.alpha = 1
            }
            // Keep the page VC's index in sync so swipes step from the highlight's page.
            if let vc = self.findPageViewController(for: webView) {
                vc.pageIndex = target
                vc.targetPageIndex = target
                // Re-anchor so the pager drops stale neighbors cached at the old index.
                self.pageViewController.setViewControllers([vc], direction: .forward, animated: false)
            }
            self.currentSpineIndex = highlight.spineIndex
            self.currentPage = target
            self.totalPages = pages
            self.updatePageLabel()
        }
    }

    // Computes the exact column/page index of a highlight from its stored text offset.
    private func computeHighlightPage(in webView: WKWebView, highlight: Highlight, completion: @escaping (Int) -> Void) {
        computePage(forOffset: highlight.startOffset ?? -1, length: max(1, highlight.range.length),
                    in: webView, completion: completion)
    }

    // Maps a UTF-16 text offset in the chapter's textContent to its current column/page index.
    // Returns -1 when the offset is invalid or can't be located. Font-size independent, so it
    // gives the exact page after repagination.
    private func computePage(forOffset start: Int, length rawLength: Int, in webView: WKWebView, completion: @escaping (Int) -> Void) {
        guard start >= 0 else { completion(-1); return }
        let length = max(1, rawLength)
        let js = """
        (function() {
            var doc = window.document;
            var body = doc.body;
            if (!body) return -1;
            var rtl = \(isRTL);
            function locate(offset) {
                var walker = doc.createTreeWalker(body, NodeFilter.SHOW_TEXT, null, false);
                var total = 0, node;
                while (node = walker.nextNode()) {
                    var len = node.textContent.length;
                    if (total + len >= offset) return { node: node, offset: offset - total };
                    total += len;
                }
                return null;
            }
            var pageW = body.clientWidth || 1;
            var total = Math.max(1, Math.round(body.scrollWidth / pageW));
            var t = locate(\(start));
            if (!t) return -1;
            var range = doc.createRange();
            var endOff = Math.min(t.node.textContent.length, t.offset + \(length));
            range.setStart(t.node, t.offset);
            range.setEnd(t.node, endOff);
            var prev = body.scrollLeft;
            body.scrollLeft = 0;
            var r = range.getBoundingClientRect();
            var b = body.getBoundingClientRect();
            var cs = window.getComputedStyle(body);
            var originLeft = b.left + (body.clientLeft || 0) + (parseFloat(cs.paddingLeft) || 0);
            var x = r.left - originLeft;
            body.scrollLeft = prev;
            // RTL columns run leftward from page 0, so the element's x is negative for later pages.
            var page = rtl ? Math.floor((-x + 1) / pageW) : Math.floor((x + 1) / pageW);
            if (page < 0) page = 0;
            if (page > total - 1) page = total - 1;
            return page;
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            completion((result as? Int) ?? -1)
        }
    }
    
    private func readerThemeJSObject() -> String {
        let backgroundColor = UserDefaults.standard.string(forKey: "backgroundColor") ?? "#FFFFFF"
        let textColor = UserDefaults.standard.string(forKey: "textColor") ?? "#000000"
        let darkBackground = UserDefaults.standard.string(forKey: "darkBackgroundColor") ?? "#000000"
        let darkText = UserDefaults.standard.string(forKey: "darkTextColor") ?? "#FFFFFF"
        let fontFamily = UserDefaults.standard.string(forKey: "fontFamily") ?? "Georgia"
        let fontSize = UserDefaults.standard.integer(forKey: "fontSize") > 0 ? UserDefaults.standard.integer(forKey: "fontSize") : 16
        let fontWeight = UserDefaults.standard.string(forKey: "fontWeight") ?? "normal"
        let lineHeight = UserDefaults.standard.object(forKey: "lineHeight") != nil ? UserDefaults.standard.double(forKey: "lineHeight") : 1.6
        let letterSpacing = UserDefaults.standard.double(forKey: "letterSpacing") * 0.05
        let wordSpacing = UserDefaults.standard.double(forKey: "wordSpacing") * 0.15
        let margins = UserDefaults.standard.double(forKey: "readerMargins") * 1.2
        let justify = UserDefaults.standard.bool(forKey: "justifyText")
        let isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        let bg = isDarkMode ? darkBackground : backgroundColor
        let color = isDarkMode ? darkText : textColor
        return "{ fontFamily: '\(fontFamily)', fontSize: \(fontSize), fontWeight: '\(fontWeight)', color: '\(color)', bg: '\(bg)', lineHeight: \(lineHeight), letterSpacing: \(letterSpacing), wordSpacing: \(wordSpacing), margins: \(margins), justify: \(justify) }"
    }

    private func applySettings(to webView: WKWebView) {
        let themeJS = "window.setReaderTheme && window.setReaderTheme(\(readerThemeJSObject())); 0;"
        webView.evaluateJavaScript(themeJS) { _, error in
            if let error = error {
                print("Error applying settings: \(error)")
            }
        }
    }

    private func readerPaginationJS() -> String {
        return """
        (function(){
            var theme = \(readerThemeJSObject());
            var rtl = \(isRTL);
            if (window.__rdr) { window.__rdr.theme = theme; return window.refreshLayout(); }
            window.__rdr = { currentPage: 0, theme: theme };
            var m = document.querySelector('meta[name=viewport]');
            if(!m){ m = document.createElement('meta'); m.setAttribute('name','viewport'); (document.head || document.documentElement).appendChild(m); }
            m.setAttribute('content','width=device-width, initial-scale=1, viewport-fit=cover');
            function baseCSS(){
                var t = window.__rdr.theme;
                var mg = (t.margins || 0);
                return 'html{margin:0 !important;padding:calc(env(safe-area-inset-top) + 50px) calc(env(safe-area-inset-right) + '+(24+mg)+'px) calc(env(safe-area-inset-bottom) + 120px) calc(env(safe-area-inset-left) + '+(24+mg)+'px) !important;height:100% !important;overflow:hidden !important;box-sizing:border-box !important;background:'+t.bg+' !important;-webkit-text-size-adjust:100% !important;}' +
                    'body{margin:0 !important;padding:0 !important;box-sizing:border-box !important;height:100% !important;overflow:hidden !important;direction:'+(rtl?'rtl':'ltr')+' !important;background:'+t.bg+' !important;color:'+t.color+' !important;font-family:'+t.fontFamily+',Georgia,serif !important;font-size:'+t.fontSize+'px !important;font-weight:'+(t.fontWeight||'normal')+' !important;line-height:'+t.lineHeight+' !important;letter-spacing:'+(t.letterSpacing||0)+'px !important;word-spacing:'+(t.wordSpacing||0)+'px !important;text-align:'+(t.justify?'justify':(rtl?'right':'left'))+' !important;}' +
                    'img,svg,video{max-height:100% !important;height:auto !important;}' +
                    'p{orphans:2;widows:2;}';
            }
            function ensureStyle(){
                var s = document.getElementById('__rdrStyle');
                if(!s){ s = document.createElement('style'); s.id = '__rdrStyle'; (document.head || document.documentElement).appendChild(s); }
                return s;
            }
            function injectStyle(){
                ensureStyle().textContent = baseCSS();
                var b = document.body; if(!b) return;
                var w = b.clientWidth, h = b.clientHeight;
                b.style.setProperty('-webkit-column-width', w + 'px', 'important');
                b.style.setProperty('column-width', w + 'px', 'important');
                b.style.setProperty('-webkit-column-gap', '0', 'important');
                b.style.setProperty('column-gap', '0', 'important');
                b.style.setProperty('-webkit-column-fill', 'auto', 'important');
                b.style.setProperty('column-fill', 'auto', 'important');
                b.style.setProperty('max-width', w + 'px', 'important');
                b.style.setProperty('height', h + 'px', 'important');
                b.scrollLeft = 0;
            }
            function pageWidth(){ return document.body ? document.body.clientWidth : 1; }
            function totalPages(){ var b = document.body; if(!b) return 1; return Math.max(1, Math.round(b.scrollWidth / pageWidth())); }
            window.getTotalPages = function(){ return totalPages(); };
            window.getCurrentPage = function(){ return window.__rdr.currentPage; };
            // In RTL the scroll container runs the other way: page i sits at negative scrollLeft.
            window.setPageIndex = function(i){ window.__rdr.currentPage = i; if(document.body){ document.body.scrollLeft = (rtl ? -1 : 1) * i * pageWidth(); } return totalPages(); };
            window.refreshLayout = function(){ injectStyle(); window.setPageIndex(window.__rdr.currentPage || 0); return totalPages(); };
            window.setReaderTheme = function(t){ window.__rdr.theme = t; injectStyle(); window.setPageIndex(window.__rdr.currentPage || 0); return totalPages(); };
            injectStyle();
            window.setPageIndex(0);
            return totalPages();
        })();
        """
    }

    private func isFixedLayoutSpine(_ index: Int) -> Bool {
        return index >= 0 && index < spineItems.count && spineItems[index].isFixedLayout
    }

    // A fully fixed-layout book uses the spread pager (a "spread" may be one or two pages).
    private var isFixedLayoutBook: Bool {
        let linear = spineItems.filter { $0.linear }
        return !linear.isEmpty && linear.allSatisfy { $0.isFixedLayout }
    }

    private var isLandscape: Bool { view.bounds.width > view.bounds.height }

    // Right-to-left reading (Arabic/Hebrew, RTL manga) per the spine's page-progression-direction.
    private var isRTL: Bool { (bookMetadata?.pageProgressionDirection ?? "ltr") == "rtl" }

    // Whether pages should pair into two-up spreads right now, per rendition:spread × orientation.
    private func spreadPairingActive() -> Bool {
        switch (bookMetadata?.renditionSpread ?? "auto") {
        case "none": return false
        case "both": return true
        case "portrait": return !isLandscape
        default: return isLandscape // "auto" / "landscape"
        }
    }

    // Builds the ordered list of spreads from the linear fixed-layout spine, honoring
    // page-spread-left/right/center and pairing consecutive pages when active.
    private func computeSpreads() -> [Spread] {
        let indices = (0..<spineItems.count).filter { spineItems[$0].linear }
        guard spreadPairingActive() else { return indices.map { Spread(left: $0, right: nil) } }
        var result: [Spread] = []
        var i = 0
        var isFirst = true
        while i < indices.count {
            let idx = indices[i]
            let item = spineItems[idx]
            // Cover / explicit-center pages stand alone; the first page is solo unless it's a left.
            if item.pageSpread == .center || (isFirst && item.pageSpread != .left) {
                result.append(Spread(left: idx, right: nil)); i += 1; isFirst = false; continue
            }
            isFirst = false
            if i + 1 < indices.count {
                let next = spineItems[indices[i + 1]]
                if next.pageSpread == .center || next.pageSpread == .left {
                    result.append(Spread(left: idx, right: nil)); i += 1   // no valid right partner
                } else {
                    result.append(Spread(left: idx, right: indices[i + 1])); i += 2
                }
            } else {
                result.append(Spread(left: idx, right: nil)); i += 1
            }
        }
        return result
    }

    private func rebuildSpreads() { spreads = computeSpreads() }

    private func spreadIndex(containingSpine spineIndex: Int) -> Int? {
        return spreads.firstIndex { $0.left == spineIndex || $0.right == spineIndex }
    }

    // Acquires a webview showing a fixed-layout spine item, reusing the warm pool. fixedLayoutJS
    // runs on didFinish and fits the page to whatever bounds the webview ends up with (full or half).
    private func acquireFXLWebView(forSpine spineIndex: Int) -> WKWebView? {
        guard let baseURL = baseURL, spineIndex >= 0, spineIndex < spineItems.count else { return nil }
        let chapterURL = baseURL.appendingPathComponent(spineItems[spineIndex].href)
        guard FileManager.default.fileExists(atPath: chapterURL.path) else { return nil }
        let webView: WKWebView
        if let idx = idleWebViews.firstIndex(where: {
            webViewChapter[ObjectIdentifier($0)] == spineIndex && readyWebViews.contains(ObjectIdentifier($0))
        }) {
            // Already-rendered page: reuse and just re-fit (bounds may differ, e.g. full vs half).
            webView = idleWebViews.remove(at: idx)
            webView.alpha = 1
            webView.evaluateJavaScript("if(window.refreshLayout){window.refreshLayout();}0;")
        } else if let shell = idleWebViews.popLast() {
            webView = shell
            readyWebViews.remove(ObjectIdentifier(webView))
            webView.alpha = 0
            webView.loadFileURL(chapterURL, allowingReadAccessTo: baseURL)
        } else {
            webView = makeReaderWebView()
            webView.alpha = 0
            webView.loadFileURL(chapterURL, allowingReadAccessTo: baseURL)
        }
        webViewChapter[ObjectIdentifier(webView)] = spineIndex
        webViewTargetPage[ObjectIdentifier(webView)] = 0
        return webView
    }

    // Builds a page VC for a spread (one or two fixed-layout pages).
    private func createSpreadViewController(spreadIndex index: Int) -> PageContentViewController? {
        guard index >= 0, index < spreads.count else { return nil }
        let spread = spreads[index]
        // In RTL the earlier-read page sits on the right, so swap the two panes visually.
        if isRTL, let secondSpine = spread.right {
            guard let visualLeftWV = acquireFXLWebView(forSpine: secondSpine),
                  let visualRightWV = acquireFXLWebView(forSpine: spread.left) else { return nil }
            return PageContentViewController(webView: visualLeftWV, pageIndex: 0, spineIndex: secondSpine,
                                             delegate: self, rightWebView: visualRightWV, rightSpineIndex: spread.left)
        }
        guard let leftWV = acquireFXLWebView(forSpine: spread.left) else { return nil }
        let rightWV = spread.right.flatMap { acquireFXLWebView(forSpine: $0) }
        return PageContentViewController(webView: leftWV, pageIndex: 0, spineIndex: spread.left,
                                         delegate: self, rightWebView: rightWV, rightSpineIndex: spread.right)
    }

    // Jumps a fixed-layout book to the spread containing the given spine item (TOC/bookmark nav).
    private func showSpine(_ spineIndex: Int) {
        guard !spreads.isEmpty else { return }
        let si = spreadIndex(containingSpine: spineIndex) ?? 0
        guard let vc = createSpreadViewController(spreadIndex: si) else { return }
        currentSpineIndex = spreads[si].left
        currentPage = 0
        pageViewController.setViewControllers([vc], direction: .forward, animated: false)
        updatePageLabel()
    }

    // Chooses the right renderer for a spine item: fit-to-screen for fixed-layout, column
    // pagination for reflowable.
    private func renderingJS(forSpineIndex index: Int) -> String {
        return isFixedLayoutSpine(index) ? fixedLayoutJS() : readerPaginationJS()
    }

    // Renders a pre-paginated (fixed-layout) page: reads its authored viewport size and scales
    // the whole page to fit the screen, centered/letterboxed. One spine item = one page.
    private func fixedLayoutJS() -> String {
        return """
        (function(){
            var theme = \(readerThemeJSObject());
            function ensureStyle(){
                var s = document.getElementById('__fxlStyle');
                if(!s){ s = document.createElement('style'); s.id='__fxlStyle'; (document.head||document.documentElement).appendChild(s); }
                return s;
            }
            function applyFrame(){
                ensureStyle().textContent =
                    'html{margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:'+theme.bg+'!important;}';
            }
            // The authored page size — read BEFORE we override the viewport meta below.
            function authoredSize(){
                var vp = document.querySelector('meta[name=viewport]');
                if(vp){
                    var c = vp.getAttribute('content')||'';
                    var w = /width\\s*=\\s*(\\d+(?:\\.\\d+)?)/i.exec(c);
                    var h = /height\\s*=\\s*(\\d+(?:\\.\\d+)?)/i.exec(c);
                    if(w && h) return { w: parseFloat(w[1]), h: parseFloat(h[1]) };
                }
                var svg = document.querySelector('svg');
                if(svg){
                    var vb = svg.getAttribute('viewBox');
                    if(vb){ var p = vb.split(/[\\s,]+/); if(p.length===4) return { w: parseFloat(p[2]), h: parseFloat(p[3]) }; }
                    var sw = parseFloat(svg.getAttribute('width')), sh = parseFloat(svg.getAttribute('height'));
                    if(sw && sh) return { w: sw, h: sh };
                }
                var img = document.querySelector('img');
                if(img && img.naturalWidth && img.naturalHeight) return { w: img.naturalWidth, h: img.naturalHeight };
                return null;
            }
            // Neutralize the page's own viewport so measurements are in real screen pixels,
            // not the authored coordinate space (which is what caused the crop).
            function overrideViewport(){
                var m = document.querySelector('meta[name=viewport]');
                if(!m){ m = document.createElement('meta'); m.setAttribute('name','viewport'); (document.head||document.documentElement).appendChild(m); }
                m.setAttribute('content','width=device-width, initial-scale=1, viewport-fit=cover');
            }
            function fit(){
                var b = document.body; if(!b) return;
                var s = window.__fxlSize;
                if(!s || !s.w || !s.h){ s = { w: Math.max(1, b.scrollWidth), h: Math.max(1, b.scrollHeight) }; }
                var availW = document.documentElement.clientWidth || window.innerWidth;
                var availH = document.documentElement.clientHeight || window.innerHeight;
                var scale = Math.min(availW / s.w, availH / s.h);
                if(!isFinite(scale) || scale <= 0) scale = 1;
                b.style.setProperty('margin','0','important');
                b.style.setProperty('position','absolute','important');
                b.style.setProperty('width', s.w+'px','important');
                b.style.setProperty('height', s.h+'px','important');
                b.style.setProperty('transform-origin','top left','important');
                b.style.setProperty('transform','scale('+scale+')','important');
                b.style.setProperty('left', Math.max(0,(availW - s.w*scale)/2)+'px','important');
                b.style.setProperty('top', Math.max(0,(availH - s.h*scale)/2)+'px','important');
            }
            if(window.__fxl){ theme = \(readerThemeJSObject()); applyFrame(); fit(); return 1; }
            window.__fxl = true;
            window.__fxlSize = authoredSize();
            overrideViewport();
            applyFrame();
            fit();
            requestAnimationFrame(fit);
            // Re-fit once late-loading images report their size, and on rotation/resize.
            window.addEventListener('load', function(){ if(!window.__fxlSize){ window.__fxlSize = authoredSize(); } fit(); });
            window.addEventListener('resize', fit);
            window.getTotalPages = function(){ return 1; };
            window.getCurrentPage = function(){ return 0; };
            window.setPageIndex = function(i){ return 1; };
            window.refreshLayout = function(){ applyFrame(); fit(); return 1; };
            window.setReaderTheme = function(t){ theme = t; applyFrame(); fit(); return 1; };
            return 1;
        })();
        """
    }

    func scrollToPage(in webView: WKWebView, pageIndex: Int, completion: (() -> Void)? = nil) {
        webView.evaluateJavaScript("if(window.setPageIndex){window.setPageIndex(\(pageIndex));}0;") { result, error in
            if let error = error {
                print("Error setting page index: \(error)")
            }
            completion?()
        }
    }

    private func updatePageLabel() {
        // Page counts aren't known until the async parse populates totalPagesPerSpine.
        guard !totalPagesPerSpine.isEmpty else {
            pageLabel.text = ""
            return
        }
        let globalPageNumber = getCurrentGlobalPageNumber()
        let totalGlobalPages = getTotalGlobalPages()
        pageLabel.text = pageLabelShowsTotal ? "\(globalPageNumber) of \(totalGlobalPages)" : "\(globalPageNumber)"
        updateBookmarkButtonState()
    }

    private func updatePanelProgress() {
        let percent = Int((Double(getCurrentGlobalPageNumber()) / Double(max(1, getTotalGlobalPages()))) * 100)
        panelHeaderLabel.text = "Contents · \(min(100, max(0, percent)))%"
    }
    
    private func getCurrentGlobalPageNumber() -> Int {
        var globalPage = 1
        let upTo = min(currentSpineIndex, totalPagesPerSpine.count)
        for i in 0..<upTo where isLinearSpine(i) {
            globalPage += totalPagesPerSpine[i]
        }
        globalPage += currentPage
        return globalPage
    }

    // Non-linear spine items don't participate in the page-count sequence.
    private func isLinearSpine(_ index: Int) -> Bool {
        return index < spineItems.count ? spineItems[index].linear : true
    }

    private func getTotalGlobalPages() -> Int {
        var total = 0
        for i in 0..<totalPagesPerSpine.count where isLinearSpine(i) {
            total += totalPagesPerSpine[i]
        }
        return total
    }
    
    // MARK: - UIPageViewController DataSource
    // Nearest spine index in the given direction that is part of the primary reading order
    // (linear="no" items are skipped by page turns). Returns nil at the ends.
    private func nextLinearSpineIndex(after index: Int) -> Int? {
        var i = index + 1
        while i < spineItems.count { if spineItems[i].linear { return i }; i += 1 }
        return nil
    }
    private func previousLinearSpineIndex(before index: Int) -> Int? {
        var i = index - 1
        while i >= 0 { if spineItems[i].linear { return i }; i -= 1 }
        return nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? PageContentViewController else { return nil }

        // Fixed-layout books step by spread, not by column page.
        if isFixedLayoutBook {
            guard let si = spreadIndex(containingSpine: current.spineIndex), si > 0 else { return nil }
            return createSpreadViewController(spreadIndex: si - 1)
        }

        if current.pageIndex > 0 {
            // Previous page in same chapter
            let previousPage = current.pageIndex - 1
            return createPageViewController(for: previousPage, spineIndex: current.spineIndex)
        } else if let previousSpine = previousLinearSpineIndex(before: current.spineIndex) {
            // Move to previous linear chapter, last page
            let lastPage = max(0, totalPagesPerSpine[previousSpine] - 1)
            return createPageViewController(for: lastPage, spineIndex: previousSpine)
        }
        return nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? PageContentViewController else { return nil }

        // Fixed-layout books step by spread, not by column page.
        if isFixedLayoutBook {
            guard let si = spreadIndex(containingSpine: current.spineIndex), si < spreads.count - 1 else { return nil }
            return createSpreadViewController(spreadIndex: si + 1)
        }

        if current.pageIndex < totalPagesPerSpine[current.spineIndex] - 1 {
            // Next page in same chapter
            let nextPage = current.pageIndex + 1
            return createPageViewController(for: nextPage, spineIndex: current.spineIndex)
        } else if let nextSpine = nextLinearSpineIndex(after: current.spineIndex) {
            // Move to next linear chapter, first page
            return createPageViewController(for: 0, spineIndex: nextSpine)
        }
        return nil
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let current = pageViewController.viewControllers?.first as? PageContentViewController {
            currentSpineIndex = current.spineIndex
            currentPage = current.pageIndex
            totalPages = totalPagesPerSpine[currentSpineIndex]
            updatePageLabel()
            saveReadingPosition()
        }
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == tocTableView { 
            print("TOC table view requesting \(tocItems.count) rows")
            return tocItems.count 
        }
        if tableView == highlightsTableView { return highlights.count }
        if tableView == bookmarksTableView { return bookmarks.count }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == tocTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "TOCCell", for: indexPath)
            let tocItem = tocItems[indexPath.row]
            cell.textLabel?.text = tocItem.label
            cell.textLabel?.numberOfLines = 0
            cell.accessoryType = .disclosureIndicator
            print("TOC cell configured: \(tocItem.label)")
            return cell
        } else if tableView == highlightsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "HighlightCell", for: indexPath)
            let highlight = highlights[indexPath.row]
            cell.textLabel?.text = highlight.displayText
            cell.textLabel?.numberOfLines = 0
            
            // Set background color to match the highlight color
            switch highlight.color {
            case "yellow":
                cell.backgroundColor = UIColor.yellow.withAlphaComponent(0.3)
            case "green":
                cell.backgroundColor = UIColor.green.withAlphaComponent(0.3)
            case "pink":
                cell.backgroundColor = UIColor.systemPink.withAlphaComponent(0.3)
            default:
                cell.backgroundColor = UIColor.yellow.withAlphaComponent(0.3)
            }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkCell", for: indexPath)
            let bookmark = bookmarks[indexPath.row]
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            cell.textLabel?.text = "Page \(bookmark.pageNumber + 1) - \(formatter.string(from: bookmark.date))"
            cell.textLabel?.numberOfLines = 0
            return cell
        }
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == tocTableView {
            navigate(toTOCItem: tocItems[indexPath.row])
        } else if tableView == highlightsTableView {
            let highlight = highlights[indexPath.row]
            if isFixedLayoutBook {
                showSpine(highlight.spineIndex)
                toggleHighlights()
            } else {
                currentSpineIndex = highlight.spineIndex

                // Navigate to the spine first
                if let newPage = createPageViewController(for: 0, spineIndex: currentSpineIndex) {
                    pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
                }

                // Find the correct page after the content loads
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.findAndNavigateToHighlight(highlight)
                }

                toggleHighlights()
            }
        } else {
            openBookmark(bookmarks[indexPath.row])
            toggleBookmarks()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    private func findAndNavigateToHighlight(_ highlight: Highlight) {
        guard let currentPageVC = pageViewController.viewControllers?.first as? PageContentViewController else {
            return
        }
        
        let webView = currentPageVC.webView
        let storedStart = highlight.startOffset ?? -1
        let findHighlightJS = """
        (function() {
            var document = window.document;
            var textContent = document.body.textContent || document.body.innerText;
            var searchText = '\(highlight.text.replacingOccurrences(of: "'", with: "\\'"))';
            var context = '\(highlight.textContext.replacingOccurrences(of: "'", with: "\\'"))';
            var storedStart = \(storedStart);

            // Prefer the exact stored offset; fall back to context/text search for legacy highlights.
            var foundIndex = (storedStart >= 0 && storedStart <= textContent.length) ? storedStart : -1;
            if (foundIndex === -1 && context.length > 0) {
                var contextIndex = textContent.indexOf(context);
                if (contextIndex !== -1) {
                    var relativeIndexInContext = context.indexOf(searchText);
                    if (relativeIndexInContext !== -1) {
                        foundIndex = contextIndex + relativeIndexInContext;
                    }
                }
            }
            
            if (foundIndex === -1) {
                var estimatedIndex = Math.floor(textContent.length * \(highlight.relativePosition));
                var searchWindow = 200;
                var startSearch = Math.max(0, estimatedIndex - searchWindow);
                var endSearch = Math.min(textContent.length, estimatedIndex + searchWindow);
                var searchArea = textContent.substring(startSearch, endSearch);
                var localIndex = searchArea.indexOf(searchText);
                if (localIndex !== -1) {
                    foundIndex = startSearch + localIndex;
                }
            }
            
            if (foundIndex === -1) {
                foundIndex = textContent.indexOf(searchText);
            }
            
            if (foundIndex !== -1) {
                // Calculate which page this text would be on
                var totalPages = window.getTotalPages();
                var textPerPage = textContent.length / totalPages;
                var estimatedPage = Math.floor(foundIndex / textPerPage);
                return Math.max(0, Math.min(estimatedPage, totalPages - 1));
            }
            
            return 0;
        })();
        """
        
        webView.evaluateJavaScript(findHighlightJS) { result, error in
            if let pageNumber = result as? Int {
                self.currentPage = pageNumber
                self.scrollToPage(in: webView, pageIndex: pageNumber) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.updatePageLabel()
                    }
                }
            }
        }
    }
}


