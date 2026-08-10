//
//  LibraryViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//


import UIKit

class LibraryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView()
    private var epubFiles: [URL] = []
    private let fileManager = FileManager.default

    // Title/author/cover, loaded lazily off the main thread and cached per file path.
    private struct BookMeta { let title: String; let author: String?; let cover: UIImage? }
    private var metaCache: [String: BookMeta] = [:]
    private var loadingPaths: Set<String> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .automatic
        setupTableView()
        loadEpubFiles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The reader hides the navigation bar for immersive reading; restore it on return.
        navigationController?.setNavigationBarHidden(false, animated: animated)
        loadEpubFiles()
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemBackground
        tableView.separatorColor = .separator
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 84, bottom: 0, right: 0)
        tableView.rowHeight = 112
        tableView.register(LibraryBookCell.self, forCellReuseIdentifier: "LibraryBookCell")
    }

    private func loadEpubFiles() {
        let bundledEPUBs = discoverEPUBsInBundle()
        let documentEPUBs = discoverEPUBsInDocumentsDirectory()

        // Keep one entry per absolute path and sort by display name.
        var uniqueByPath: [String: URL] = [:]
        for url in bundledEPUBs + documentEPUBs {
            uniqueByPath[url.standardizedFileURL.path] = url
        }

        epubFiles = uniqueByPath.values.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        tableView.reloadData()
    }

    private func discoverEPUBsInBundle() -> [URL] {
        guard let bundleRootURL = Bundle.main.resourceURL else {
            return []
        }
        return discoverEPUBsRecursively(at: bundleRootURL)
    }

    private func discoverEPUBsInDocumentsDirectory() -> [URL] {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        return discoverEPUBsRecursively(at: documentsURL)
    }

    private func discoverEPUBsRecursively(at rootURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return []
        }

        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "epub" {
                result.append(fileURL)
            }
        }
        return result
    }

    private func isBundled(_ url: URL) -> Bool {
        let bundlePath = (Bundle.main.resourceURL?.standardizedFileURL.path ?? "") + "/"
        return url.standardizedFileURL.path.hasPrefix(bundlePath)
    }

    // Filename fallback when the OPF has no usable title.
    private func prettifiedName(_ url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return base.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Metadata loading

    private func ensureMetadataLoaded(for url: URL) {
        let path = url.standardizedFileURL.path
        guard metaCache[path] == nil, !loadingPaths.contains(path) else { return }
        loadingPaths.insert(path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let brief = EPUBParser.briefMetadata(at: url)
            let cover = brief?.coverData.flatMap { UIImage(data: $0) }
            let title = (brief?.title).flatMap { $0.isEmpty || $0 == "Unknown Title" ? nil : $0 }
            let author = (brief?.author).flatMap { $0.isEmpty || $0 == "Unknown Author" ? nil : $0 }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadingPaths.remove(path)
                self.metaCache[path] = BookMeta(title: title ?? self.prettifiedName(url), author: author, cover: cover)
                if let idx = self.epubFiles.firstIndex(where: { $0.standardizedFileURL.path == path }) {
                    self.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
                }
            }
        }
    }

    // MARK: - Table view

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return epubFiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LibraryBookCell", for: indexPath) as! LibraryBookCell
        let fileURL = epubFiles[indexPath.row]
        let path = fileURL.standardizedFileURL.path
        let footnote = isBundled(fileURL) ? "EPUB · Bundled" : "EPUB"

        if let meta = metaCache[path] {
            cell.configure(title: meta.title, author: meta.author, cover: meta.cover, footnote: footnote)
        } else {
            cell.configure(title: prettifiedName(fileURL), author: nil, cover: nil, footnote: footnote)
            ensureMetadataLoaded(for: fileURL)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedURL = epubFiles[indexPath.row]
        tableView.deselectRow(at: indexPath, animated: true)
        do {
            let readableURL = try prepareEPUBForReading(from: selectedURL)
            let readerVC = ReaderViewController(epubURL: readableURL)
            navigationController?.pushViewController(readerVC, animated: true)
        } catch {
            showLoadError(message: error.localizedDescription)
        }
    }

    private func prepareEPUBForReading(from sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL else {
            throw NSError(domain: "EPUBReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected EPUB path is invalid."])
        }

        let bundlePath = (Bundle.main.resourceURL?.standardizedFileURL.path ?? "") + "/"
        let sourcePath = sourceURL.standardizedFileURL.path

        // EPUBs inside the app bundle are read-only; copy them to caches for stable access.
        if sourcePath.hasPrefix(bundlePath) {
            let cachesURL = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let targetDirectory = cachesURL.appendingPathComponent("BundledEPUBs", isDirectory: true)
            try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

            let targetURL = targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            return targetURL
        }

        return sourceURL
    }

    private func showLoadError(message: String) {
        let alert = UIAlertController(title: "Unable to Open EPUB", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Cell

final class LibraryBookCell: UITableViewCell {
    private let coverView = UIImageView()
    private let placeholderIcon = UIImageView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let footnoteLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        selectionStyle = .default

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 5
        coverView.backgroundColor = .secondarySystemBackground
        coverView.layer.borderWidth = 0.5
        coverView.layer.borderColor = UIColor.separator.cgColor
        coverView.translatesAutoresizingMaskIntoConstraints = false

        placeholderIcon.image = UIImage(systemName: "book.closed")
        placeholderIcon.tintColor = .tertiaryLabel
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        authorLabel.font = .systemFont(ofSize: 14)
        authorLabel.textColor = .secondaryLabel
        authorLabel.numberOfLines = 1

        footnoteLabel.font = .systemFont(ofSize: 12, weight: .medium)
        footnoteLabel.textColor = .tertiaryLabel
        footnoteLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, authorLabel, footnoteLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setCustomSpacing(7, after: authorLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(coverView)
        coverView.addSubview(placeholderIcon)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 56),
            coverView.heightAnchor.constraint(equalToConstant: 84),

            placeholderIcon.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 26),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 26),

            textStack.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        coverView.layer.borderColor = UIColor.separator.cgColor
    }

    func configure(title: String, author: String?, cover: UIImage?, footnote: String) {
        titleLabel.text = title
        authorLabel.text = author
        authorLabel.isHidden = (author == nil)
        footnoteLabel.text = footnote
        coverView.image = cover
        placeholderIcon.isHidden = (cover != nil)
    }
}
