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
    let pageIndex: Int
    var targetPageIndex: Int = 0
    weak var delegate: ReaderViewController?
    
    init(webView: WKWebView, pageIndex: Int, delegate: ReaderViewController?) {
        self.webView = webView
        self.pageIndex = pageIndex
        self.targetPageIndex = pageIndex
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
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
        // Just set the page index when view appears - no translation needed
        if webView.alpha > 0 {
            delegate?.scrollToPage(in: webView, pageIndex: targetPageIndex)
        }
    }
}
