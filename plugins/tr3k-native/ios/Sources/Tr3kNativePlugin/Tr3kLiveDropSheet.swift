import UIKit

/// Full-bleed black moment. One button. One line under it.
/// Swipe down dismisses. There is no second control.
final class Tr3kLiveDropSheet: UIViewController, UIGestureRecognizerDelegate {
    static weak var current: Tr3kLiveDropSheet?

    private var drop: Tr3kLiveDrop
    private var onJoin: (String) -> Void
    private let headline = UILabel()
    private let button = UIButton(type: .custom)
    private let note = UILabel()

    static func present(drop: Tr3kLiveDrop, from presenter: UIViewController, onJoin: @escaping (String) -> Void) {
        if let current {
            current.onJoin = onJoin
            current.render(drop)
            return
        }
        let sheet = Tr3kLiveDropSheet(drop: drop, onJoin: onJoin)
        sheet.modalPresentationStyle = .fullScreen
        sheet.modalPresentationCapturesStatusBarAppearance = true
        current = sheet
        presenter.present(sheet, animated: false)
    }

    static func dismissIfNeeded() {
        current?.dismiss(animated: false)
    }

    init(drop: Tr3kLiveDrop, onJoin: @escaping (String) -> Void) {
        self.drop = drop
        self.onJoin = onJoin
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        view.accessibilityViewIsModal = true

        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.textColor = .white
        headline.textAlignment = .left
        headline.numberOfLines = 3
        headline.adjustsFontSizeToFitWidth = true
        headline.minimumScaleFactor = 0.4
        headline.accessibilityTraits = .header

        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "tr3k.liveDrop.join"
        button.addTarget(self, action: #selector(join), for: .touchUpInside)

        note.translatesAutoresizingMaskIntoConstraints = false
        note.text = Tr3kLiveDropCopy.note
        note.textColor = UIColor.white.withAlphaComponent(0.72)
        note.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        note.textAlignment = .center
        note.numberOfLines = 1

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [headline, spacer, button, note])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        stack.setCustomSpacing(14, after: button)
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 72),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            button.heightAnchor.constraint(equalToConstant: 64)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        render(drop)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            if Tr3kLiveDropSheet.current === self {
                Tr3kLiveDropSheet.current = nil
            }
        }
    }

    func render(_ drop: Tr3kLiveDrop) {
        self.drop = drop
        let font = UIFont.systemFont(ofSize: 72, weight: .bold)
        headline.attributedText = NSAttributedString(
            string: Tr3kLiveDropCopy.headline(title: drop.title),
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .kern: -3.2
            ]
        )
        var config = UIButton.Configuration.filled()
        config.title = drop.kind.joinLabel
        config.baseBackgroundColor = .white
        config.baseForegroundColor = .black
        config.background.cornerRadius = 8
        config.cornerStyle = .fixed
        config.titleAlignment = .center
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 20, weight: .bold)
            outgoing.kern = 0.8
            return outgoing
        }
        button.configuration = config
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    @objc private func join() {
        Tr3kHaptics.play("selection")
        let url = drop.url
        let join = onJoin
        dismiss(animated: false) {
            join(url)
        }
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view).y
        switch pan.state {
        case .changed:
            if translation > 0 {
                view.transform = CGAffineTransform(translationX: 0, y: translation)
            }
        case .ended, .cancelled:
            let velocity = pan.velocity(in: view).y
            if translation > 120 || velocity > 900 {
                UIView.animate(withDuration: 0.16, animations: {
                    self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                }, completion: { _ in
                    self.dismiss(animated: false)
                })
            } else {
                UIView.animate(withDuration: 0.18) {
                    self.view.transform = .identity
                }
            }
        case .possible, .began, .failed:
            break
        @unknown default:
            break
        }
    }
}
