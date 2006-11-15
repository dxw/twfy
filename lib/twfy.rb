require 'open-uri'
require 'json'
require 'cgi'
require 'ostruct'
require 'logger'

require File.join(File.dirname(__FILE__), 'data_element')

module Twfy
  
  VERSION = '1.0.0'
  BASE = URI.parse('http://www.theyworkforyou.com/api/')
  
  API_VERSION = '1.0.0'
  
  class Client
    
    class Error < ::StandardError; end
    class ServiceArgumentError < ::ArgumentError; end
    class APIError < ::StandardError; end
            
    def initialize(log_to=$stderr)
      @logger = Logger.new(log_to)
    end
    
    def log(message, level=:info)
      @logger.send(level, message) if $DEBUG
    end
    
    def convert_url(params={})
      service :convertURL, validate(params, :require => :url)
    end

    def constituency(params={})
      service :getConstituency, validate(params, :require => :postcode), Constituency
    end

    def constituencies(params={})
      service :getConstituencies, validate(params, :allow => [:date, :search, :longitude, :latitude, :distance]), Constituency
    end

    def mp(params={})
      service :getMP, validate(params, :allow => [:postcode, :constituency, :id, :always_return]), MP
    end

    def mp_info(params={})
      service :getMPInfo, validate(params, :require => :id)
    end

    def mps(params={})
      service :getMPs, validate(params, :allow => [:date, :search]), MP
    end

    def lord(params={})
      service :getLord, validate(params, :require => :id)
    end

    def lords(params={})
      service :getLords, validate(params, :allow => [:date, :search])
    end

    def geometry(params={})
      service :getGeometry, validate(params, :allow => :name), Geometry
    end

    def committee(params={})
      service :getCommittee, validate(params, :require => :name, :allow => :date)
    end

    def debates(params={})
      service :getDebates, validate(params, :require => :type, :require_one_of => [:date, :person, :search, :gid], :allow_dependencies => {
        :search => [:order, :page, :num],
        :person => [:order, :page, :num]
      })
    end
    
    def wrans(params={})
      service :getWrans, validate(params, :require_one_of => [:date, :person, :search, :gid], :allow_dependencies => {
        :search => [:order, :page, :num],
        :person => [:order, :page, :num]
      } )
    end
    
    def wms(params={})
      service :getWMS, validate(params, :require_one_of => [:date, :person, :search, :gid], :allow_dependencies => {
        :search => [:order, :page, :num],
        :person => [:order, :page, :num]
      } )
    end
    
    def comments(params={})
      service :getComments, validate(params, :allow => [:date, :search, :user_id, :pid, :page, :num])
    end
    
    def service(name, params={}, klass=OpenStruct)
      log "Calling service #{name}"
      url = BASE + name.to_s
      url.query = build_query(params)
      result = JSON.parse(url.read)
      log result.inspect
      unless result.kind_of?(Enumerable)
        raise Error, "Could not handle result: #{result.inspect}"
      end
      if result.kind_of?(Hash) && result['error']
        raise APIError, result['error'].to_s
      else
        structure result, klass
      end
    end
            
    #######
    private
    #######
    
    def validate(params, against)
      requirements = against[:require].kind_of?(Array) ? against[:require] : [against[:require]].compact
      allowed = against[:allow].kind_of?(Array) ? against[:allow] : [against[:allow]].compact
      require_one = against[:require_one_of].kind_of?(Array) ? against[:require_one_of] : [against[:require_one_of]].compact
      allow_dependencies = against[:allow_dependencies] || {}
      provided_keys = params.keys.map{|k| k.to_sym }
      
      # Add allowed dependencies
      allow_dependencies.each do |key,dependent_keys|
        dependent_keys = dependent_keys.kind_of?(Array) ? dependent_keys : [dependent_keys].compact
        allowed += dependent_keys if provided_keys.include?(key)
      end
      
      if (missing = requirements.select{|r| !provided_keys.include? r }).any?
        raise ServiceArgumentError, "Missing required params #{missing.inspect}"
      end
      
      if require_one.any?
        if (count = provided_keys.inject(0){|count,item| count + (require_one.include?(item) ? 1 : 0) }) < 1
          raise ServiceArgumentError, "Need exactly one of #{require_one.inspect}"
        elsif count > 1
          raise ServiceArgumentError, "Only one of #{require_one.inspect} allowed"
        end
      end
      
      unless (extra = provided_keys - (requirements + allowed + require_one)).empty?
        raise ServiceArgumentError, "Unknown params #{extra.inspect}"
      end
      
      params
    end
    
    def structure(value, klass)
      case value
      when Array
        value.map{|r| structure(r, klass) }
      when Hash
        if klass == Hash
          value
        else
          klass.ancestors.include?(DataElement) ? klass.new(self,value) : klass.new(value)
        end
      else
        result
      end
    end
    
    def build_query(params)
      params.update(:version=>API_VERSION)
      params.map{|set| set.map{|i| CGI.escape(i.to_s)}.join('=') }.join('&')
    end
        
  end
  
end