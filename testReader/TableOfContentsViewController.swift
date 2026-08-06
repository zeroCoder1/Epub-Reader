//
//  TableOfContentsViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 04/08/25.
//

import UIKit

final class TableOfContentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let items: [EPUBTOCItem]
    private let pageNumbers: [Int?]
    private let currentItemIndex: Int?
    private let bookTitle: String
    private let metadata: EPUBMetadata?
    private let coverImage: UIImage?
    private let pageSummary: String
    private let onSelect: (EPUBTOCItem) -> Void

    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let detailLabel = UILabel()
    private let summaryLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(items: [EPUBTOCItem],
         pageNumbers: [Int?],
         currentItemIndex: Int?,
         bookTitle: String,
         metadata: EPUBMetadata?,
         coverImage: UIImage?,
         pageSummary: String,
         onSelect: @escaping (EPUBTOCItem) -> Void) {
        self.items = items
        self.pageNumbers = pageNumbers
        self.currentItemIndex = currentItemIndex
        self.bookTitle = bookTitle
        self.metadata = metadata
        self.coverImage = coverImage
        self.pageSummary = pageSummary
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupHeader()
        setupTable()
        scrollToCurrentItem()
    }

    // Set at the end of setupHeader so setupTable can pin the list below the header,
    // whether or not a description is present.
    private var headerBottomAnchor: NSLayoutYAxisAnchor!
    private var headerBottomInset: CGFloat = 20

    private func setupHeader() {
        coverImageView.contentMode = .scaleAspectFit
        coverImageView.image = coverImage
        coverImageView.layer.cornerRadius = 4
        coverImageView.clipsToBounds = true
        coverImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = bookTitle
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let authorText = composedAuthor()
        authorLabel.text = authorText
        authorLabel.font = UIFont.systemFont(ofSize: 15)
        authorLabel.textColor = .secondaryLabel
        authorLabel.numberOfLines = 1
        authorLabel.isHidden = (authorText == nil)

        let detailText = composedDetail()
        detailLabel.text = detailText
        detailLabel.font = UIFont.systemFont(ofSize: 13)
        detailLabel.textColor = .tertiaryLabel
        detailLabel.numberOfLines = 2
        detailLabel.isHidden = (detailText == nil)

        // Page number is the last line of the header stack.
        summaryLabel.text = pageSummary
        summaryLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        summaryLabel.textColor = .secondaryLabel

        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = .tertiarySystemFill
        closeButton.layer.cornerRadius = 22
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, authorLabel, detailLabel, summaryLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.setCustomSpacing(8, after: detailLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(coverImageView)
        view.addSubview(textStack)
        view.addSubview(closeButton)

        // A guide whose bottom tracks the taller of cover / text column.
        let rowGuide = UILayoutGuide()
        view.addLayoutGuide(rowGuide)
        let equalToCover = rowGuide.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor)
        let equalToText = rowGuide.bottomAnchor.constraint(equalTo: textStack.bottomAnchor)
        equalToCover.priority = .defaultLow
        equalToText.priority = .defaultLow

        NSLayoutConstraint.activate([
            coverImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            coverImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            coverImageView.widthAnchor.constraint(equalToConstant: 88),
            coverImageView.heightAnchor.constraint(equalToConstant: 130),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            textStack.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 4),

            rowGuide.bottomAnchor.constraint(greaterThanOrEqualTo: coverImageView.bottomAnchor),
            rowGuide.bottomAnchor.constraint(greaterThanOrEqualTo: textStack.bottomAnchor),
            equalToCover, equalToText
        ])

        // Optional full-width description below the cover/text row.
        if let descriptionText = composedDescription() {
            descriptionLabel.text = descriptionText
            descriptionLabel.font = UIFont.systemFont(ofSize: 14)
            descriptionLabel.textColor = .secondaryLabel
            descriptionLabel.numberOfLines = 4
            descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(descriptionLabel)
            NSLayoutConstraint.activate([
                descriptionLabel.topAnchor.constraint(equalTo: rowGuide.bottomAnchor, constant: 14),
                descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
            ])
            headerBottomAnchor = descriptionLabel.bottomAnchor
            headerBottomInset = 16
        } else {
            headerBottomAnchor = rowGuide.bottomAnchor
            headerBottomInset = 20
        }
    }

    private func setupTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemBackground
        tableView.separatorColor = .separator
        tableView.rowHeight = 56
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.register(TOCListCell.self, forCellReuseIdentifier: "TOCListCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerBottomAnchor, constant: headerBottomInset),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Metadata formatting

    private func composedAuthor() -> String? {
        guard let author = metadata?.author, !author.isEmpty, author != "Unknown Author" else { return nil }
        return "by \(author)"
    }

    private func composedDetail() -> String? {
        var parts: [String] = []
        if let publisher = metadata?.publisher, !publisher.isEmpty { parts.append(publisher) }
        if let language = metadata?.language, !language.isEmpty {
            let display = Locale.current.localizedString(forLanguageCode: language)
                ?? Locale.current.localizedString(forIdentifier: language)
                ?? language.uppercased()
            parts.append(display)
        }
        if let year = publicationYear() { parts.append(year) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // First 4-digit run in the date string (handles "2011", "2011-03-01", ISO timestamps).
    private func publicationYear() -> String? {
        guard let date = metadata?.publicationDate else { return nil }
        let chars = Array(date)
        guard chars.count >= 4 else { return nil }
        for i in 0...(chars.count - 4) {
            let slice = chars[i..<i+4]
            if slice.allSatisfy({ $0.isNumber }) { return String(slice) }
        }
        return nil
    }

    private func composedDescription() -> String? {
        guard var desc = metadata?.bookDescription, !desc.isEmpty else { return nil }
        // dc:description occasionally carries HTML; strip tags and common entities.
        desc = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return desc.isEmpty ? nil : desc
    }

    private func scrollToCurrentItem() {
        guard let idx = currentItemIndex, idx < items.count else { return }
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: IndexPath(row: idx, section: 0), at: .middle, animated: false)
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TOCListCell", for: indexPath) as! TOCListCell
        let item = items[indexPath.row]
        cell.configure(title: item.label, page: pageNumbers[indexPath.row], highlighted: indexPath.row == currentItemIndex)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let item = items[indexPath.row]
        dismiss(animated: true) { [weak self] in
            self?.onSelect(item)
        }
    }
}

final class TOCListCell: UITableViewCell {
    private let container = UIView()
    private let titleLabel = UILabel()
    private let pageLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = UIFont.systemFont(ofSize: 13)
        pageLabel.textColor = .secondaryLabel
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)
        container.addSubview(titleLabel)
        container.addSubview(pageLabel)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            pageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            pageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, page: Int?, highlighted: Bool) {
        titleLabel.text = title
        pageLabel.text = page.map { "\($0)" } ?? ""
        container.backgroundColor = highlighted ? .tertiarySystemFill : .clear
    }
}
