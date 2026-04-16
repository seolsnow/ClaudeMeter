import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let onLoginComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoginComplete: onLoginComplete)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.setMainWebView(webView)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

        if let url = URL(string: "https://claude.ai/login") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onLoginComplete: () -> Void
        private var didComplete = false
        private var popupWindow: NSWindow?
        private var popupWebView: WKWebView?
        private weak var mainWebView: WKWebView?
        private var urlObservation: NSKeyValueObservation?

        private static let authPaths = ["/login", "/signup", "/oauth", "/auth", "/verify"]

        init(onLoginComplete: @escaping () -> Void) {
            self.onLoginComplete = onLoginComplete
        }

        deinit {
            urlObservation?.invalidate()
        }

        func setMainWebView(_ webView: WKWebView) {
            self.mainWebView = webView
            // Observe URL changes so SPA pushState/replaceState transitions
            // are detected without polling.
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, change in
                guard let self, !self.didComplete else { return }
                guard let newURL = change.newValue ?? nil else { return }
                self.handleNavigation(to: newURL)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didComplete else { return }
            guard let url = webView.url else { return }
            handleNavigation(to: url)
        }

        private func handleNavigation(to url: URL) {
            guard url.host == "claude.ai" else { return }
            let isOnAuthPage = Self.authPaths.contains(where: { url.path.hasPrefix($0) })
            if !isOnAuthPage {
                syncCookiesAndComplete()
            }
        }

        // MARK: - WKUIDelegate (handle OAuth popups)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Open OAuth popup in a real NSWindow so passkey/WebAuthn dialogs work.
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.customUserAgent = webView.customUserAgent

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Sign in"
            win.contentView = popup
            win.center()
            win.isReleasedWhenClosed = false
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            self.popupWindow = win
            self.popupWebView = popup
            return popup
        }

        /// Called when the popup calls window.close() — clean up.
        func webViewDidClose(_ webView: WKWebView) {
            if webView === popupWebView {
                popupWindow?.close()
                popupWindow = nil
                popupWebView = nil
            }
        }

        // MARK: - Cookie sync

        func syncCookiesAndComplete() {
            guard !didComplete else { return }
            didComplete = true
            urlObservation?.invalidate()
            urlObservation = nil
            popupWindow?.close()
            popupWindow = nil
            popupWebView = nil

            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                for cookie in claudeCookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.onLoginComplete()
                }
            }
        }
    }
}

/// Opens a standalone NSWindow for Claude login (avoids MenuBarExtra popover dismissal).
@MainActor
final class LoginWindowController {
    static let shared = LoginWindowController()
    private var window: NSWindow?

    func open(onComplete: @escaping () -> Void) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView:
            VStack(spacing: 0) {
                HStack {
                    Text("Log in to Claude")
                        .font(.headline)
                    Spacer()
                    Button("Done") { [weak self] in
                        self?.syncCookiesAndClose(onComplete: onComplete)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                LoginWebView {
                    onComplete()
                    DispatchQueue.main.async { [weak self] in
                        self?.close()
                    }
                }
            }
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Log in to Claude"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    /// Sync cookies from WKWebView before closing — covers the case where
    /// SPA routing prevented automatic detection.
    private func syncCookiesAndClose(onComplete: @escaping () -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            for cookie in claudeCookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            DispatchQueue.main.async { [weak self] in
                onComplete()
                self?.close()
            }
        }
    }

    func close() {
        window?.close()
        window = nil
    }
}
