module MadChatter
  
  class Server
    
    def initialize(config)
      @config = config
      @server = initialize_server
      @subscribers = {};
    end
    
    def self.main_channel
      @main_channel ||= EventMachine::Channel.new
    end
    
    def initialize_server
      # TODO: Figure out a better (more flexible/dynamic) way to initialize the server class
      if @config['websocket_backend'] && @config['websocket_backend'] == 'MadChatter::Servers::EventMachineWebSocket'
        return MadChatter::Servers::EventMachineWebSocket.new(@config['websocket_port'], self)
      end
      
      raise 'You did not specify a valid class name for websocket_backend'
    end
  
    def start
      EM.run do
        puts "Starting Mad Chatter Web Socket server on port #{@config['websocket_port']}."
        @server.start
      end
    end
    
    def register_connection(&send_message)
      subscriber_id = MadChatter::Server.main_channel.subscribe(send_message)
      token = generate_token
      send_message.call(MadChatter::Message.new('token', token).to_json)
      @subscribers[subscriber_id] = token
      MadChatter::MessageHistory.all.each do |json|
        send_message.call(json)
      end
      subscriber_id
    end
    
    def generate_token
      Digest::SHA1.hexdigest(Time.now.to_s)
    end
    
    def connection_closed(id)
      token = @subscribers.delete(id)
      username = MadChatter::Users.find_username_by_token(token)
      MadChatter::Server.main_channel.unsubscribe(id)
      MadChatter::Users.remove(token)
      MadChatter::Server.send_json(MadChatter::Message.new('status', "#{username} has left the chatroom").to_json)
      MadChatter::Server.send_json(MadChatter::Message.new('users', MadChatter::Users.current).to_json)
    end
    
    def message_received(json)
      msg = JSON.parse(json)
      username = MadChatter::Users.find_username_by_token(msg['token'])
      message = MadChatter::Message.new(msg['type'], msg['message'], msg['token'], username)
      message.filter
      
      if message.token.nil?
        return # Token is required to send messages
      end
      
      begin
        MadChatter.message_listeners.each do |listener|
          listener.handle(message)
        end
        
        MadChatter::Server.send_json(message.to_json)
      rescue RuntimeError
        # dont need to do anything, just prevent any errors from stopping the server
      end
    end

    def self.send_json(json)
      MadChatter::Server.main_channel.push(json)
      MadChatter::MessageHistory.add(json)
    end
    
  end

end
