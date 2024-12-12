import SwiftUI
import GRPC
import NIO

struct ContentView: View {
    @State private var serverResponse: String = "Waiting for server response..."
    @State private var isConnected: Bool = false
    
    // gRPC-related properties
    @State private var eventLoopGroup: EventLoopGroup? = nil
    @State private var channel: GRPCChannel? = nil
    @State private var call: BidirectionalStreamingCall<Service_ClientMessage, Service_Ping>? = nil
    
    var body: some View {
        VStack {
            Text("GRPC Ping-Pong Client")
                .font(.title)
            
            Text(serverResponse)
                .font(.body)
                .padding()
            
            Button(action: {
                if isConnected {
                    disconnectFromGRPCServer()
                } else {
                    connectToGRPCServer()
                }
            }) {
                Text(isConnected ? "Disconnect from gRPC Server" : "Connect to gRPC Server")
                    .padding()
                    .background(isConnected ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding()
    }
    
    /// **Connect to gRPC Server**
    func connectToGRPCServer() {
        DispatchQueue.global().async {
            do {
                // 1. Create an EventLoopGroup for handling async work
                let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                self.eventLoopGroup = group
                
                // 2. Create a channel to the gRPC server
                let channel = try GRPCChannelPool.with(
                    target: .host("komaki.tech", port: 443),
                    transportSecurity: .tls(.makeClientConfigurationBackedByNIOSSL()),
                    eventLoopGroup: group
                )
                self.channel = channel
                
                // 3. Create the gRPC client
                let client = Service_ServerNIOClient(channel: channel)
                
                DispatchQueue.main.async {
                    serverResponse = "✅ Connected to gRPC Server!"
                    isConnected = true
                }
                
                // 4. Create the communication stream for Ping-Pong
                let localCall = client.communicate { response in
                    DispatchQueue.main.async {
                        serverResponse = "📨 Ping from Server: \(response.message)"
                        print("📨 Received Ping: \(response.message)")
                    }
                    
                    // 🔥 Send Pong back immediately after receiving Ping
                    if let call = self.call {
                        sendPong(call: call)
                    }
                }
                
                self.call = localCall
                
                // 5. Send the ClientHello message to initialize the connection
                var clientHello = Service_ClientHello()
                clientHello.clientID = "client_\(UUID().uuidString)"
                
                var clientMessage = Service_ClientMessage()
                clientMessage.clientHello = clientHello
                
                localCall.sendMessage(clientMessage).whenComplete { result in
                    switch result {
                    case .success:
                        print("✅ Sent ClientHello message successfully")
                        DispatchQueue.main.async {
                            serverResponse = "✅ Sent ClientHello to Server"
                        }
                    case .failure(let error):
                        print("❌ Failed to send ClientHello message: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            serverResponse = "❌ Failed to send ClientHello: \(error.localizedDescription)"
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
    
    /// **Disconnect from gRPC Server**
    func disconnectFromGRPCServer() {
        DispatchQueue.global().async {
            // 1. Cancel the call
            if let call = self.call {
                call.cancel(promise: nil)
                self.call = nil
                print("🔌 Call cancelled successfully")
            }
            
            // 2. Close the channel
            if let channel = self.channel {
                channel.close().whenComplete { result in
                    switch result {
                    case .success:
                        print("🔌 Channel closed successfully")
                    case .failure(let error):
                        print("❌ Failed to close channel: \(error.localizedDescription)")
                    }
                }
                self.channel = nil
            }
            
            // 3. Shutdown the EventLoopGroup
            if let group = self.eventLoopGroup {
                try? group.syncShutdownGracefully()
                print("🔻 EventLoopGroup shutdown successfully")
                self.eventLoopGroup = nil
            }
            
            // 4. Update the UI state
            DispatchQueue.main.async {
                self.isConnected = false
                self.serverResponse = "🔴 Disconnected from gRPC Server"
            }
        }
    }
    
    /// **Send Pong Message** — This function will send a Pong message as a response to the server's Ping
    /// - Parameter call: The active gRPC stream call
    func sendPong(call: BidirectionalStreamingCall<Service_ClientMessage, Service_Ping>) {
        // Create a Pong message
        var pong = Service_Pong()
        pong.status = .even // Hardcoding status as .even for now
        
        var clientMessage = Service_ClientMessage()
        clientMessage.pong = pong
        
        call.sendMessage(clientMessage).whenComplete { result in
            switch result {
            case .success:
                print("✅ Sent Pong message successfully")
                DispatchQueue.main.async {
                    serverResponse = "✅ Sent Pong in response to Ping"
                }
            case .failure(let error):
                print("❌ Failed to send Pong message: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    serverResponse = "❌ Failed to send Pong: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
