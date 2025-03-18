import SwiftUI
import WebKit
import Network

struct WebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var error: Error?
    @ObservedObject var networkMonitor: NetworkMonitor
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var webView: WKWebView?
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.error = nil
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            self.webView = webView
            
            // Inject JavaScript to handle fullscreen API
            let script = """
                document.querySelectorAll('video').forEach(function(video) {
                    video.addEventListener('webkitbeginfullscreen', function() {
                        window.webkit.messageHandlers.fullscreenHandler.postMessage('entered');
                    });
                    video.addEventListener('webkitendfullscreen', function() {
                        window.webkit.messageHandlers.fullscreenHandler.postMessage('exited');
                    });
                });
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.error = error
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.error = error
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        // Configure WKWebView with video playback support
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []  // Allow autoplay
        configuration.preferences.javaScriptEnabled = true
        
        // Add message handler for fullscreen events
        let userContentController = WKUserContentController()
        let handler = FullscreenMessageHandler()
        userContentController.add(handler, name: "fullscreenHandler")
        configuration.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Enable fullscreen support
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = false
        
        if networkMonitor.isConnected {
            // Load the local index.html with better error handling
            if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
                let baseURL = url.deletingLastPathComponent()
                webView.loadFileURL(url, allowingReadAccessTo: baseURL)
            } else {
                let error = NSError(domain: "WebViewError", 
                                  code: -1, 
                                  userInfo: [NSLocalizedDescriptionKey: "Could not find index.html in www directory"])
                self.error = error
                isLoading = false
            }
        } else {
            let error = NSError(domain: "WebViewError", 
                              code: -2, 
                              userInfo: [NSLocalizedDescriptionKey: "No internet connection available"])
            self.error = error
            isLoading = false
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Handle internet connectivity changes
        if !networkMonitor.isConnected {
            let error = NSError(domain: "WebViewError", 
                              code: -2, 
                              userInfo: [NSLocalizedDescriptionKey: "Internet connection lost"])
            self.error = error
            isLoading = false
        }
    }
}

// Fullscreen message handler
class FullscreenMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, 
                             didReceive message: WKScriptMessage) {
        if message.name == "fullscreenHandler" {
            if let messageBody = message.body as? String {
                print("Fullscreen state changed: \(messageBody)")
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        ZStack {
            WebView(isLoading: $isLoading, 
                   error: $error, 
                   networkMonitor: networkMonitor)
                .edgesIgnoringSafeArea(.all)
            
            if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            if let error = error {
                VStack {
                    Image(systemName: networkMonitor.isConnected ? 
                          "exclamationmark.triangle" : "wifi.slash")
                        .foregroundColor(.red)
                        .font(.largeTitle)
                    
                    Text(networkMonitor.isConnected ? 
                         "Error loading content" : "No Internet Connection")
                        .font(.headline)
                    
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    if !networkMonitor.isConnected {
                        Button("Retry") {
                            if networkMonitor.isConnected {
                                isLoading = true
                                error = nil
                                // Reload webview content
                            }
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 5)
            }
        }
    }
}

// Preview provider for SwiftUI canvas
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}