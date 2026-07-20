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
    private var workspaceViewController: UIViewController?
    private var workspaceAnalyzerWebView: WKWebView?
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

    private var rocketQueenReaderScript: String {
        return #"""
        (() => {
          "use strict";
          if (window.__LUMORAX_IOS_ROCKETQUEEN_BRIDGE__) return;
          window.__LUMORAX_IOS_ROCKETQUEEN_BRIDGE__ = true;
          let lastSignature = "";
          let lastHeartbeat = 0;
          let scheduled = false;
          function send(message) {
            try { window.webkit.messageHandlers.aviatorBridge.postMessage({ source:"lumorax-aviator", game:"rocketqueen", ...message }); } catch (_error) {}
          }
          function coefficient(value) {
            const text = String(value == null ? "" : value).replace(/\s+/g, "").replace(",", ".");
            const match = text.match(/^(?:x)?(\d+(?:\.\d+)?)(?:x)?$/i);
            if (!match) return null;
            const number = Number(match[1]);
            return Number.isFinite(number) && number >= 1 && number <= 100000 ? Number(number.toFixed(2)) : null;
          }
          function publish(values) {
            const clean = values.map(coefficient).filter(value => value !== null).slice(0, 80);
            if (clean.length < 3) return;
            const signature = clean.join("|");
            if (signature === lastSignature) return;
            lastSignature = signature;
            send({ type:"history", values:clean, ts:Date.now() });
          }
          function scanDOM() {
            scheduled = false;
            if (!document.documentElement) return;
            const groups = new Map();
            const nodes = document.querySelectorAll("span,div,button,li,p");
            for (let index = 0; index < nodes.length && index < 4500; index += 1) {
              const node = nodes[index];
              if (node.children.length) continue;
              const value = coefficient(node.textContent);
              if (value === null) continue;
              const rect = node.getBoundingClientRect();
              if (!rect.width || !rect.height) continue;
              const key = String(Math.round(rect.top / 18));
              if (!groups.has(key)) groups.set(key, []);
              groups.get(key).push({ left:rect.left, value });
            }
            let best = [];
            for (const entries of groups.values()) {
              if (entries.length < 3) continue;
              entries.sort((a,b) => a.left - b.left);
              const values = entries.map(entry => entry.value);
              if (values.length > best.length) best = values;
            }
            publish(best);
            const now = Date.now();
            if (now - lastHeartbeat > 5000) { lastHeartbeat = now; send({ type:"heartbeat", ts:now }); }
          }
          function schedule() {
            if (scheduled) return;
            scheduled = true;
            setTimeout(scanDOM, 120);
          }
          function fromPayload(payload) {
            let object = payload;
            try { if (typeof object === "string" && /^[\[{]/.test(object.trim())) object = JSON.parse(object); } catch (_error) { return; }
            if (!object || typeof object !== "object") return;
            const stack = [{ value:object, key:"", depth:0 }];
            while (stack.length) {
              const item = stack.pop();
              if (item.depth > 6 || item.value == null) continue;
              if (Array.isArray(item.value)) {
                if (/history|result|round|multiplier|coefficient|coef|crash/i.test(item.key)) {
                  publish(item.value.map(entry => entry && typeof entry === "object" ? (entry.multiplier ?? entry.coefficient ?? entry.coef ?? entry.crashPoint ?? entry.result) : entry));
                }
                for (const value of item.value.slice(0,100)) stack.push({ value, key:item.key, depth:item.depth + 1 });
              } else if (typeof item.value === "object") {
                for (const [key,value] of Object.entries(item.value)) stack.push({ value, key, depth:item.depth + 1 });
              }
            }
          }
          try {
            const NativeWebSocket = window.WebSocket;
            if (NativeWebSocket) {
              class ObservedWebSocket extends NativeWebSocket {
                constructor(...args) { super(...args); this.addEventListener("message", event => fromPayload(event.data)); }
              }
              window.WebSocket = ObservedWebSocket;
            }
          } catch (_error) {}
          const start = () => {
            try { new MutationObserver(schedule).observe(document.documentElement, { childList:true, subtree:true, characterData:true }); } catch (_error) {}
            schedule();
            setInterval(schedule, 1000);
          };
          if (document.documentElement) start(); else document.addEventListener("DOMContentLoaded", start, { once:true });
        })();
        """#
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == "aviatorControl" {
            let action = body["action"] as? String ?? ""
            if action == "open" { openAviator() }
            if action == "open-rocketqueen" { openRocketQueen() }
            if action == "close" { closeAviator() }
            if action == "open-game",
               let urlText = body["url"] as? String,
               let url = URL(string: urlText),
               isAllowedStandaloneGameURL(url) {
                openStandaloneGame(url: url, title: body["title"] as? String ?? "LIVE GAME")
            }
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
            let script = "window.postMessage(\(json), '*');"
            self?.analyzerWebView?.evaluateJavaScript(script, completionHandler: nil)
            self?.workspaceAnalyzerWebView?.evaluateJavaScript(script, completionHandler: nil)
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

    private func isAllowedStandaloneGameURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "one-vv1220.com" || host.hasSuffix(".one-vv1220.com")
    }

    private func openStandaloneGame(url: URL, title: String) {
        guard let root = window?.rootViewController, gameWebView == nil else { return }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let workspace = UIViewController()
        workspace.modalPresentationStyle = .fullScreen
        workspace.view.backgroundColor = .black

        let game = WKWebView(frame: workspace.view.bounds, configuration: configuration)
        game.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        game.uiDelegate = self
        game.navigationDelegate = self
        game.scrollView.contentInsetAdjustmentBehavior = .never
        workspace.view.addSubview(game)

        let header = UIView(frame: CGRect(x: 0, y: 0, width: workspace.view.bounds.width, height: 58))
        header.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        header.backgroundColor = UIColor.black.withAlphaComponent(0.82)

        let closeButton = UIButton(type: .system)
        closeButton.frame = CGRect(x: 10, y: 10, width: 100, height: 38)
        closeButton.setTitle("‹ GAMES", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .black)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        closeButton.layer.cornerRadius = 19
        closeButton.addTarget(self, action: #selector(closeAviator), for: .touchUpInside)
        header.addSubview(closeButton)

        let label = UILabel(frame: CGRect(x: 116, y: 10, width: max(80, workspace.view.bounds.width - 126), height: 38))
        label.autoresizingMask = [.flexibleWidth]
        label.text = title
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 15, weight: .black)
        header.addSubview(label)
        workspace.view.addSubview(header)

        workspaceViewController = workspace
        workspaceNavigation = header
        gameWebView = game
        root.present(workspace, animated: true)
        game.load(URLRequest(url: url))
    }
    private func openAviator() {
        guard let url = URL(string: "https://1w-ftend.life/casino/play/v_spribe:aviator") else { return }
        openCrashWorkspace(gameURL: url, analyzerPage: "aviator", readerScript: aviatorReaderScript, injectionTime: .atDocumentEnd)
    }

    private func openRocketQueen() {
        guard let url = URL(string: "https://one-vv1220.com/casino/play/v_1wingames:rocketqueen?p=yshe") else { return }
        openCrashWorkspace(gameURL: url, analyzerPage: "rocketqueen", readerScript: rocketQueenReaderScript, injectionTime: .atDocumentStart)
    }

    private func openCrashWorkspace(gameURL: URL, analyzerPage: String, readerScript: String, injectionTime: WKUserScriptInjectionTime) {
        guard let root = window?.rootViewController else { return }

        if gameWebView != nil {
            scrollToGame()
            relayBridgeStatus("bridge-ready")
            return
        }

        let analyzerContent = WKUserContentController()
        analyzerContent.add(self, name: "aviatorControl")
        let analyzerConfiguration = WKWebViewConfiguration()
        analyzerConfiguration.websiteDataStore = .default()
        analyzerConfiguration.userContentController = analyzerContent

        let mirror = WKWebView(frame: .zero, configuration: analyzerConfiguration)
        mirror.autoresizingMask = [.flexibleWidth]
        mirror.navigationDelegate = self
        mirror.scrollView.isScrollEnabled = false
        mirror.scrollView.contentInsetAdjustmentBehavior = .never
        mirror.backgroundColor = .black
        mirror.isOpaque = false

        let gameContent = WKUserContentController()
        gameContent.add(self, name: "aviatorBridge")
        gameContent.addUserScript(WKUserScript(source: readerScript, injectionTime: injectionTime, forMainFrameOnly: false))

        let gameConfiguration = WKWebViewConfiguration()
        gameConfiguration.websiteDataStore = .default()
        gameConfiguration.userContentController = gameContent
        gameConfiguration.allowsInlineMediaPlayback = true
        gameConfiguration.mediaTypesRequiringUserActionForPlayback = []

        let gameSection = UIView()
        gameSection.backgroundColor = .black
        gameSection.autoresizingMask = [.flexibleWidth]

        let game = WKWebView(frame: .zero, configuration: gameConfiguration)
        game.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        game.uiDelegate = self
        game.navigationDelegate = self
        game.scrollView.contentInsetAdjustmentBehavior = .never
        gameSection.addSubview(game)

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
        gameSection.addSubview(upButton)

        let workspace = UIViewController()
        workspace.modalPresentationStyle = .fullScreen
        workspace.view.backgroundColor = .black

        let scrollView = UIScrollView(frame: workspace.view.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.backgroundColor = .black
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addSubview(mirror)
        scrollView.addSubview(gameSection)
        workspace.view.addSubview(scrollView)

        workspaceViewController = workspace
        workspaceAnalyzerWebView = mirror
        workspaceScrollView = scrollView
        gameContainer = gameSection
        gameWebView = game
        installWorkspaceNavigation(in: workspace.view)
        layoutWorkspace(analyzerHeight: max(root.view.bounds.height * 1.55, 1080))

        if let analyzerURL = Bundle.main.url(forResource: analyzerPage, withExtension: "html", subdirectory: "public") {
            mirror.loadFileURL(analyzerURL, allowingReadAccessTo: analyzerURL.deletingLastPathComponent())
        }

        lastBridgeMessageAt = 0
        bridgeWasActive = false
        startBridgeWatchdog()

        game.load(URLRequest(url: gameURL))

        root.present(workspace, animated: true) { [weak self] in
            self?.refreshAnalyzerHeight()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.scrollToGame()
            }
        }
    }

    private func refreshAnalyzerHeight() {
        guard let analyzer = workspaceAnalyzerWebView else { return }
        let script = "Math.max(document.documentElement.scrollHeight || 0, document.body ? document.body.scrollHeight : 0)"
        analyzer.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            let measured = (result as? NSNumber)?.doubleValue ?? 0
            let minimum = self.workspaceViewController?.view.bounds.height ?? 800
            self.layoutWorkspace(analyzerHeight: max(CGFloat(measured), minimum))
        }
    }

    private func layoutWorkspace(analyzerHeight: CGFloat) {
        guard let workspace = workspaceViewController,
              let scrollView = workspaceScrollView,
              let analyzer = workspaceAnalyzerWebView,
              let container = gameContainer,
              let webView = gameWebView else { return }

        let width = scrollView.bounds.width
        analyzerSectionHeight = max(analyzerHeight, workspace.view.bounds.height)
        analyzer.frame = CGRect(x: 0, y: 0, width: width, height: analyzerSectionHeight)

        let gap: CGFloat = 16
        let gameHeight = max(workspace.view.bounds.height * 1.08, 780)
        container.frame = CGRect(x: 0, y: analyzerSectionHeight + gap, width: width, height: gameHeight)
        webView.frame = container.bounds
        scrollView.contentSize = CGSize(width: width, height: container.frame.maxY + workspace.view.safeAreaInsets.bottom + 24)
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

        gameWebView?.stopLoading()
        workspaceAnalyzerWebView?.stopLoading()
        gameWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "aviatorBridge")
        workspaceAnalyzerWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "aviatorControl")
        workspaceNavigation?.removeFromSuperview()
        workspaceViewController?.dismiss(animated: true)

        gameWebView = nil
        gameContainer = nil
        workspaceNavigation = nil
        workspaceScrollView = nil
        workspaceAnalyzerWebView = nil
        workspaceViewController = nil
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === workspaceAnalyzerWebView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refreshAnalyzerHeight() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshAnalyzerHeight() }
            return
        }
        if webView === gameWebView {
            relayBridgeStatus("bridge-ready")
        }
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