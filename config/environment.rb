require 'oj'
require 'sinatra'
require 'mongoid'
require 'tzinfo'
require 'rubberband'

class Environment

  def self.config
    @config ||= YAML.load_file File.join(File.dirname(__FILE__), "config.yml")
  end

  # special fields used by the system, cannot be used on a model (on the top level)
  def self.magic_fields
    [
      :fields,
      :order, :sort, 
      :page, :per_page,
      
      :query, # query.fields
      :search, # tokill

      :citing, # citing.details
      :citation, :citation_details, # tokill

      :explain, 
      :format, # undocumented XML support

      :apikey, # API key gating
      :callback, :_, # jsonp support (_ is to allow cache-busting)
      :captures, :splat # Sinatra keywords to do route parsing
    ]
  end

end


# insist on my API-wide timestamp format
Time::DATE_FORMATS.merge!(:default => Proc.new {|t| t.xmlschema})


# workhorse API handlers
require './queryable'
require './searchable'


configure do
  # configure mongodb client
  Mongoid.load! File.join(File.dirname(__FILE__), "mongoid.yml")
  
  Searchable.configure_clients!
  
  # This is for when people search by date (with no time), or a time that omits the time zone
  # We will assume users mean Eastern time, which is where Congress is.
  Time.zone = ActiveSupport::TimeZone.find_tzinfo "America/New_York"

  # insist on using the time format I set as the Ruby default,
  # even in dependent libraries that use MultiJSON (e.g. rubberband)
  Oj.default_options = {mode: :compat, time_format: :ruby}
end

@all_models = []
Dir.glob('models/*.rb').each do |filename|
  load filename
  model_name = File.basename filename, File.extname(filename)
  @all_models << model_name.camelize.constantize
end

def all_models
  @all_models
end

def queryable_models
  @queryable_models ||= all_models.select {|model| model.respond_to?(:queryable?) and model.queryable?}
end

def queryable_route
  @queryable_route ||= /^\/(#{queryable_models.map {|m| m.to_s.underscore.pluralize}.join "|"})$/
end

def searchable_models
  @search_models ||= all_models.select {|model| model.respond_to?(:searchable?) and model.searchable?}
end

def searchable_route
  @search_route ||= /^\/search\/((?:(?:#{searchable_models.map {|m| m.to_s.underscore.pluralize}.join "|"}),?)+)$/
end