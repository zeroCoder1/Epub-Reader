//
//  ReaderViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//

import UIKit
import WebKit
import SwiftSoup

class ReaderViewController: UIViewController, WKNavigationDelegate, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UITableViewDataSource, UITableViewDelegate {
    private var pageViewController: UIPageViewController!
    private let epubURL: URL
    private var spineItems: [EPUBSpineItem] = []
    private var currentSpineIndex = 0
    private var currentPage = 0
    private var totalPages = 0
    private var totalPagesPerSpine: [Int] = [] // Track pages per chapter
    private var baseURL: URL?
    private var isPageCurlEnabled = UserDefaults.standard.bool(forKey: "isPageCurlEnabled")
    private let pageLabel = UILabel()
    private var bookmarks: [Bookmark] = []
    private var highlights: [Highlight] = []
    private let tocTableView = UITableView()
    private let highlightsTableView = UITableView()
    private var tocItems: [EPUBTOCItem] = []
    private let bookmarksTableView = UITableView()
    
    init(epubURL: URL) {
        self.epubURL = epubURL
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupNavigationBar()
        setupPageLabel()
        
        // Load data first before parsing EPUB
        loadHighlights()
        loadBookmarks()
        
        parseAndLoadEPUB()
        setupPageViewController()
        setupMenuController()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupTOCView()
        setupHighlightsView()
        setupBookmarksView()
        // Data already loaded in viewDidLoad, just reload table views
        highlightsTableView.reloadData()
        bookmarksTableView.reloadData()
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
    
    func setupMenuController() {
        // Add custom menu items for highlighting and bookmarking
        let highlightMenuItem = UIMenuItem(title: "Highlight", action: #selector(highlightSelectedText))
        let bookmarkMenuItem = UIMenuItem(title: "Bookmark", action: #selector(bookmarkFromMenu))
        UIMenuController.shared.menuItems = [highlightMenuItem, bookmarkMenuItem]
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
            var selection = window.getSelection();
            if (selection.rangeCount > 0) {
                var range = selection.getRangeAt(0);
                var span = document.createElement('span');
                span.className = 'highlight';
                span.style.backgroundColor = '\(highlightColor)';
                span.style.color = 'black';
                
                var selectedText = selection.toString();
                
                // Get context around the selection for better matching
                var textContent = document.body.textContent || document.body.innerText;
                var selectedIndex = textContent.indexOf(selectedText);
                var contextStart = Math.max(0, selectedIndex - 50);
                var contextEnd = Math.min(textContent.length, selectedIndex + selectedText.length + 50);
                var textContext = textContent.substring(contextStart, contextEnd);
                
                // Calculate relative position in the document
                var relativePosition = selectedIndex / textContent.length;
                
                try {
                    range.surroundContents(span);
                    selection.removeAllRanges();
                    
                    // Return the highlighted data to Swift
                    return {
                        text: selectedText,
                        context: textContext,
                        position: relativePosition
                    };
                } catch(e) {
                    var contents = range.extractContents();
                    span.appendChild(contents);
                    range.insertNode(span);
                    selection.removeAllRanges();
                    
                    // Return the highlighted data to Swift
                    return {
                        text: selectedText,
                        context: textContext,
                        position: relativePosition
                    };
                }
            }
            return null;
        })();
        """
        
        webView.evaluateJavaScript(highlightJS) { result, error in
            if let result = result as? [String: Any],
               let text = result["text"] as? String,
               let context = result["context"] as? String,
               let position = result["position"] as? Double,
               !text.isEmpty {
                
                let highlight = Highlight(
                    spineIndex: self.currentSpineIndex,
                    pageNumber: self.currentPage,
                    text: text,
                    range: NSRange(location: 0, length: text.count),
                    color: highlightColor,
                    textContext: context,
                    relativePosition: position
                )
                
                self.highlights.append(highlight)
                self.saveHighlights()
                print("Highlight saved: \(text) with color: \(highlightColor)")
            }
        }
    }

    private func recreatePageViewController() {
        // Remove old page view controller
        pageViewController.willMove(toParent: nil)
        pageViewController.view.removeFromSuperview()
        pageViewController.removeFromParent()
        
        // Create new one with updated settings
        setupPageViewController()
    }

    private func setupPageViewController() {
        let style: UIPageViewController.TransitionStyle = isPageCurlEnabled ? .pageCurl : .scroll
        pageViewController = UIPageViewController(transitionStyle: style, navigationOrientation: .horizontal, options: nil)
        pageViewController.dataSource = self
        pageViewController.delegate = self
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.frame = view.bounds
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: pageLabel.topAnchor, constant: -10),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        // Load the initial page
        if let initialPage = createPageViewController(for: currentPage) {
            pageViewController.setViewControllers([initialPage], direction: .forward, animated: false)
        }
    }
    
    private func setupTOCView() {
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
            pageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            pageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        pageLabel.textAlignment = .center
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Highlights", style: .plain, target: self, action: #selector(toggleHighlights)),
            UIBarButtonItem(title: "Bookmarks", style: .plain, target: self, action: #selector(toggleBookmarks)),
            UIBarButtonItem(title: "TOC", style: .plain, target: self, action: #selector(toggleTOC))
        ]
    }
    

    @objc func bookmarkFromMenu() {
        addBookmark()
    }

    // Add bookmark
    @objc func addBookmark() {
        let bookmark = Bookmark(spineIndex: currentSpineIndex, pageNumber: currentPage, date: Date())
        bookmarks.append(bookmark)
        saveBookmarks()
        print("Bookmark added: \(bookmark)")
        
        // Show confirmation
        let alert = UIAlertController(title: "Bookmark Added", message: "Page bookmarked successfully", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // Save bookmarks to UserDefaults
    private func saveBookmarks() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(bookmarks) {
            UserDefaults.standard.set(encoded, forKey: "savedBookmarks")
            print("Bookmarks saved: \(bookmarks.count) total")
        }
    }

    // Load bookmarks from UserDefaults
    private func loadBookmarks() {
        if let savedBookmarks = UserDefaults.standard.object(forKey: "savedBookmarks") as? Data {
            let decoder = JSONDecoder()
            if let loadedBookmarks = try? decoder.decode([Bookmark].self, from: savedBookmarks) {
                bookmarks = loadedBookmarks
                print("Bookmarks loaded: \(bookmarks.count) total")
            }
        }
    }

    // Load highlights from UserDefaults
    private func loadHighlights() {
        if let savedHighlights = UserDefaults.standard.object(forKey: "savedHighlights") as? Data {
            let decoder = JSONDecoder()
            if let loadedHighlights = try? decoder.decode([Highlight].self, from: savedHighlights) {
                highlights = loadedHighlights
                print("Highlights loaded: \(highlights.count) total")
            }
        }
    }

    // Save highlights to UserDefaults
    private func saveHighlights() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(highlights) {
            UserDefaults.standard.set(encoded, forKey: "savedHighlights")
            print("Highlights saved: \(highlights.count) total")
        }
    }

    // Apply saved highlights to a WebView
    private func applySavedHighlights(to webView: WKWebView) {
        let currentHighlights = highlights.filter { $0.spineIndex == currentSpineIndex }
        
        for (index, highlight) in currentHighlights.enumerated() {
            let highlightJS = """
            (function() {
                var textContent = document.body.textContent || document.body.innerText;
                var searchText = '\(highlight.text.replacingOccurrences(of: "'", with: "\\'"))';
                var context = '\(highlight.textContext.replacingOccurrences(of: "'", with: "\\'"))';
                
                // Try to find the text using context first
                var foundIndex = -1;
                if (context.length > 0) {
                    var contextIndex = textContent.indexOf(context);
                    if (contextIndex !== -1) {
                        var relativeIndexInContext = context.indexOf(searchText);
                        if (relativeIndexInContext !== -1) {
                            foundIndex = contextIndex + relativeIndexInContext;
                        }
                    }
                } else {
                    // Fallback: use relative position
                    var estimatedIndex = Math.floor(textContent.length * \(highlight.relativePosition));
                    var searchWindow = 200; // Search within 200 characters
                    var startSearch = Math.max(0, estimatedIndex - searchWindow);
                    var endSearch = Math.min(textContent.length, estimatedIndex + searchWindow);
                    var searchArea = textContent.substring(startSearch, endSearch);
                    var localIndex = searchArea.indexOf(searchText);
                    if (localIndex !== -1) {
                        foundIndex = startSearch + localIndex;
                    }
                }
                
                // Final fallback: simple indexOf
                if (foundIndex === -1) {
                    foundIndex = textContent.indexOf(searchText);
                }
                
                if (foundIndex !== -1) {
                    // Find the text node and apply highlighting
                    var walker = document.createTreeWalker(
                        document.body,
                        NodeFilter.SHOW_TEXT,
                        null,
                        false
                    );
                    
                    var currentIndex = 0;
                    var node;
                    while (node = walker.nextNode()) {
                        var nodeLength = node.textContent.length;
                        if (currentIndex + nodeLength > foundIndex) {
                            var localStart = foundIndex - currentIndex;
                            var localEnd = localStart + searchText.length;
                            
                            if (localEnd <= nodeLength) {
                                var range = document.createRange();
                                range.setStart(node, localStart);
                                range.setEnd(node, localEnd);
                                
                                var span = document.createElement('span');
                                span.style.backgroundColor = '\(highlight.color)';
                                span.style.color = 'black';
                                span.className = 'saved-highlight-\(index)';
                                span.setAttribute('data-highlight-id', '\(index)');
                                
                                try {
                                    range.surroundContents(span);
                                    return true;
                                } catch(e) {
                                    var contents = range.extractContents();
                                    span.appendChild(contents);
                                    range.insertNode(span);
                                    return true;
                                }
                            }
                        }
                        currentIndex += nodeLength;
                    }
                }
                return false;
            })();
            """
            
            webView.evaluateJavaScript(highlightJS) { success, error in
                if let error = error {
                    print("Error applying saved highlight: \(error)")
                } else if let success = success as? Bool, success {
                    print("Successfully applied highlight: \(highlight.text)")
                }
            }
        }
    }
    
    @objc private func toggleBookmarks() {
        bookmarksTableView.isHidden = !bookmarksTableView.isHidden
        tocTableView.isHidden = true
        highlightsTableView.isHidden = true
        bookmarksTableView.reloadData()
    }

    @objc private func toggleTOC() {
        tocTableView.isHidden = !tocTableView.isHidden
        highlightsTableView.isHidden = true
        bookmarksTableView.isHidden = true
        
        // Load TOC from HTML file if empty
        if tocItems.isEmpty {
            loadTOCFromHTML()
        }
        
        tocTableView.reloadData()
        print("TOC toggled, items count: \(tocItems.count)")
    }
    
    @objc private func toggleHighlights() {
        highlightsTableView.isHidden = !highlightsTableView.isHidden
        tocTableView.isHidden = true
        bookmarksTableView.isHidden = true
        highlightsTableView.reloadData()
    }

    private func parseAndLoadEPUB() {
        guard let (metadata, spine, toc, baseURL) = EPUBParser.parseEPUB(at: epubURL) else { return }
        title = metadata.title
        spineItems = spine
        tocItems = toc // Keep this for fallback
        self.baseURL = baseURL
        totalPagesPerSpine = Array(repeating: 1, count: spine.count)
        
        // Try to load TOC from HTML file
        loadTOCFromHTML()
    }
    
    private func loadTOCFromHTML() {
        guard let baseURL = baseURL else { return }
        
        let tocURL = baseURL.appendingPathComponent("OPS/toc.xhtml")
        
        do {
            let tocHTML = try String(contentsOf: tocURL)
            let doc = try SwiftSoup.parse(tocHTML)
            
            // Parse the TOC HTML - typically contains nav or ol/li structure
            var newTocItems: [EPUBTOCItem] = []
            
            // Try to find navigation elements (EPUB3 style)
            if let nav = try doc.select("nav").first() {
                let links = try nav.select("a")
                for link in links {
                    let href = try link.attr("href")
                    let label = try link.text()
                    if !href.isEmpty && !label.isEmpty {
                        newTocItems.append(EPUBTOCItem(label: label, href: href))
                    }
                }
            } else {
                // Fallback: look for any links in the document
                let links = try doc.select("a")
                for link in links {
                    let href = try link.attr("href")
                    let label = try link.text()
                    if !href.isEmpty && !label.isEmpty {
                        newTocItems.append(EPUBTOCItem(label: label, href: href))
                    }
                }
            }
            
            if !newTocItems.isEmpty {
                tocItems = newTocItems
                print("Loaded \(tocItems.count) TOC items from TOC.html")
            } else {
                print("No TOC items found in TOC.html, using existing TOC")
            }
            
        } catch {
            print("Error loading TOC.html: \(error)")
            // Keep existing tocItems as fallback
        }
    }
    
    private func createPageViewController(for pageIndex: Int) -> PageContentViewController? {
        guard let baseURL = baseURL, currentSpineIndex < spineItems.count else { return nil }
        
        // Create fresh WKWebViewConfiguration for each page
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = self
        webView.alpha = 0 // Hide initially to prevent flickering
        let htmlURL = baseURL.appendingPathComponent("OPS/\(spineItems[currentSpineIndex].href)")
        webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
        
        let pageVC = PageContentViewController(webView: webView, pageIndex: pageIndex, delegate: self)
        pageVC.targetPageIndex = pageIndex
        return pageVC
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applySettings(to: webView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.calculateTotalPages(for: webView)
            // Find the PageContentViewController that owns this webView and scroll to its target page
            if let pageVC = self.findPageViewController(for: webView) {
                self.scrollToPage(in: webView, pageIndex: pageVC.targetPageIndex) {
                    // Apply saved highlights after page is positioned and content is loaded
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.applySavedHighlights(to: webView)
                        // Show the web view after everything is ready
                        webView.alpha = 1
                    }
                }
            } else {
                // If not found, still apply highlights and show the web view
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.applySavedHighlights(to: webView)
                    webView.alpha = 1
                }
            }
        }
    }
    
    private func findPageViewController(for webView: WKWebView) -> PageContentViewController? {
        // Check current page view controller
        if let currentVC = pageViewController.viewControllers?.first as? PageContentViewController,
           currentVC.webView == webView {
            return currentVC
        }
        return nil
    }
    
    private func calculateTotalPages(for webView: WKWebView) {
        webView.evaluateJavaScript("window.getTotalPages()") { (totalPages, error) in
            if let pages = totalPages as? Int, pages > 0 {
                self.totalPagesPerSpine[self.currentSpineIndex] = pages
                self.totalPages = pages
                self.currentPage = min(self.currentPage, self.totalPages - 1)
                self.updatePageLabel()
                self.scrollToPage(in: webView, pageIndex: self.currentPage)
            } else {
                // Fallback: use a default single page if calculation fails
                print("Page calculation failed - using default single page")
                print("Total pages result: \(totalPages ?? "nil")")
                self.totalPagesPerSpine[self.currentSpineIndex] = 1
                self.totalPages = 1
                self.currentPage = 0
                self.updatePageLabel()
            }
        }
    }
    
    private func applySettings(to webView: WKWebView) {
        let backgroundColor = UserDefaults.standard.string(forKey: "backgroundColor") ?? "#FFFFFF"
        let fontFamily = UserDefaults.standard.string(forKey: "fontFamily") ?? "Georgia"
        let fontSize = UserDefaults.standard.integer(forKey: "fontSize") > 0 ? UserDefaults.standard.integer(forKey: "fontSize") : 16
        let isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        
        let viewHeight = view.safeAreaLayoutGuide.layoutFrame.height - pageLabel.frame.height - 20
        let viewWidth = view.frame.width - 40
        
        let css = """
        * {
            -webkit-touch-callout: default;
            box-sizing: border-box;
        }
        html {
            margin: 0;
            padding: 0;
            height: 100vh;
            overflow: hidden;
            background-color: \(backgroundColor);
        }
        body {
            margin: 0;
            padding: 20px;
            font-family: '\(fontFamily)', serif;
            font-size: \(fontSize)px;
            color: \(isDarkMode ? "#FFFFFF" : "#000000");
            line-height: 1.6;
            
            /* Enable text selection */
            -webkit-user-select: text;
            -moz-user-select: text;
            -ms-user-select: text;
            user-select: text;
            
            /* Column-based pagination */
            column-width: \(viewWidth)px;
            column-height: \(viewHeight - 40)px;
            column-gap: 20px;
            column-fill: auto;
            
            /* Fixed height for consistent pagination */
            height: \(viewHeight - 40)px;
            width: auto;
            overflow: hidden;
            
            /* Prevent awkward breaks */
            orphans: 2;
            widows: 2;
        }
        p {
            margin-bottom: 1em;
            break-inside: avoid-column;
            -webkit-user-select: text;
            user-select: text;
        }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            break-after: avoid-column;
            break-inside: avoid-column;
            -webkit-user-select: text;
            user-select: text;
        }
        img {
            max-width: 100%;
            height: auto;
            break-inside: avoid-column;
        }
        blockquote, pre {
            break-inside: avoid-column;
            -webkit-user-select: text;
            user-select: text;
        }
        
        /* Highlight styles */
        .highlight {
            background-color: yellow;
            color: black;
        }
        """
        
        let js = """
        var meta = document.createElement('meta');
        meta.name = "viewport";
        meta.content = "width=device-width, initial-scale=1.0, user-scalable=no";
        document.head.appendChild(meta);
        
        var style = document.createElement('style');
        style.type = "text/css";
        style.textContent = `\(css)`;
        document.head.appendChild(style);
        
        // Page configuration
        var pageConfig = {
            columnWidth: \(viewWidth),
            columnGap: 20,
            viewportWidth: \(viewWidth),
            targetPageIndex: 0
        };
        
        // Disable body scrolling but allow text selection
        document.body.style.overflowX = 'hidden';
        document.body.style.overflowY = 'hidden';
        window.addEventListener('scroll', function(e) { e.preventDefault(); });
        window.addEventListener('wheel', function(e) { e.preventDefault(); });
        
        // Existing page functions...
        window.getTotalPages = function() {
            var computedStyle = window.getComputedStyle(document.body);
            var columnWidth = parseFloat(computedStyle.columnWidth) || pageConfig.columnWidth;
            var columnGap = parseFloat(computedStyle.columnGap) || pageConfig.columnGap;
            
            var totalWidth = document.body.scrollWidth;
            var singleColumnWidth = columnWidth + columnGap;
            var totalColumns = Math.ceil(totalWidth / singleColumnWidth);
            
            console.log('Total width: ' + totalWidth + ', Single column: ' + singleColumnWidth + ', Columns: ' + totalColumns);
            return Math.max(1, totalColumns);
        };
        
        window.setPageIndex = function(pageIndex) {
            pageConfig.targetPageIndex = pageIndex;
            
            var columnWidth = pageConfig.columnWidth;
            var columnGap = pageConfig.columnGap;
            var singleColumnWidth = columnWidth + columnGap;
            
            var leftPosition = pageIndex * singleColumnWidth;
            
            var clipPath = 'inset(0 0 0 ' + leftPosition + 'px)';
            document.body.style.clipPath = clipPath;
            document.body.style.webkitClipPath = clipPath;
            document.body.style.marginLeft = '-' + leftPosition + 'px';
            
            return {
                totalPages: window.getTotalPages(),
                currentPage: pageIndex
            };
        };
        
        window.getCurrentPage = function() {
            return pageConfig.targetPageIndex;
        };
        
        window.refreshLayout = function() {
            document.body.style.display = 'none';
            document.body.offsetHeight;
            document.body.style.display = '';
            return window.getTotalPages();
        };
        """
        
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("Error injecting settings: \(error)")
            }
        }
    }

    func scrollToPage(in webView: WKWebView, pageIndex: Int, completion: (() -> Void)? = nil) {
        webView.evaluateJavaScript("window.setPageIndex(\(pageIndex))") { result, error in
            if let error = error {
                print("Error setting page index: \(error)")
            }
            completion?()
        }
    }

    private func updatePageLabel() {
        let globalPageNumber = getCurrentGlobalPageNumber()
        let totalGlobalPages = getTotalGlobalPages()
        pageLabel.text = "Page \(globalPageNumber) of \(totalGlobalPages)"
    }
    
    private func getCurrentGlobalPageNumber() -> Int {
        var globalPage = 1
        for i in 0..<currentSpineIndex {
            globalPage += totalPagesPerSpine[i]
        }
        globalPage += currentPage
        return globalPage
    }
    
    private func getTotalGlobalPages() -> Int {
        return totalPagesPerSpine.reduce(0, +)
    }
    
    // MARK: - UIPageViewController DataSource
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? PageContentViewController else { return nil }
        
        if current.pageIndex > 0 {
            // Previous page in same chapter
            let previousPage = current.pageIndex - 1
            currentPage = previousPage
            return createPageViewController(for: previousPage)
        } else if currentSpineIndex > 0 {
            // Move to previous chapter, last page
            currentSpineIndex -= 1
            let lastPage = max(0, totalPagesPerSpine[currentSpineIndex] - 1)
            currentPage = lastPage
            return createPageViewController(for: lastPage)
        }
        return nil
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? PageContentViewController else { return nil }
        
        if current.pageIndex < totalPagesPerSpine[currentSpineIndex] - 1 {
            // Next page in same chapter
            let nextPage = current.pageIndex + 1
            currentPage = nextPage
            return createPageViewController(for: nextPage)
        } else if currentSpineIndex < spineItems.count - 1 {
            // Move to next chapter, first page
            currentSpineIndex += 1
            currentPage = 0
            return createPageViewController(for: 0)
        }
        return nil
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let current = pageViewController.viewControllers?.first as? PageContentViewController {
            currentPage = current.pageIndex
            updatePageLabel()
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
            let tocItem = tocItems[indexPath.row]
            print("TOC item selected: \(tocItem.label), href: \(tocItem.href)")
            
            // Clean the href - remove any leading "./" and handle fragments
            var cleanHref = tocItem.href
            if cleanHref.hasPrefix("./") {
                cleanHref = String(cleanHref.dropFirst(2))
            }
            
            // Split href and fragment if present
            let components = cleanHref.components(separatedBy: "#")
            let fileHref = components[0]
            
            // Find the spine index that matches the TOC href
            if let index = spineItems.firstIndex(where: { spine in
                let spineHref = spine.href.components(separatedBy: "#")[0]
                return spineHref == fileHref || spineHref.hasSuffix(fileHref) || fileHref.hasSuffix(spineHref)
            }) {
                currentSpineIndex = index
                currentPage = 0
                if let newPage = createPageViewController(for: currentPage) {
                    pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
                }
                updatePageLabel()
                toggleTOC()
                print("Navigated to spine index: \(index) for file: \(fileHref)")
            } else {
                print("Could not find matching spine for TOC href: \(fileHref)")
                print("Available spine hrefs: \(spineItems.map { $0.href })")
            }
        } else if tableView == highlightsTableView {
            let highlight = highlights[indexPath.row]
            currentSpineIndex = highlight.spineIndex
            
            // Navigate to the spine first
            if let newPage = createPageViewController(for: 0) {
                pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
            }
            
            // Find the correct page after the content loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.findAndNavigateToHighlight(highlight)
            }
            
            toggleHighlights()
        } else {
            currentSpineIndex = bookmarks[indexPath.row].spineIndex
            currentPage = bookmarks[indexPath.row].pageNumber
            if let newPage = createPageViewController(for: currentPage) {
                pageViewController.setViewControllers([newPage], direction: .forward, animated: false)
            }
            updatePageLabel()
            toggleBookmarks()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    private func findAndNavigateToHighlight(_ highlight: Highlight) {
        guard let currentPageVC = pageViewController.viewControllers?.first as? PageContentViewController else {
            return
        }
        
        let webView = currentPageVC.webView
        let findHighlightJS = """
        (function() {
            var textContent = document.body.textContent || document.body.innerText;
            var searchText = '\(highlight.text.replacingOccurrences(of: "'", with: "\\'"))';
            var context = '\(highlight.textContext.replacingOccurrences(of: "'", with: "\\'"))';
            
            // Find the text position
            var foundIndex = -1;
            if (context.length > 0) {
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


