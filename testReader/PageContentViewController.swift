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
    
    init(webView: WKWebView, pageIndex: Int, spineIndex: Int, delegate: ReaderViewController?) {
        self.webView = webView
        self.pageIndex = pageIndex
        self.spineIndex = spineIndex
        self.targetPageIndex = pageIndex
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Hand the webview back to the reader's warm pool for reuse.
        delegate?.recycleWebView(webView)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
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
