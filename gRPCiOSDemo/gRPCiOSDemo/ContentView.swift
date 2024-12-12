import SwiftUI
import GRPC
import NIO
import Combine

struct ContentView: View {
    @State private var serverResponse: String = "No response yet"
    
    var body: some View {
        VStack {
            Text("gRPC Server Response:")
                .font(.headline)
            
            Text(serverResponse)
                .padding()
                .multilineTextAlignment(.center)
            
            Button(action: connectToGRPCServer) {
                Text("Connect to gRPC Server")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
    
    /// Connects to the gRPC server and fetches user info
    func connectToGRPCServer() {
        DispatchQueue.global().async {
            do {
                // 1. Create an EventLoopGroup for handling async work
                let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                
                // 2. Create a channel to the gRPC server
                let channel = try GRPCChannelPool.with(
                    target: .host("komaki.tech", port: 443),
                    transportSecurity: .tls(.makeClientConfigurationBackedByNIOSSL()),
                    eventLoopGroup: group
                )
                
                // 3. Create the gRPC client
                let client = Service_ServerClient(channel: channel)
                
                // 4. Call GetAllUserInfo from your service
                let request = Service_Empty()
                let call = client.getAllUserInfo(request)
                
                call.response.whenComplete { result in
                    switch result {
                    case .success(let response):
                        let users = response.users.map { $0.clientID }
                        DispatchQueue.main.async {
                            serverResponse = "Users: \(users.joined(separator: ", "))"
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            serverResponse = "❌ Error: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    serverResponse = "❌ Failed to connect: \(error.localizedDescription)"
                }
            }
        }
    }
}



#Preview {
    ContentView()
}
