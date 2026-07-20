import UIKit
import Capacitor
import WebKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {

    var window: UIWindow?

    private weak var analyzerWebView: WKWebView?
    private var gameWebView: WKWebView?
    private var gameContainer: UIView?
    private var bridgeConfigured = false
    private var bridgeWatchdog: Timer?
    private var lastBridgeMessageAt: TimeInterval = 0
    private var bridgeWasActive = false
    private var workspaceScrollView: UIScrollView?
    private var workspaceNavigation: UIView?
    private weak var analyzerOriginalSuperview: UIView?
    private var analyzerOriginalFrame: CGRect = .zero
    private var analyzerOriginalScrollEnabled = true
    private var analyzerSectionHeight: CGFloat = 0

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DispatchQueue.main.async { [weak self] in self?.configureAviatorBridge() }
        return true
    }

    private func configureAviatorBridge() {
        guard !bridgeConfigured else { return }
        guard let root = window?.rootViewController as? CAPBridgeViewController else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.configureAviatorBridge() }
            return
        }
        _ = root.view
        guard let webView = root.webView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.configureAviatorBridge() }
            return
        }
        analyzerWebView = webView
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "aviatorControl")
        webView.configuration.userContentController.add(self, name: "aviatorControl")
        bridgeConfigured = true
    }

    private var aviatorReaderScript: String {
        return #"""
        (() => {
          "use strict";
          if(!/(^|\.)spribelaunch\.com$/i.test(location.hostname) &&
             !/(^|\.)spribegaming\.com$/i.test(location.hostname) &&
             !/(^|\.)spribe\.io$/i.test(location.hostname)) return;
          if(window.__LUMORAX_IOS_AVIATOR_BRIDGE__) return;
          window.__LUMORAX_IOS_AVIATOR_BRIDGE__ = true;

          let previousValues = [];
          let sequence = 0;
          let scheduled = false;
          let observer = null;
          let observedRoot = null;
          let emptyScans = 0;
          let lastHistoryAt = 0;
          let lastHeartbeatAt = 0;

          function send(message){
            try {
              window.webkit.messageHandlers.aviatorBridge.postMessage({
                source:"lumorax-aviator",
                ...message
              });
            } catch(_error) {}
          }

          function normalize(text){
            const match = String(text || "").trim().match(/^(\d+(?:[.,]\d+)?)x$/i);
            if(!match) return null;
            const value = Number(match[1].replace(",", "."));
            return Number.isFinite(value) && value >= 1 ? Number(value.toFixed(2)) : null;
          }

          function roots(){
            const all = [document];
            for(let index = 0; index < all.length; index += 1){
              all[index].querySelectorAll("*").forEach(node => {
                if(node.shadowRoot && !all.includes(node.shadowRoot)) all.push(node.shadowRoot);
              });
            }
            return all;
          }

          function currentValues(){
            const selectors = [
              ".payouts-wrapper .payout",
              "[class*='payouts-wrapper'] [class~='payout']",
              "[class*='payouts'] [class*='payout']"
            ];
            for(const root of roots()){
              for(const selector of selectors){
                const values = Array.from(root.querySelectorAll(selector))
                  .map(node => normalize(node.textContent))
                  .filter(value => value != null)
                  .slice(0, 120);
                if(values.length >= 2) return values;
              }
            }
            return [];
          }

          function sendHistory(reason = "periodic"){
            const values = currentValues();
            if(!values.length) return false;
            lastHistoryAt = Date.now();
            send({
              type:"history",
              values:values.slice().reverse(),
              batchId:"ios-spribe:" + lastHistoryAt,
              reason,
              ts:lastHistoryAt
            });
            return true;
          }

          function sameAtShift(current, previous, shift){
            const overlap = Math.min(previous.length, current.length - shift);
            if(overlap < Math.min(3, previous.length)) return false;
            for(let index = 0; index < overlap; index += 1){
              if(current[shift + index] !== previous[index]) return false;
            }
            return true;
          }

          function emit(coef){
            send({
              type:"coef",
              coef,
              roundKey:"ios-spribe:" + Date.now() + ":" + sequence++,
              ts:Date.now()
            });
          }

          function scan(){
            scheduled = false;
            const values = currentValues();
            if(!values.length){
              emptyScans += 1;
              if(emptyScans >= 10) previousValues = [];
              return;
            }
            emptyScans = 0;

            if(!previousValues.length){
              sendHistory("attached");
              previousValues = values;
              return;
            }

            if(values.length === previousValues.length &&
               values.every((value, index) => value === previousValues[index])) return;

            let newCount = -1;
            const maxShift = Math.min(40, values.length - 1);
            for(let shift = 0; shift <= maxShift; shift += 1){
              if(sameAtShift(values, previousValues, shift)){
                newCount = shift;
                break;
              }
            }

            if(newCount > 0){
              values.slice(0, newCount).reverse().forEach(emit);
            }else if(newCount < 0 && values[0] !== previousValues[0]){
              emit(values[0]);
              sendHistory("realigned");
            }
            previousValues = values;
          }

          function schedule(){
            if(scheduled) return;
            scheduled = true;
            setTimeout(scan, 80);
          }

          function ensureObserver(){
            if(observedRoot === document.documentElement && observer) return;
            if(observer) observer.disconnect();
            observedRoot = document.documentElement;
            if(!observedRoot) return;
            observer = new MutationObserver(schedule);
            observer.observe(observedRoot, { childList:true, subtree:true, characterData:true });
          }

          function keepAlive(){
            ensureObserver();
            schedule();
            const now = Date.now();
            if(now - lastHeartbeatAt >= 5000){
              lastHeartbeatAt = now;
              send({ type:"heartbeat", ts:now, url:location.href });
            }
            if(now - lastHistoryAt >= 15000) sendHistory("periodic");
          }

          window.addEventListener("pageshow", () => { previousValues = []; keepAlive(); });
          document.addEventListener("visibilitychange", () => { if(!document.hidden) keepAlive(); });
          ensureObserver();
          scan();
          setInterval(keepAlive, 1000);
        })();
        """#
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == "aviatorControl" {
            let action = body["action"] as? String ?? ""
            if action == "open" { openAviator() }
            if action == "close" { closeAviator() }
            return
        }

        guard message.name == "aviatorBridge",
              body["source"] as? String == "lumorax-aviator",
              let type = body["type"] as? String,
              ["history", "coef", "heartbeat"].contains(type) else { return }

        lastBridgeMessageAt = Date().timeIntervalSince1970
        bridgeWasActive = true
        relayToAnalyzer(body)
    }

    private func relayToAnalyzer(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.analyzerWebView?.evaluateJavaScript("window.postMessage(\(json), '*');", completionHandler: nil)
        }
    }

    private func relayBridgeStatus(_ type: String) {
        relayToAnalyzer([
            "source": "lumorax-aviator",
            "type": type,
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }

    private func startBridgeWatchdog() {
        bridgeWatchdog?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkBridgeHealth()
        }
        bridgeWatchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkBridgeHealth() {
        guard UIApplication.shared.applicationState == .active,
              let webView = gameWebView else { return }

        webView.evaluateJavaScript("document.readyState") { [weak webView] _, error in
            if error != nil { webView?.reload() }
        }

        guard bridgeWasActive else { return }
        let silence = Date().timeIntervalSince1970 - lastBridgeMessageAt
        if silence > 45 {
            bridgeWasActive = false
            relayBridgeStatus("bridge-reconnecting")
            webView.reload()
        }
    }

    private func openAviator() {
        guard let root = window?.rootViewController,
              let analyzer = analyzerWebView else { return }

        if gameWebView != nil {
            scrollToGame()
            relayBridgeStatus("bridge-ready")
            return
        }

        let content = WKUserContentController()
        content.add(self, name: "aviatorBridge")
        content.addUserScript(WKUserScript(source: aviatorReaderScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = content
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let container = UIView()
        container.backgroundColor = .black
        container.autoresizingMask = [.flexibleWidth]

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        container.addSubview(webView)

        let upButton = UIButton(type: .system)
        upButton.setTitle("↑ ANALYZER", for: .normal)
        upButton.setTitleColor(.white, for: .normal)
        upButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .black)
        upButton.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        upButton.layer.cornerRadius = 18
        upButton.layer.borderWidth = 1
        upButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        upButton.frame = CGRect(x: 12, y: 12, width: 118, height: 36)
        upButton.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        upButton.addTarget(self, action: #selector(scrollToAnalyzer), for: .touchUpInside)
        container.addSubview(upButton)

        let scrollView = UIScrollView(frame: root.view.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.backgroundColor = .black
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never

        analyzerOriginalSuperview = analyzer.superview
        analyzerOriginalFrame = analyzer.frame
        analyzerOriginalScrollEnabled = analyzer.scrollView.isScrollEnabled
        analyzer.removeFromSuperview()
        analyzer.translatesAutoresizingMaskIntoConstraints = true
        analyzer.autoresizingMask = [.flexibleWidth]
        analyzer.scrollView.isScrollEnabled = false

        scrollView.addSubview(analyzer)
        scrollView.addSubview(container)
        root.view.addSubview(scrollView)

        workspaceScrollView = scrollView
        gameContainer = container
        gameWebView = webView
        installWorkspaceNavigation(in: root.view)
        layoutWorkspace(analyzerHeight: max(root.view.bounds.height * 1.55, 1080))
        refreshAnalyzerHeight()

        lastBridgeMessageAt = 0
        bridgeWasActive = false
        startBridgeWatchdog()

        if let url = URL(string: "https://1w-ftend.life/casino/play/v_spribe:aviator") {
            webView.load(URLRequest(url: url))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.scrollToGame()
        }
    }

    private func refreshAnalyzerHeight() {
        guard let analyzer = analyzerWebView else { return }
        let script = "Math.max(document.documentElement.scrollHeight || 0, document.body ? document.body.scrollHeight : 0)"
        analyzer.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            let measured = (result as? NSNumber)?.doubleValue ?? 0
            let minimum = self.window?.rootViewController?.view.bounds.height ?? 800
            self.layoutWorkspace(analyzerHeight: max(CGFloat(measured), minimum))
        }
    }

    private func layoutWorkspace(analyzerHeight: CGFloat) {
        guard let root = window?.rootViewController,
              let scrollView = workspaceScrollView,
              let analyzer = analyzerWebView,
              let container = gameContainer,
              let webView = gameWebView else { return }

        let width = scrollView.bounds.width
        analyzerSectionHeight = max(analyzerHeight, root.view.bounds.height)
        analyzer.frame = CGRect(x: 0, y: 0, width: width, height: analyzerSectionHeight)

        let gap: CGFloat = 16
        let gameHeight = max(root.view.bounds.height * 1.08, 780)
        container.frame = CGRect(x: 0, y: analyzerSectionHeight + gap, width: width, height: gameHeight)
        webView.frame = container.bounds
        scrollView.contentSize = CGSize(width: width, height: container.frame.maxY + root.view.safeAreaInsets.bottom + 24)
    }

    private func installWorkspaceNavigation(in rootView: UIView) {
        workspaceNavigation?.removeFromSuperview()
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 250, height: 42))
        bar.center = CGPoint(x: rootView.bounds.midX, y: rootView.safeAreaInsets.top + 29)
        bar.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleBottomMargin]
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        bar.layer.cornerRadius = 21
        bar.layer.borderWidth = 1
        bar.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor

        let analyzerButton = makeWorkspaceButton(title: "↑ ANALYZER", frame: CGRect(x: 4, y: 4, width: 119, height: 34))
        analyzerButton.addTarget(self, action: #selector(scrollToAnalyzer), for: .touchUpInside)
        bar.addSubview(analyzerButton)

        let gameButton = makeWorkspaceButton(title: "↓ GAME", frame: CGRect(x: 127, y: 4, width: 119, height: 34))
        gameButton.addTarget(self, action: #selector(scrollToGame), for: .touchUpInside)
        bar.addSubview(gameButton)

        rootView.addSubview(bar)
        workspaceNavigation = bar
    }

    private func makeWorkspaceButton(title: String, frame: CGRect) -> UIButton {
        let button = UIButton(type: .system)
        button.frame = frame
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .black)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        button.layer.cornerRadius = 17
        return button
    }

    @objc private func scrollToAnalyzer() {
        workspaceScrollView?.setContentOffset(.zero, animated: true)
    }

    @objc private func scrollToGame() {
        guard let scrollView = workspaceScrollView else { return }
        let target = CGPoint(x: 0, y: max(0, analyzerSectionHeight + 16))
        scrollView.setContentOffset(target, animated: true)
    }

    @objc private func closeAviator() {
        bridgeWatchdog?.invalidate()
        bridgeWatchdog = nil

        let analyzer = analyzerWebView
        analyzer?.removeFromSuperview()
        gameWebView?.stopLoading()
        gameWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "aviatorBridge")
        gameWebView?.removeFromSuperview()
        workspaceNavigation?.removeFromSuperview()
        workspaceScrollView?.removeFromSuperview()

        if let analyzer, let originalSuperview = analyzerOriginalSuperview {
            analyzer.translatesAutoresizingMaskIntoConstraints = true
            analyzer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            analyzer.frame = originalSuperview.bounds
            analyzer.scrollView.isScrollEnabled = analyzerOriginalScrollEnabled
            originalSuperview.addSubview(analyzer)
        }

        gameWebView = nil
        gameContainer = nil
        workspaceNavigation = nil
        workspaceScrollView = nil
        analyzerOriginalSuperview = nil
        analyzerSectionHeight = 0
        bridgeWasActive = false
        lastBridgeMessageAt = 0
    }
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === gameWebView else { return }
        bridgeWasActive = false
        relayBridgeStatus("bridge-reconnecting")
        webView.reload()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        application.isIdleTimerDisabled = false
    }

    func applicationDidEnterBackground(_ application: UIApplication) {}

    func applicationWillEnterForeground(_ application: UIApplication) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let webView = self.gameWebView else { return }
            webView.evaluateJavaScript("document.readyState") { _, error in
                if error != nil { webView.reload() }
            }
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.isIdleTimerDisabled = true
    }

    func applicationWillTerminate(_ application: UIApplication) {}

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}