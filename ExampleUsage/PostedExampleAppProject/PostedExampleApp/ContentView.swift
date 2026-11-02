import SwiftUI

struct ContentView: View {
    @ObservedObject private var demoState = PostedDemoState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("PostedSDK Example")
                    .font(.title)
                    .bold()

                Text("""
                The app calls reportInstall on launch. Delete and reinstall the app to report again. \
                The result is logged to Console under the com.postedapp.posted subsystem.
                """)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Log")
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

#Preview {
    ContentView()
}
