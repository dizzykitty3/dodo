import SwiftUI
import UIKit

extension View {
    func confirmSheetDismissal() -> some View { modifier(SheetDismissalGuard()) }

    func confirmUnsavedChanges(_ changed: Bool, pushed: Bool = false, closeTitle: String = "Cancel") -> some View {
        modifier(UnsavedChanges(changed: changed, pushed: pushed, closeTitle: closeTitle))
    }
}

private struct UnsavedChanges: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let changed: Bool
    let pushed: Bool
    let closeTitle: String
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .preference(key: UnsavedChangesKey.self, value: changed)
            .navigationBarBackButtonHidden(pushed && changed)
            .toolbar {
                if !pushed || changed {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(pushed ? "Back" : closeTitle, systemImage: pushed ? "chevron.backward" : "xmark") {
                            if changed { confirming = true } else { dismiss() }
                        }
                    }
                }
            }
            .alert("Discard unsaved changes?", isPresented: $confirming) {
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            }
    }

}
private struct UnsavedChangesKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct SheetDismissalGuard: ViewModifier {
    @State private var changed = false
    @State private var confirming = false
    @State private var closeSheet: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(UnsavedChangesKey.self) { changed = $0 }
            .interactiveDismissDisabled(changed)
            .background {
                if changed {
                    SheetDismissAttempt { close in
                        closeSheet = close
                        confirming = true
                    }
                }
            }
            .alert("Discard unsaved changes?", isPresented: $confirming) {
                Button("Discard Changes", role: .destructive) { closeSheet?() }
                Button("Keep Editing", role: .cancel) {}
            }
    }
}

// Install only while the visible editor is dirty. Forward unrelated presentation
// callbacks to SwiftUI and restore its delegate when the guard leaves the view.
private struct SheetDismissAttempt: UIViewControllerRepresentable {
    var attempted: (@escaping () -> Void) -> Void

    func makeUIViewController(context: Context) -> Observer { Observer() }
    func updateUIViewController(_ controller: Observer, context: Context) {
        controller.attempted = attempted
        controller.install()
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }
    static func dismantleUIViewController(_ controller: Observer, coordinator: ()) { controller.detach() }

    final class Observer: UIViewController, UIAdaptivePresentationControllerDelegate {
        var attempted: ((@escaping () -> Void) -> Void)?
        weak var observed: UIPresentationController?
        weak var previous: UIAdaptivePresentationControllerDelegate?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            detach()
        }
        func install() {
            var ancestor = parent
            var candidate: UIPresentationController?
            while let current = ancestor {
                if let presentation = current.presentationController {
                    candidate = presentation
                }
                ancestor = current.parent
            }
            guard let presentation = candidate, presentation.delegate !== self else { return }
            detach()
            observed = presentation
            previous = presentation.delegate
            presentation.delegate = self
        }
        func detach() {
            if let observed, observed.delegate === self { observed.delegate = previous }
            observed = nil
            previous = nil
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { false }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            attempted? { [weak presentationController] in
                presentationController?.presentedViewController.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
            }
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previous?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector)
        }
    }
}
