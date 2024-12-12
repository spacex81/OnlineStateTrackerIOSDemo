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
    
    // MARK: - Connect to gRPC Server
    func connect(clientID: String, friends: [String]) {
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
                self.startPingPong(client: client, clientID: clientID)
                
                // 🔥 Start Friend Listener
                self.startFriendListener(client: client, friends: friends)
                
            } catch {
                DispatchQueue.main.async {
                    self.serverResponse = "❌ Failed to connect: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Start the Ping-Pong Communication
    private func startPingPong(client: Service_ServerNIOClient, clientID: String) {
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
        
        var clientHello = Service_ClientHello()
        clientHello.clientID = clientID
        
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
    private func startFriendListener(client: Service_ServerNIOClient, friends: [String]) {
        let call = client.friendListener { response in
            DispatchQueue.main.async {
                self.friendStatuses[response.clientID] = response.isOnline
            }
        }
        
        self.friendListenerCall = call
        
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
            self.pingPongCall?.cancel(promise: nil)
            self.pingPongCall = nil
            
            self.friendListenerCall?.cancel(promise: nil)
            self.friendListenerCall = nil
            
            self.channel?.close().whenComplete { _ in }
            self.channel = nil
            
            try? self.eventLoopGroup?.syncShutdownGracefully()
            self.eventLoopGroup = nil
            
            DispatchQueue.main.async {
                self.isConnected = false
                self.serverResponse = "🔴 Disconnected from gRPC Server"
                self.friendStatuses = [:]
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
