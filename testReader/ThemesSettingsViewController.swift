//
//  ThemesSettingsViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 04/08/25.
//

import UIKit

struct ReaderTheme {
    let name: String
    let backgroundHex: String
    let textHex: String
    let darkBackgroundHex: String
    let darkTextHex: String
    let bold: Bool
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    static func dynamic(light: String, dark: String) -> UIColor {
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

enum ReaderPageTransition: String, CaseIterable {
    case slide, curl, fastFade, scroll
    var title: String {
        switch self {
        case .slide: return "Slide"
        case .curl: return "Curl"
        case .fastFade: return "Fast Fade"
        case .scroll: return "Scroll"
        }
    }
    var icon: String {
        switch self {
        case .slide: return "arrow.left.square"
        case .curl: return "doc"
        case .fastFade: return "bolt"
        case .scroll: return "doc.plaintext"
        }
    }
}

protocol ThemesSettingsViewControllerDelegate: AnyObject {
    func themesViewController(_ controller: ThemesSettingsViewController, didSelectDarkMode isDarkMode: Bool)
    func themesViewController(_ controller: ThemesSettingsViewController, didSelectTheme theme: ReaderTheme)
    func themesViewController(_ controller: ThemesSettingsViewController, didChangeFontSizeBy delta: Int)
    func themesViewController(_ controller: ThemesSettingsViewController, didSelectTransition transition: ReaderPageTransition)
    func themesViewControllerDidRequestCustomize(_ controller: ThemesSettingsViewController)
}

class ThemesSettingsViewController: UIViewController {
    weak var delegate: ThemesSettingsViewControllerDelegate?
    // Set by the reader; hides the page-curl transition, which has no RTL variant.
    var isRTL: Bool = false

    private let themes: [ReaderTheme] = [
        ReaderTheme(name: "Original", backgroundHex: "#FFFFFF", textHex: "#000000", darkBackgroundHex: "#000000", darkTextHex: "#FFFFFF", bold: false),
        ReaderTheme(name: "Quiet", backgroundHex: "#545454", textHex: "#D1D1D1", darkBackgroundHex: "#1A1A1A", darkTextHex: "#8E8E93", bold: false),
        ReaderTheme(name: "Paper", backgroundHex: "#F5F5F5", textHex: "#000000", darkBackgroundHex: "#121212", darkTextHex: "#D6D6D6", bold: false),
        ReaderTheme(name: "Bold", backgroundHex: "#FFFFFF", textHex: "#000000", darkBackgroundHex: "#000000", darkTextHex: "#FFFFFF", bold: true),
        ReaderTheme(name: "Calm", backgroundHex: "#F2E3BF", textHex: "#333333", darkBackgroundHex: "#2E2A1E", darkTextHex: "#C9B48A", bold: false),
        ReaderTheme(name: "Focus", backgroundHex: "#FAF7ED", textHex: "#000000", darkBackgroundHex: "#26261C", darkTextHex: "#E5E1D0", bold: false)
    ]

    private let rootStack = UIStackView()
    private let topRow = UIStackView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let sizeControl = UIStackView()
    private let modeControl = UIStackView()
    private let brightnessSlider = UISlider()
    private let cardsGrid = UIStackView()
    private let customizeButton = UIButton(type: .system)

    private let smallAButton = UIButton(type: .system)
    private let bigAButton = UIButton(type: .system)
    private let boltButton = UIButton(type: .system)
    private let sunButton = UIButton(type: .system)
    private var cardViews: [UIView] = []

    private var menuSelectHandler: ((Int) -> Void)?
    private var activeMenuBackdrop: UIControl?
    private var activeMenuPanel: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        applyPanelStyle()
        view.backgroundColor = .clear
        setupContainer()
        setupTopRow()
        setupControls()
        setupCards()
        setupCustomizeButton()
    }

    // The real system appearance, independent of the app-wide light override on the window
    // (the window scene's trait environment isn't affected by the window's own override).
    private var systemUserInterfaceStyle: UIUserInterfaceStyle {
        view.window?.windowScene?.traitCollection.userInterfaceStyle ?? UIScreen.main.traitCollection.userInterfaceStyle
    }

    private func applyPanelStyle() {
        let mode = UserDefaults.standard.integer(forKey: "readerThemeMode")
        switch mode {
        case 1: overrideUserInterfaceStyle = .dark
        case 2: overrideUserInterfaceStyle = .unspecified
        default: overrideUserInterfaceStyle = UserDefaults.standard.bool(forKey: "isDarkMode") ? .dark : .light
        }
    }

    private func setupContainer() {
        rootStack.axis = .vertical
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let materialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        materialView.layer.cornerRadius = 28
        materialView.clipsToBounds = true
        materialView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(materialView)
        materialView.contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            materialView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            materialView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            materialView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 90),

            rootStack.topAnchor.constraint(equalTo: materialView.contentView.topAnchor, constant: 18),
            rootStack.bottomAnchor.constraint(equalTo: materialView.contentView.bottomAnchor, constant: -18),
            rootStack.leadingAnchor.constraint(equalTo: materialView.contentView.leadingAnchor, constant: 18),
            rootStack.trailingAnchor.constraint(equalTo: materialView.contentView.trailingAnchor, constant: -18)
        ])
    }

    private func setupTopRow() {
        topRow.axis = .horizontal
        topRow.alignment = .center

        titleLabel.text = "Themes & Settings"
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)

        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.backgroundColor = .tertiarySystemFill
        closeButton.layer.cornerRadius = 23
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        topRow.addArrangedSubview(titleLabel)
        topRow.addArrangedSubview(UIView())
        topRow.addArrangedSubview(closeButton)
        rootStack.addArrangedSubview(topRow)
    }

    private func setupControls() {
        let controlRow = UIStackView()
        controlRow.axis = .horizontal
        controlRow.spacing = 12
        controlRow.distribution = .fillEqually

        smallAButton.setTitle("A", for: .normal)
        smallAButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        smallAButton.tintColor = .label
        smallAButton.setTitleColor(.label, for: .normal)
        smallAButton.addTarget(self, action: #selector(decreaseFontTapped), for: .touchUpInside)

        bigAButton.setTitle("A", for: .normal)
        bigAButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .regular)
        bigAButton.tintColor = .label
        bigAButton.setTitleColor(.label, for: .normal)
        bigAButton.addTarget(self, action: #selector(increaseFontTapped), for: .touchUpInside)

        boltButton.setImage(UIImage(systemName: "bolt.square"), for: .normal)
        boltButton.tintColor = .label
        boltButton.addTarget(self, action: #selector(transitionTapped), for: .touchUpInside)

        sunButton.setImage(UIImage(systemName: "sun.max"), for: .normal)
        sunButton.tintColor = .label
        sunButton.addTarget(self, action: #selector(themeModeTapped), for: .touchUpInside)

        layoutCapsule(sizeControl, first: smallAButton, second: bigAButton)
        layoutCapsule(modeControl, first: boltButton, second: sunButton)

        controlRow.addArrangedSubview(sizeControl)
        controlRow.addArrangedSubview(modeControl)

        let leftSun = UIImageView(image: UIImage(systemName: "sun.min"))
        let rightSun = UIImageView(image: UIImage(systemName: "sun.max"))
        leftSun.tintColor = .label
        rightSun.tintColor = .label

        let brightnessRow = UIStackView(arrangedSubviews: [leftSun, brightnessSlider, rightSun])
        brightnessRow.axis = .horizontal
        brightnessRow.spacing = 10
        brightnessRow.alignment = .center

        brightnessSlider.minimumValue = 0
        brightnessSlider.maximumValue = 1
        brightnessSlider.value = 0.35

        rootStack.addArrangedSubview(controlRow)
        rootStack.addArrangedSubview(brightnessRow)
    }

    private func layoutCapsule(_ stack: UIStackView, first: UIButton, second: UIButton) {
        stack.axis = .horizontal
        stack.distribution = .fill
        stack.alignment = .fill
        stack.spacing = 0
        stack.backgroundColor = .tertiarySystemFill
        stack.layer.cornerRadius = 22
        stack.clipsToBounds = true

        let separator = UIView()
        separator.backgroundColor = .separator

        let firstWrapper = UIView()
        firstWrapper.addSubview(first)
        first.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            first.centerXAnchor.constraint(equalTo: firstWrapper.centerXAnchor),
            first.centerYAnchor.constraint(equalTo: firstWrapper.centerYAnchor)
        ])

        let secondWrapper = UIView()
        secondWrapper.addSubview(second)
        second.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            second.centerXAnchor.constraint(equalTo: secondWrapper.centerXAnchor),
            second.centerYAnchor.constraint(equalTo: secondWrapper.centerYAnchor)
        ])

        let dividerWrapper = UIView()
        dividerWrapper.addSubview(separator)
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.centerXAnchor.constraint(equalTo: dividerWrapper.centerXAnchor),
            separator.centerYAnchor.constraint(equalTo: dividerWrapper.centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalTo: dividerWrapper.heightAnchor, multiplier: 0.62)
        ])

        stack.addArrangedSubview(firstWrapper)
        stack.addArrangedSubview(dividerWrapper)
        stack.addArrangedSubview(secondWrapper)
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true
        dividerWrapper.widthAnchor.constraint(equalToConstant: 1).isActive = true
        firstWrapper.widthAnchor.constraint(equalTo: secondWrapper.widthAnchor).isActive = true
    }

    private func setupCards() {
        cardsGrid.axis = .vertical
        cardsGrid.spacing = 10

        let selectedName = UserDefaults.standard.string(forKey: "readerTheme") ?? "Original"
        cardViews.removeAll()

        for rowIndex in 0..<2 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually

            for columnIndex in 0..<3 {
                let idx = (rowIndex * 3) + columnIndex
                let theme = themes[idx]
                let card = makeCard(title: "Aa",
                                    subtitle: theme.name,
                                    bgColor: UIColor.dynamic(light: theme.backgroundHex, dark: theme.darkBackgroundHex),
                                    textColor: UIColor.dynamic(light: theme.textHex, dark: theme.darkTextHex),
                                    selected: theme.name == selectedName)
                cardViews.append(card)
                row.addArrangedSubview(card)
            }

            cardsGrid.addArrangedSubview(row)
        }

        rootStack.addArrangedSubview(cardsGrid)
    }

    private func makeCard(title: String, subtitle: String, bgColor: UIColor, textColor: UIColor, selected: Bool) -> UIView {
        let card = UIView()
        card.backgroundColor = bgColor
        card.layer.cornerRadius = 18
        card.layer.borderWidth = selected ? 2.5 : 0
        card.layer.borderColor = selected ? UIColor.label.cgColor : UIColor.clear.cgColor
        card.isUserInteractionEnabled = true
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(themeCardTapped(_:))))

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = textColor
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .medium)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = textColor
        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            card.heightAnchor.constraint(equalToConstant: 90)
        ])

        return card
    }

    private func setupCustomizeButton() {
        customizeButton.setTitle("  Customize", for: .normal)
        customizeButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        customizeButton.tintColor = .label
        customizeButton.backgroundColor = .tertiarySystemFill
        customizeButton.layer.cornerRadius = 24
        customizeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        customizeButton.semanticContentAttribute = .forceLeftToRight
        customizeButton.contentHorizontalAlignment = .center
        customizeButton.addTarget(self, action: #selector(customizeTapped), for: .touchUpInside)
        customizeButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        rootStack.addArrangedSubview(customizeButton)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func customizeTapped() {
        delegate?.themesViewControllerDidRequestCustomize(self)
    }

    @objc private func decreaseFontTapped() {
        delegate?.themesViewController(self, didChangeFontSizeBy: -1)
    }

    @objc private func increaseFontTapped() {
        delegate?.themesViewController(self, didChangeFontSizeBy: 1)
    }

    @objc private func themeCardTapped(_ gesture: UITapGestureRecognizer) {
        guard let card = gesture.view, let index = cardViews.firstIndex(of: card) else { return }
        for (i, c) in cardViews.enumerated() {
            let isSelected = i == index
            c.layer.borderWidth = isSelected ? 2.5 : 0
            c.layer.borderColor = isSelected ? UIColor.label.cgColor : UIColor.clear.cgColor
        }
        let theme = themes[index]
        UserDefaults.standard.set(theme.name, forKey: "readerTheme")
        delegate?.themesViewController(self, didSelectTheme: theme)
    }

    @objc private func transitionTapped() {
        // Page curl has no right-to-left variant, so it's unavailable for RTL books.
        let options = ReaderPageTransition.allCases.filter { !(isRTL && $0 == .curl) }
        let current = UserDefaults.standard.string(forKey: "pageTransition") ?? "slide"
        let selected = options.firstIndex(where: { $0.rawValue == current }) ?? 0
        presentGlassMenu(from: boltButton, items: options.map { (icon: $0.icon, title: $0.title) }, selectedIndex: selected) { [weak self] idx in
            guard let self = self else { return }
            let transition = options[idx]
            UserDefaults.standard.set(transition.rawValue, forKey: "pageTransition")
            self.delegate?.themesViewController(self, didSelectTransition: transition)
        }
    }

    @objc private func themeModeTapped() {
        let modes: [(icon: String, title: String)] = [
            ("sunrise", "Light"),
            ("moon.stars", "Dark"),
            ("circle.lefthalf.filled", "Match Device"),
            ("sun.max", "Match Surroundings")
        ]
        let selected = UserDefaults.standard.integer(forKey: "readerThemeMode")
        presentGlassMenu(from: sunButton, items: modes, selectedIndex: selected) { [weak self] idx in
            guard let self = self else { return }
            UserDefaults.standard.set(idx, forKey: "readerThemeMode")
            let isDark: Bool
            switch idx {
            case 1: isDark = true
            case 2: isDark = self.systemUserInterfaceStyle == .dark
            default: isDark = false
            }
            UserDefaults.standard.set(isDark, forKey: "isDarkMode")
            UIView.animate(withDuration: 0.25) { self.applyPanelStyle() }
            self.delegate?.themesViewController(self, didSelectDarkMode: isDark)
        }
    }

    // MARK: - Glass popup menu

    private func presentGlassMenu(from source: UIView, items: [(icon: String, title: String)], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        dismissGlassMenu()

        let backdrop = UIControl(frame: view.bounds)
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.addTarget(self, action: #selector(dismissGlassMenu), for: .touchUpInside)
        view.addSubview(backdrop)

        let panel = makeGlassContainer(cornerRadius: 22)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor)
        ])

        for (i, item) in items.enumerated() {
            let row = makeMenuRow(icon: item.icon, title: item.title, selected: i == selectedIndex)
            row.tag = i
            row.addTarget(self, action: #selector(menuRowTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(row)
        }

        view.addSubview(panel)
        let width: CGFloat = 250
        let rowHeight: CGFloat = 52
        let height = CGFloat(items.count) * rowHeight + 12
        let src = source.convert(source.bounds, to: view)
        var x = src.midX - width / 2
        x = max(12, min(x, view.bounds.width - width - 12))
        let y = max(12, src.minY - height - 8)
        panel.frame = CGRect(x: x, y: y, width: width, height: height)

        menuSelectHandler = onSelect
        activeMenuBackdrop = backdrop
        activeMenuPanel = panel

        panel.transform = CGAffineTransform(translationX: src.midX - panel.center.x, y: src.midY - panel.center.y).scaledBy(x: 0.1, y: 0.1)
        panel.alpha = 0
        UIView.animate(withDuration: 0.34, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4, options: [.curveEaseOut]) {
            panel.transform = .identity
            panel.alpha = 1
        }
    }

    @objc private func menuRowTapped(_ sender: UIControl) {
        let handler = menuSelectHandler
        let index = sender.tag
        dismissGlassMenu()
        handler?(index)
    }

    @objc private func dismissGlassMenu() {
        guard let panel = activeMenuPanel, let backdrop = activeMenuBackdrop else { return }
        activeMenuPanel = nil
        activeMenuBackdrop = nil
        menuSelectHandler = nil
        UIView.animate(withDuration: 0.2, animations: {
            panel.alpha = 0
            panel.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        }) { _ in
            panel.removeFromSuperview()
            backdrop.removeFromSuperview()
        }
    }

    private func makeMenuRow(icon: String, title: String, selected: Bool) -> UIControl {
        let row = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let check = UIImageView(image: UIImage(systemName: "checkmark"))
        check.tintColor = .label
        check.contentMode = .scaleAspectFit
        check.isHidden = !selected
        check.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 18)
        label.textColor = .label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(check)
        row.addSubview(iconView)
        row.addSubview(label)
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 16),
            check.heightAnchor.constraint(equalToConstant: 16),
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 44),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeGlassContainer(cornerRadius: CGFloat) -> UIVisualEffectView {
        let effectView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            effectView = UIVisualEffectView(effect: glass)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        }
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        return effectView
    }
}
