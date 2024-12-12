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
    @State private var friendListenerCall: BidirectionalStreamingCall<Service_FriendListenerMessage, Service_FriendStatusUpdate>? = nil
    
    // Friend List and Status
    @State private var friends: [String] = ["713bede9-e9a9-4c96-8038-04e3108ac403", "045bfce2-4859-4ae7-ba1d-82e34d8bb87f"]
    @State private var friendStatuses: [String: Bool] = [:]
    
    var body: some View {
        VStack {
            Text("GRPC Ping-Pong & Friend Listener")
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
            
            Text("Friend Statuses")
                .font(.headline)
            
            List {
                ForEach(friends, id: \.self) { friendID in
                    HStack {
                        Text("Friend: \(friendID)")
                        Spacer()
                        Text(friendStatuses[friendID] == true ? "🟢 Online" : "🔴 Offline")
                    }
                }
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
                
                // 🔥 Start Ping-Pong Communication
                startPingPong(client: client)
                
                // 🔥 Start Friend Listener
                startFriendListener(client: client)
                
            } catch {
                DispatchQueue.main.async {
                    serverResponse = "❌ Failed to connect: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// **Start the Ping-Pong Communication**
    func startPingPong(client: Service_ServerNIOClient) {
        let localCall = client.communicate { response in
            DispatchQueue.main.async {
                serverResponse = "📨 Ping from Server: \(response.message)"
                print("📨 Received Ping: \(response.message)")
            }
            
            if let call = self.call {
                sendPong(call: call)
            }
        }
        
        self.call = localCall
        
        // Send ClientHello message to initialize the connection
        var clientHello = Service_ClientHello()
        clientHello.clientID = "e6c1a465-2c03-4487-abf5-6f747d18fa7e"
        
        var clientMessage = Service_ClientMessage()
        clientMessage.clientHello = clientHello
        
        localCall.sendMessage(clientMessage).whenComplete { result in
            switch result {
            case .success:
                print("✅ Sent ClientHello message successfully")
            case .failure(let error):
                print("❌ Failed to send ClientHello message: \(error.localizedDescription)")
            }
        }
    }
    
    /// **Start the Friend Listener**
    func startFriendListener(client: Service_ServerNIOClient) {
        let localCall = client.friendListener { response in
            DispatchQueue.main.async {
                self.friendStatuses[response.clientID] = response.isOnline
            }
        }
        
        self.friendListenerCall = localCall
        
        // Send FriendList to initialize the friend listener
        var friendList = Service_FriendList()
        friendList.friendIds = friends
        
        var friendListenerMessage = Service_FriendListenerMessage()
        friendListenerMessage.friendList = friendList
        
        localCall.sendMessage(friendListenerMessage).whenComplete { result in
            switch result {
            case .success:
                print("✅ Sent FriendList message successfully")
            case .failure(let error):
                print("❌ Failed to send FriendList message: \(error.localizedDescription)")
            }
        }
    }
    
    /// **Disconnect from gRPC Server**
    func disconnectFromGRPCServer() {
        DispatchQueue.global().async {
            // Cancel the Ping-Pong call
            if let call = self.call {
                call.cancel(promise: nil)
                self.call = nil
                print("🔌 Call cancelled successfully")
            }
            
            // Cancel the Friend Listener call
            if let call = self.friendListenerCall {
                call.cancel(promise: nil)
                self.friendListenerCall = nil
                print("🔌 Friend Listener Call cancelled successfully")
            }
            
            // Close the gRPC channel
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
            
            // Shutdown the EventLoopGroup
            if let group = self.eventLoopGroup {
                try? group.syncShutdownGracefully()
                print("🔻 EventLoopGroup shutdown successfully")
                self.eventLoopGroup = nil
            }
            
            DispatchQueue.main.async {
                self.isConnected = false
                self.serverResponse = "🔴 Disconnected from gRPC Server"
                self.friendStatuses = [:] // Reset friend statuses
            }
        }
    }
    
    /// **Send Pong Message** — This function will send a Pong message as a response to the server's Ping
    func sendPong(call: BidirectionalStreamingCall<Service_ClientMessage, Service_Ping>) {
        var pong = Service_Pong()
        pong.status = .even // Hardcoding status as .even for now
        
        var clientMessage = Service_ClientMessage()
        clientMessage.pong = pong
        
        call.sendMessage(clientMessage).whenComplete { result in
            switch result {
            case .success:
                print("✅ Sent Pong message successfully")
            case .failure(let error):
                print("❌ Failed to send Pong message: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
}
