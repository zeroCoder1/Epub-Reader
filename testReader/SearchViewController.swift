//
//  SearchViewController.swift
//  testReader
//

import UIKit

// A single full-text search hit: where it is, a readable snippet, and its page/chapter.
struct EPUBSearchResult {
    let spineIndex: Int
    let snippet: String
    let query: String
    let chapter: String?
    let page: Int
    let relativePosition: Double
    let occurrence: Int   // which match within the chapter (0-based), for exact navigation
}

final class SearchViewController: UIViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var results: [EPUBSearchResult] = []
    private var debounce: DispatchWorkItem?
    private var currentQuery = ""

    // Provided by the reader: run the (potentially slow) search off-main and call back on main.
    private let performSearch: (String, @escaping ([EPUBSearchResult]) -> Void) -> Void
    private let onSelect: (EPUBSearchResult) -> Void

    init(performSearch: @escaping (String, @escaping ([EPUBSearchResult]) -> Void) -> Void,
         onSelect: @escaping (EPUBSearchResult) -> Void) {
        self.performSearch = performSearch
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setup()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    private func setup() {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = .tertiarySystemFill
        closeButton.layer.cornerRadius = 16
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        searchBar.placeholder = "Search in book"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .search
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Type to search the whole book."
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(closeButton)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            searchBar.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            searchBar.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 44),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36)
        ])
    }

    @objc private func close() {
        view.endEditing(true)
        dismiss(animated: true)
    }

    // MARK: - Search input

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = query
        debounce?.cancel()

        guard query.count >= 2 else {
            results = []
            statusLabel.text = query.isEmpty ? "Type to search the whole book." : "Keep typing…"
            statusLabel.isHidden = false
            tableView.reloadData()
            return
        }

        statusLabel.text = "Searching…"
        statusLabel.isHidden = false
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.performSearch(query) { [weak self] found in
                guard let self = self, self.currentQuery == query else { return }
                self.results = found
                self.statusLabel.text = found.isEmpty ? "No results for “\(query)”." : nil
                self.statusLabel.isHidden = !found.isEmpty
                self.tableView.reloadData()
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - Results

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath) as! SearchResultCell
        let r = results[indexPath.row]
        let footer = [r.chapter, "p. \(r.page)"].compactMap { $0 }.joined(separator: "  ·  ")
        cell.configure(snippet: r.snippet, query: r.query, footer: footer)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let result = results[indexPath.row]
        view.endEditing(true)
        dismiss(animated: true) { [weak self] in self?.onSelect(result) }
    }
}

// MARK: - Cell

final class SearchResultCell: UITableViewCell {
    private let container = UIView()
    private let snippetLabel = UILabel()
    private let footerLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = .clear

        container.translatesAutoresizingMaskIntoConstraints = false

        snippetLabel.numberOfLines = 3
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false

        footerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        footerLabel.textColor = .secondaryLabel
        footerLabel.numberOfLines = 1
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(container)
        container.addSubview(snippetLabel)
        container.addSubview(footerLabel)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            snippetLabel.topAnchor.constraint(equalTo: container.topAnchor),
            snippetLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            footerLabel.topAnchor.constraint(equalTo: snippetLabel.bottomAnchor, constant: 6),
            footerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(snippet: String, query: String, footer: String) {
        snippetLabel.attributedText = SearchResultCell.highlighted(snippet, query: query)
        footerLabel.text = footer
    }

    // Bolds every case-insensitive occurrence of the query within the snippet.
    private static func highlighted(_ snippet: String, query: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: snippet, attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.secondaryLabel
        ])
        guard !query.isEmpty else { return text }
        let ns = snippet as NSString
        var range = NSRange(location: 0, length: ns.length)
        while range.location < ns.length {
            let found = ns.range(of: query, options: .caseInsensitive, range: range)
            if found.location == NSNotFound { break }
            text.addAttributes([
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.label
            ], range: found)
            let next = found.location + max(1, found.length)
            range = NSRange(location: next, length: ns.length - next)
        }
        return text
    }
}
