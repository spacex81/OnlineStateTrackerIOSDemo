import Foundation
import GRPC
import NIO

final class GRPCManager: ObservableObject {
    
    // MARK: - Properties
    private var eventLoopGroup: EventLoopGroup?
    private var channel: GRPCChannel?
    private var pingPongCall: BidirectionalStreamingCall<Service_ClientMessage, Service_Ping>?
    private var friendListenerCall: BidirectionalStreamingCall<Service_FriendListenerMessage, Service_FriendStatusUpdate>?
    
    @Published var serverResponse: String = "Waiting for server response..."
    @Published var isConnected: Bool = false
    @Published var friendStatuses: [String: Bool] = [:]
    
    private var friends: [String] = ["713bede9-e9a9-4c96-8038-04e3108ac403", "045bfce2-4859-4ae7-ba1d-82e34d8bb87f"]
    
    // MARK: - Connect to gRPC Server
    func connect() {
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
                    self.serverResponse = "✅ Connected to gRPC Server!"
                    self.isConnected = true
                }
                
                // 🔥 Start Ping-Pong Communication
                self.startPingPong(client: client)
                
                // 🔥 Start Friend Listener
                self.startFriendListener(client: client)
                
            } catch {
                DispatchQueue.main.async {
                    self.serverResponse = "❌ Failed to connect: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Start the Ping-Pong Communication
    private func startPingPong(client: Service_ServerNIOClient) {
        let call = client.communicate { response in
            DispatchQueue.main.async {
                self.serverResponse = "📨 Ping from Server: \(response.message)"
                print("📨 Received Ping: \(response.message)")
            }
            
            if let call = self.pingPongCall {
                self.sendPong(call: call)
            }
        }
        
        self.pingPongCall = call
        
        // Send ClientHello message to initialize the connection
        var clientHello = Service_ClientHello()
        clientHello.clientID = "e6c1a465-2c03-4487-abf5-6f747d18fa7e"
        
        var clientMessage = Service_ClientMessage()
        clientMessage.clientHello = clientHello
        
        call.sendMessage(clientMessage).whenComplete { result in
            switch result {
            case .success:
                print("✅ Sent ClientHello message successfully")
            case .failure(let error):
                print("❌ Failed to send ClientHello message: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Start the Friend Listener
    private func startFriendListener(client: Service_ServerNIOClient) {
        let call = client.friendListener { response in
            DispatchQueue.main.async {
                self.friendStatuses[response.clientID] = response.isOnline
            }
        }
        
        self.friendListenerCall = call
        
        // Send FriendList to initialize the friend listener
        var friendList = Service_FriendList()
        friendList.friendIds = friends
        
        var friendListenerMessage = Service_FriendListenerMessage()
        friendListenerMessage.friendList = friendList
        
        call.sendMessage(friendListenerMessage).whenComplete { result in
            switch result {
            case .success:
                print("✅ Sent FriendList message successfully")
            case .failure(let error):
                print("❌ Failed to send FriendList message: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Disconnect from gRPC Server
    func disconnect() {
        DispatchQueue.global().async {
            // Cancel the Ping-Pong call
            if let call = self.pingPongCall {
                call.cancel(promise: nil)
                self.pingPongCall = nil
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
    
    // MARK: - Send Pong Message
    private func sendPong(call: BidirectionalStreamingCall<Service_ClientMessage, Service_Ping>) {
        let currentTimeMillis = Int64(Date().timeIntervalSince1970 * 1000)
        
        var pong = Service_Pong()
        pong.status = (currentTimeMillis % 2 == 0) ? .even : .odd
        
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
