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
    private var analyzerHasState = false
    private var latestHistory: [String: Any]?

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

          function currentValues(){
            return Array.from(document.querySelectorAll(".payouts-wrapper .payout"))
              .map(node => normalize(node.textContent))
              .filter(value => value != null)
              .slice(0, 120);
          }

          function sameAtShift(current, previous, shift){
            const overlap = Math.min(previous.length, current.length - shift);
            const minimum = Math.min(3, previous.length);
            if(overlap < minimum) return false;
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
            if(!values.length) return;

            if(!previousValues.length){
              send({
                type:"history",
                values:values.slice().reverse(),
                batchId:"ios-spribe:" + Date.now()
              });
              previousValues = values;
              return;
            }

            if(values.length === previousValues.length &&
               values.every((value, index) => value === previousValues[index])) return;

            let newCount = -1;
            const maxShift = Math.min(20, values.length - 1);
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
            }
            previousValues = values;
          }

          function schedule(){
            if(scheduled) return;
            scheduled = true;
            setTimeout(scan, 80);
          }

          new MutationObserver(schedule).observe(document.documentElement, {
            childList:true,
            subtree:true,
            characterData:true
          });
          scan();
          setInterval(schedule, 1000);
        })();
        """#
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == "aviatorControl" {
            let action = body["action"] as? String ?? ""
            if let hasState = body["hasState"] as? Bool { analyzerHasState = hasState }
            if action == "open" { openAviator() }
            if action == "close" { closeAviator() }
            return
        }

        guard message.name == "aviatorBridge",
              body["source"] as? String == "lumorax-aviator",
              let type = body["type"] as? String else { return }

        if type == "history" {
            latestHistory = body
            if !analyzerHasState {
                relayToAnalyzer(body)
                analyzerHasState = true
            }
        } else if type == "coef" {
            relayToAnalyzer(body)
        }
    }

    private func relayToAnalyzer(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.analyzerWebView?.evaluateJavaScript("window.postMessage(\(json), '*');", completionHandler: nil)
        }
    }

    private func openAviator() {
        guard gameWebView == nil,
              let root = window?.rootViewController else { return }

        let content = WKUserContentController()
        content.add(self, name: "aviatorBridge")
        content.addUserScript(WKUserScript(source: aviatorReaderScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = content
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let container = UIView(frame: root.view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.backgroundColor = .black

        let webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        container.addSubview(webView)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("‹ ANALYZER", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .black)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        closeButton.layer.cornerRadius = 18
        closeButton.layer.borderWidth = 1
        closeButton.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        closeButton.frame = CGRect(x: 12, y: max(12, root.view.safeAreaInsets.top + 6), width: 112, height: 36)
        closeButton.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        closeButton.addTarget(self, action: #selector(closeAviator), for: .touchUpInside)
        container.addSubview(closeButton)

        root.view.addSubview(container)
        gameContainer = container
        gameWebView = webView

        if let url = URL(string: "https://1w-ftend.life/casino/play/v_spribe:aviator") {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func closeAviator() {
        gameWebView?.stopLoading()
        gameWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "aviatorBridge")
        gameWebView?.removeFromSuperview()
        gameContainer?.removeFromSuperview()
        gameWebView = nil
        gameContainer = nil
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

    func applicationWillResignActive(_ application: UIApplication) {
        application.isIdleTimerDisabled = false
    }

    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}

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
