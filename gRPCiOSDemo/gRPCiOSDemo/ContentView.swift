import SwiftUI

struct ContentView: View {
    @StateObject private var grpcManager = GRPCManager()
    
    @State private var clientID: String = "e6c1a465-2c03-4487-abf5-6f747d18fa7e"
    @State private var friends: [String] = [
        "713bede9-e9a9-4c96-8038-04e3108ac403",
        "045bfce2-4859-4ae7-ba1d-82e34d8bb87f"
    ]
    
    var body: some View {
        VStack {
            Text("GRPC Ping-Pong & Friend Listener")
                .font(.title)
            
            Text(grpcManager.serverResponse)
                .font(.body)
                .padding()
            
            Button(action: {
                if grpcManager.isConnected {
                    grpcManager.disconnect()
                } else {
                    grpcManager.connect(clientID: clientID, friends: friends)
                }
            }) {
                Text(grpcManager.isConnected ? "Disconnect from gRPC Server" : "Connect to gRPC Server")
                    .padding()
                    .background(grpcManager.isConnected ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Spacer()
            
            Text("Friend Statuses")
                .font(.headline)
            
            List {
                ForEach(grpcManager.friendStatuses.keys.sorted(), id: \ .self) { friendID in
                    HStack {
                        Text("Friend: \(friendID)")
                        Spacer()
                        Text(grpcManager.friendStatuses[friendID] == true ? "🟢 Online" : "🔴 Offline")
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
