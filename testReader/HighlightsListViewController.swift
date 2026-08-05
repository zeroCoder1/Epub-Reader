//
//  HighlightsListViewController.swift
//  testReader
//

import UIKit

final class HighlightsListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private enum Mode: Int { case highlights = 0, bookmarks = 1 }

    private var highlights: [Highlight]
    private var pageNumbers: [Int?]
    private var bookmarks: [Bookmark]
    private var bookmarkPageNumbers: [Int?]
    private let currentSpineIndex: Int
    private let bookTitle: String
    private let coverImage: UIImage?
    private let onSelect: (Highlight) -> Void
    private let onDelete: ((Highlight) -> Void)?
    private let onSelectBookmark: ((Bookmark) -> Void)?
    private let onDeleteBookmark: ((Bookmark) -> Void)?

    private var mode: Mode = .highlights

    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let segmentedControl = UISegmentedControl(items: ["Highlights", "Bookmarks"])
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(highlights: [Highlight],
         pageNumbers: [Int?],
         bookmarks: [Bookmark],
         bookmarkPageNumbers: [Int?],
         currentSpineIndex: Int,
         bookTitle: String,
         coverImage: UIImage?,
         onSelect: @escaping (Highlight) -> Void,
         onDelete: ((Highlight) -> Void)? = nil,
         onSelectBookmark: ((Bookmark) -> Void)? = nil,
         onDeleteBookmark: ((Bookmark) -> Void)? = nil) {
        self.highlights = highlights
        self.pageNumbers = pageNumbers
        self.bookmarks = bookmarks
        self.bookmarkPageNumbers = bookmarkPageNumbers
        self.currentSpineIndex = currentSpineIndex
        self.bookTitle = bookTitle
        self.coverImage = coverImage
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onSelectBookmark = onSelectBookmark
        self.onDeleteBookmark = onDeleteBookmark
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupHeader()
        setupTable()
        updateHeaderText()
    }

    private func setupHeader() {
        coverImageView.contentMode = .scaleAspectFit
        coverImageView.image = coverImage
        coverImageView.layer.cornerRadius = 4
        coverImageView.clipsToBounds = true
        coverImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = UIFont.systemFont(ofSize: 16)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 2
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = .tertiarySystemFill
        closeButton.layer.cornerRadius = 22
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(coverImageView)
        view.addSubview(textStack)
        view.addSubview(closeButton)
        view.addSubview(segmentedControl)

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
            textStack.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 8),

            segmentedControl.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func setupTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemBackground
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.register(HighlightListCell.self, forCellReuseIdentifier: "HighlightListCell")
        tableView.register(BookmarkListCell.self, forCellReuseIdentifier: "BookmarkListCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateHeaderText() {
        switch mode {
        case .highlights:
            titleLabel.text = "Highlights"
            summaryLabel.text = highlights.count == 1 ? "1 highlight" : "\(highlights.count) highlights"
        case .bookmarks:
            titleLabel.text = "Bookmarks"
            summaryLabel.text = bookmarks.count == 1 ? "1 bookmark" : "\(bookmarks.count) bookmarks"
        }
    }

    @objc private func segmentChanged() {
        mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .highlights
        updateHeaderText()
        tableView.reloadData()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        mode == .highlights ? highlights.count : bookmarks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch mode {
        case .highlights:
            let cell = tableView.dequeueReusableCell(withIdentifier: "HighlightListCell", for: indexPath) as! HighlightListCell
            let highlight = highlights[indexPath.row]
            cell.configure(text: highlight.text,
                           page: pageNumbers[indexPath.row],
                           color: HighlightListCell.color(named: highlight.color),
                           highlighted: highlight.spineIndex == currentSpineIndex)
            return cell
        case .bookmarks:
            let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkListCell", for: indexPath) as! BookmarkListCell
            let bookmark = bookmarks[indexPath.row]
            cell.configure(page: bookmarkPageNumbers[indexPath.row],
                           date: bookmark.date,
                           highlighted: bookmark.spineIndex == currentSpineIndex)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        switch mode {
        case .highlights:
            let highlight = highlights[indexPath.row]
            dismiss(animated: true) { [weak self] in self?.onSelect(highlight) }
        case .bookmarks:
            let bookmark = bookmarks[indexPath.row]
            dismiss(animated: true) { [weak self] in self?.onSelectBookmark?(bookmark) }
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            switch self.mode {
            case .highlights:
                let highlight = self.highlights[indexPath.row]
                self.highlights.remove(at: indexPath.row)
                self.pageNumbers.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
                self.onDelete?(highlight)
            case .bookmarks:
                let bookmark = self.bookmarks[indexPath.row]
                self.bookmarks.remove(at: indexPath.row)
                self.bookmarkPageNumbers.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
                self.onDeleteBookmark?(bookmark)
            }
            self.updateHeaderText()
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

final class HighlightListCell: UITableViewCell {
    private let container = UIView()
    private let colorBar = UIView()
    private let textLabel_ = UILabel()
    private let pageLabel = UILabel()

    static func color(named name: String) -> UIColor {
        switch name.lowercased() {
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "pink": return .systemPink
        case "blue": return .systemBlue
        case "orange": return .systemOrange
        default: return .systemYellow
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        colorBar.layer.cornerRadius = 3
        colorBar.translatesAutoresizingMaskIntoConstraints = false

        textLabel_.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        textLabel_.textColor = .label
        textLabel_.numberOfLines = 3
        textLabel_.translatesAutoresizingMaskIntoConstraints = false

        pageLabel.font = UIFont.systemFont(ofSize: 13)
        pageLabel.textColor = .secondaryLabel
        pageLabel.setContentHuggingPriority(.required, for: .horizontal)
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(container)
        container.addSubview(colorBar)
        container.addSubview(textLabel_)
        container.addSubview(pageLabel)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            colorBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            colorBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            colorBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            colorBar.widthAnchor.constraint(equalToConstant: 6),

            textLabel_.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 12),
            textLabel_.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            textLabel_.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),

            pageLabel.leadingAnchor.constraint(equalTo: textLabel_.trailingAnchor, constant: 12),
            pageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            pageLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, page: Int?, color: UIColor, highlighted: Bool) {
        textLabel_.text = text
        pageLabel.text = page.map { "p. \($0)" } ?? ""
        colorBar.backgroundColor = color
        container.backgroundColor = highlighted ? .tertiarySystemFill : .clear
    }
}

final class BookmarkListCell: UITableViewCell {
    private let container = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = UIImage(systemName: "bookmark.fill")
        iconView.tintColor = .systemRed
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = UIFont.systemFont(ofSize: 13)
        dateLabel.textColor = .secondaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, dateLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(container)
        container.addSubview(iconView)
        container.addSubview(textStack)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(page: Int?, date: Date, highlighted: Bool) {
        titleLabel.text = page.map { "Page \($0)" } ?? "Bookmark"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: date)
        container.backgroundColor = highlighted ? .tertiarySystemFill : .clear
    }
}
