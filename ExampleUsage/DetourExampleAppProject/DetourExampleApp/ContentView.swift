import SwiftUI
import PostedSDK

struct ContentView: View {
    @ObservedObject private var demoState = DetourDemoState.shared

    var body: some View {
        Group {
            if demoState.isResolvingInitialLink {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Resolving link...")
                        .font(.headline)
                    Text("Please wait")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PostedSDK ExampleUsage Template")
                            .font(.title)
                            .bold()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Last route: \(demoState.lastRoute)")
                            Text("Last link type: \(demoState.lastLinkType)")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Text("Links scenarios")
                            .font(.headline)

                        Text("Open the app from a custom scheme, universal link, or deferred deep link to see entries in the log.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("Analytics scenarios")
                            .font(.headline)

                        Button("Log typed event: add_to_cart") {
                            PostedAnalytics.logEvent(.addToCart, data: ["sku": "example-sku", "price": 129.0])
                            demoState.appendLog("[analytics] add_to_cart logged")
                        }

                        Button("Log custom event") {
                            PostedAnalytics.logEvent("promo_banner_tap", data: ["placement": "home_top"])
                            demoState.appendLog("[analytics] promo_banner_tap logged")
                        }

                        Button("Log retention event") {
                            PostedAnalytics.logRetention("day_7_return")
                            demoState.appendLog("[analytics] day_7_return retention logged")
                        }

                        Divider()

                        Text("Recent log")
                            .font(.headline)

                        ForEach(demoState.eventLog, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
