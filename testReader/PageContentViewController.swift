//
//  PageContentViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 28/05/25.
//

import UIKit
import WebKit

class PageContentViewController: UIViewController {
    let webView: WKWebView
    var pageIndex: Int
    let spineIndex: Int
    var targetPageIndex: Int = 0
    weak var delegate: ReaderViewController?

    // Fixed-layout two-page spread: the second (right-hand) page, shown beside `webView`.
    // nil for single pages and all reflowable content.
    let rightWebView: WKWebView?
    let rightSpineIndex: Int?

    // Set to false when the webview is being handed to a replacement VC (e.g. re-anchoring
    // after a TOC/highlight jump), so deinit doesn't recycle a webview still in use.
    var recyclesWebViewOnDeinit = true

    init(webView: WKWebView, pageIndex: Int, spineIndex: Int, delegate: ReaderViewController?,
         rightWebView: WKWebView? = nil, rightSpineIndex: Int? = nil) {
        self.webView = webView
        self.pageIndex = pageIndex
        self.spineIndex = spineIndex
        self.targetPageIndex = pageIndex
        self.delegate = delegate
        self.rightWebView = rightWebView
        self.rightSpineIndex = rightSpineIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Hand the webview(s) back to the reader's warm pool for reuse (unless it was handed
        // off to a replacement page VC).
        guard recyclesWebViewOnDeinit else { return }
        delegate?.recycleWebView(webView)
        if let rightWebView { delegate?.recycleWebView(rightWebView) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        if let rightWebView {
            // Two pages side by side, splitting the width evenly.
            view.addSubview(rightWebView)
            rightWebView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.topAnchor),
                webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                webView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),

                rightWebView.topAnchor.constraint(equalTo: view.topAnchor),
                rightWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                rightWebView.leadingAnchor.constraint(equalTo: webView.trailingAnchor),
                rightWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.topAnchor),
                webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }

        // Enable the menu controller
        becomeFirstResponder()
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(highlightSelectedText) || action == #selector(bookmarkFromMenu) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    @objc func highlightSelectedText() {
        // Forward the action to the delegate (ReaderViewController)
        delegate?.highlightSelectedText()
    }
    
    @objc func bookmarkFromMenu() {
        // Forward the action to the delegate (ReaderViewController)
        delegate?.bookmarkFromMenu()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-assert this page's target index on appear; no-ops until pagination JS is ready.
        delegate?.scrollToPage(in: webView, pageIndex: targetPageIndex)
    }
}
