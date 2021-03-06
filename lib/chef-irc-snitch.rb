require 'rubygems'
require 'chef'
require 'chef/handler'
require 'net/http'
require 'uri'
require 'json'
require 'carrier-pigeon'

class IRCSnitch < Chef::Handler

  def initialize(irc_uri, github_user, github_token, ssl = false)
    @irc_uri = irc_uri
    @github_user = github_user
    @github_token = github_token
    @ssl = ssl
    @timestamp = Time.now.getutc
  end

  def fmt_run_list
    node.run_list.map {|r| r.type == :role ? r.name : r.to_s }.join(', ')
  end

  def fmt_gist
    ([ "Node: #{node.name} (#{node.ipaddress})",
       "Run list: #{node.run_list}",
       "All roles: #{node.roles.join(', ')}",
       "",
       "#{run_status.formatted_exception}",
       ""] +
     Array(backtrace)).join("\n")
  end

  def report

    if STDOUT.tty?
      Chef::Log.error("Chef run failed @ #{@timestamp}")
      Chef::Log.error("#{run_status.formatted_exception}")
    else
      Chef::Log.error("Chef run failed @ #{@timestamp}, snitchin' to chefs via IRC")

      gist_id = nil
      begin
        timeout(10) do
          res = Net::HTTP.post_form(URI.parse("http://gist.github.com/api/v1/json/new"), {
            "files[#{node.name}-#{@timestamp.to_i.to_s}]" => fmt_gist,
            "login" => @github_user,
            "token" => @github_token,
            "description" => "Chef run failed on #{node.name} @ #{@timestamp}",
            "public" => false
          })
          gist_id = JSON.parse(res.body)["gists"].first["repo"]
          Chef::Log.info("Created a GitHub Gist @ https://gist.github.com/#{gist_id}")
        end
      rescue Timeout::Error
        Chef::Log.error("Timed out while attempting to create a GitHub Gist")
      end

      message = "Chef failed on #{node.name} (#{fmt_run_list}): https://gist.github.com/#{gist_id}"

      begin
        timeout(10) do
          CarrierPigeon.send(:uri => @irc_uri, :message => message, :ssl => @ssl)
          Chef::Log.info("Informed chefs via IRC '#{message}'")
        end
      rescue Timeout::Error
        Chef::Log.error("Timed out while attempting to message Chefs via IRC")
      end
    end
  end

end
