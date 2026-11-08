import SwiftUI
import UIKit

struct TaskTitleInput: UIViewRepresentable {
    @Binding var text: String
    let focusOnAppearance: Bool
    let focusRequest: Int
    let submit: () -> Void

    final class Input: UITextView {
        var initiallyFocused = false

        var handledFocusRequest = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && initiallyFocused {
                initiallyFocused = false
                becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Input {
        let view = Input()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .done
        view.accessibilityLabel = "Title"
        view.accessibilityIdentifier = "Title"
        view.initiallyFocused = focusOnAppearance
        return view
    }

    func updateUIView(_ view: Input, context: Context) {
        context.coordinator.input = self
        if view.handledFocusRequest != focusRequest {
            view.handledFocusRequest = focusRequest
            view.becomeFirstResponder()
        }
        if view.text != text { view.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Input, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitting.height, uiView.font?.lineHeight ?? 0))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var input: TaskTitleInput
        init(_ input: TaskTitleInput) { self.input = input }

        func textViewDidChange(_ textView: UITextView) {
            input.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement.contains(where: \.isNewline) else { return true }
            if replacement.count == 1 {
                input.submit()
            } else {
                let flattened = replacement.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
                if let start = view.position(from: view.beginningOfDocument, offset: range.location),
                   let end = view.position(from: start, offset: range.length),
                   let selection = view.textRange(from: start, to: end) {
                    view.replace(selection, withText: flattened)
                }
            }
            return false
        }
    }
}
