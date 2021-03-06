module Sheepsafe
  class Installer
    PLIST_FILE = File.expand_path("~/Library/LaunchAgents/sheepsafe.plist")

    attr_reader :config, :status, :controller

    def initialize
      require 'highline/import'
      @config = File.readable?(Sheepsafe::Config::FILE) ? Sheepsafe::Config.new : Sheepsafe::Config.new({})
      @status = Sheepsafe::Status.new(@config)
      @controller = Sheepsafe::Controller.new @config, @status, Logger.new(Sheepsafe::Controller::LOG_FILE)
      update_config_with_status
    end

    def run
      intro_message
      config_prompts
      manual_network_location_prompt
      setup_untrusted_location
      write_config
      write_launchd_plist
      register_launchd_task
      announce_done
    end

    def intro_message
      say(<<-MSG)
Welcome to Sheepsafe!

So you want to protect yourself from FireSheep snoopers like me, eh?
Follow the prompts to get started.
MSG
    end

    def config_prompts
      say "First thing we need is the name of a server you can reach via SSH."

      config.ssh_host = ask "SSH connection (server name or user@server) >\n" do |q|
        q.default = config.ssh_host
      end

      say "Testing connectivitity to #{config.ssh_host}..."
      system "ssh #{config.ssh_host} true"
      unless $?.success?
        abort "Sorry! that ssh host was no good."
      end

      config.socks_port = ask "Ok, next we need to pick a port on localhost where the proxy runs >\n" do |q|
       q.default = config.socks_port || 9999
      end

      config.trusted_location = ask "Next, a name for the \"trusted\" network location >\n" do |q|
        q.default = config.trusted_location
      end

      config.trusted_names = ask "Next, one or more network names (blank line to stop, RET for #{@names.inspect}) >\n" do |q|
        q.gather = ""
      end
      config.trusted_names = @names if config.trusted_names.empty?
    end

    def manual_network_location_prompt
      say "Next, I need you to create and switch to the \"Untrusted\" location in Network preferences."
      system "open /System/Library/PreferencePanes/Network.prefPane"
      ask "Press ENTER when done."
    end

    def setup_untrusted_location
      if agree "Next, I'll set up the SOCKS proxy in the \"Untrusted\" location for you. OK\? (yes/no)\n"
        system "networksetup -setsocksfirewallproxy AirPort localhost #{config.socks_port}"
      end
    end

    def write_config
      say "Saving configuration to #{Sheepsafe::Config::FILE}..."
      config.write
    end

    # Write a launchd plist file to .~/Library/LaunchAgents/sheepsafe.plist.
    #
    # For details see http://tech.inhelsinki.nl/locationchanger/
    def write_launchd_plist
      say "Setting up launchd configuration file #{PLIST_FILE}..."
      plist = <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
	"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>org.rubygems.sheepsafe</string>
	<key>ProgramArguments</key>
	<array>
		<string>#{sheepsafe_bin_path}</string>
	</array>
	<key>WatchPaths</key>
	<array>
		<string>/Library/Preferences/SystemConfiguration</string>
	</array>
        <!-- We specify PATH here because /usr/local/bin, where grownotify -->
        <!-- is usually installed, is not in the script path by default. -->
        <key>EnvironmentVariables</key>
        <dict>
                <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/bin</string>
        </dict>
</dict>
</plist>
PLIST
      File.open(PLIST_FILE, "w") {|f| f << plist }
    end

    # Register the task with launchd.
    def register_launchd_task
      say "Registering #{PLIST_FILE}"
      system "launchctl load #{PLIST_FILE}"
    end

    def announce_done
      controller.run   # Choose the right network and get things going
      say("Sheepsafe installation done!")
    end

    def uninstall
      if controller.proxy_running?
        say "Shutting down SOCKS proxy..."
        controller.bring_socks_proxy 'down'
      end
      if File.exist?(PLIST_FILE)
        say "Uninstalling Sheepsafe from launchd..."
        system "launchctl unload #{PLIST_FILE}"
        File.unlink PLIST_FILE rescue nil
      end
      Dir['~/.sheepsafe.*'].each {|f| File.unlink f rescue nil}
      say "Uninstall finished."
    end

    private
    def update_config_with_status
      unless config.trusted_location
        config.trusted_location = status.current_location
      end
      @names = [status.current_network.current_ssid, status.current_network.current_bssid]
    end

    def sheepsafe_bin_path
      begin
        Gem.bin_path('sheepsafe')
      rescue Exception
        File.expand_path('../../../bin/sheepsafe', __FILE__)
      end
    end
  end
end
