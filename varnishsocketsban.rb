#!/usr/bin/env ruby
# Copyright: mk(2011)  qi 
# Lincense: ....

require 'rubygems'
require 'sinatra'
require 'haml'
require 'socket'
require 'digest'
require 'uri/http'


class VarnishBanSocket
  
  def initialize(host='127.0.0.1',port=6082,secret=nil)
    @port = port
    @host = host 
    @secret = secret
    @debug = nil
  end
  
  def connect(host,port)
    begin
      socket = TCPSocket.new(@host, @port) 
    rescue Exception => e
       puts "Exception rescued : #{e}"
    ensure
      @connected = true if  ! e
      @socket = socket if ! e
    end
  end
  
  def disconnect
    @socket.close  if @socket
  end
  
  def on_connect
    connect @host,@port if ! @connected
  end
  
  def cmd(name, *params)
      on_connect
      status, length = @socket.gets.split 
      # authentication to login varnishadmin
      if  status == '107'
        challenge = @socket.read(length.to_i + 1).split("\n")[0]
        auth_response = Digest::SHA256.hexdigest(challenge + "\n" + @secret + challenge + "\n")
        @socket.write "auth #{auth_response}\n"
        status, length = @socket.gets.split 
        content = @socket.read(length.to_i + 1) 
        raise  "status #{status}: #{content}" if status.to_i != 200
      end
      @socket.write "#{name} #{params.join(' ').gsub('\\', '\\\\\\')}\n"
      status, length = @socket.gets.split  
      content = @socket.read(length.to_i + 1) # +1 = \n
      content
  end
  

  def ban(*args)
    c = 'ban'
    c << ".#{args.shift}" if [:url, :list].include?(args.first)
    response = cmd(c, *args)
    case c
    when 'ban.list'
      response.split("\n").map do |line|
        puts line
        a = line.split("\t")
        [a[0].to_i, a[1]]
      end
    else
       response
    end
  end

  def uri_banuri(url,fod='dir')
    uri = URI.parse("#{url}")
    case fod
    when 'dir'
         ban "req.http.host ~ #{uri.host} && req.url ~ #{uri.request_uri}"  
     when 'file'
         ban "req.http.host == #{uri.host} && req.url == #{uri.request_uri}"
     else
        raise  "argv error"
     end
  end
end



# ban app

before do
  content_type "text/html", :charset => "utf-8"
end

configure :production, :development do
  enable :logging
  enable :sessions
end

def getban(url,fod)
  @hosts = ['192.168.2.171', '192.168.2.172']
  @hosts.each do |host|
    @varnish = VarnishAdminSocket.new(host,nil,"7a480e77-3e1b-41b3-b4f4-f9f0b2ba6178\n")
    @value = @varnish.uri_banuri(url,fod)
    @value = @varnish.ban :list 
  end
  @value[1]
end

# routes for web interface
get '/' do
  redirect '/login' unless session[:currentuser]
  haml :home
end

get '/login' do
  haml :login
end

get '/logout' do
  session[:currentuser] = nil
  redirect '/login' 
end

post '/login' do
  if params[:name] == 'admin' and    params[:passwd] == 'admin'
    session[:currentuser] = 'mk'
    redirect '/'
  else
    redirect '/login' 
  end
end

get '/home' do
  haml :home
end

post '/purge' do
  haml :purge
end
    
# routes for api

post '/home' do
  if params[:username] == 'admin' && params[:password] == 'admin'
    if  params[:url] && params[:fod]
        return  getban("#{params[:url]}","#{params[:fod]}")
    else
       return "Two params need."
    end
  else
       return "Wront username or password"
  end
  puts "#{params[:username]} + #{params[:password]} + #{params[:url] } + #{params[:fod]}"
end

__END__
@@ layout
!!! 5
%html
  %head
    %title= "Your Website"
    %meta{ :content => "ban system ", :name => "description" }
    %meta{ :content => "root@mkrss.com", :name => "author" }
    %meta{ :content => "3 days", :name => "revisit-after" }    
  %body
    =yield
 
  
@@ login
#login
%form{ :action => "/login", :method => "post", :id=>"login" }
  %fieldset 
    %legend 用户登陆
    %ol
      %li
        %label{:for => "name"} 用户:
        %input{:type => "text", :name => "name", :class => "text"}
        %br
      %li
        %label{:for => "passwd"} 密码:
        %input{:type => "password", :name => "passwd", :class => "text"}
    %input{:type => "submit", :value => "login", :class => "button"}


@@ home
%form(action='/purge' method='post') 
  %fieldset 
    %legend 提交要清的地址
    %input(type='text' name= "@url" id="url")
    %input(type="radio" name = "@fod" value = "dir") dirs
    %input(type="radio" name = "@fod" value = "file") file
    %input(type='submit' value= "Submit")
 
%li
  %a(href="/logout") logout
  
@@ purge 
= getban("#{params[:@url]}","#{params[:@fod]}")
