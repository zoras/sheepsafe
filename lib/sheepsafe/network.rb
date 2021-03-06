module Sheepsafe
  class Network
    def initialize(config = nil)
      @data = YAML.load(`/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport -I`.gsub(/^\s*([^:]+)/, '"\1"'))
      @config = config || Sheepsafe::Config.new({})
    end

    def trusted?
      @config.trusted_names.include?(current_ssid) ||
        @config.trusted_names.include?(current_bssid)
    end

    def up?
      @data['AirPort'] != false
    end

    def current_ssid
      @data['SSID']
    end

    def current_bssid
      @data['BSSID']
    end
  end
end
