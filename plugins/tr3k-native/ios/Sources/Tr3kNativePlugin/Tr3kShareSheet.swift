import LinkPresentation
import UIKit

enum Tr3kShareSheet {
    static func present(title: String?, text: String?, urlString: String?, from presenter: UIViewController, completion: @escaping (Bool) -> Void) {
        let url = urlString.flatMap { URL(string: $0) }
        let item = Tr3kShareItem(title: title, text: text, url: url)
        guard item.hasContent else {
            completion(false)
            return
        }
        var items: [Any] = []
        if let text, !text.isEmpty, url != nil {
            items.append(text)
        }
        items.append(item)
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion(completed)
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            let bounds = presenter.view.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }
}

private final class Tr3kShareItem: NSObject, UIActivityItemSource {
    let title: String?
    let text: String?
    let url: URL?

    var hasContent: Bool {
        if let text, !text.isEmpty { return true }
        if url != nil { return true }
        if let title, !title.isEmpty { return true }
        return false
    }

    init(title: String?, text: String?, url: URL?) {
        self.title = title
        self.text = text
        self.url = url
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url ?? text ?? title ?? "Tr3k"
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if let url { return url }
        if let text, !text.isEmpty { return text }
        return title
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        if let title, !title.isEmpty { return title }
        return "Tr3k"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = (title?.isEmpty == false) ? title : "Tr3k"
        if let url {
            metadata.originalURL = url
            metadata.url = url
        }
        return metadata
    }
}
