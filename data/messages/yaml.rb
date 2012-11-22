require "yaml"
require File.expand_path(File.dirname(__FILE__) + '/../messages.rb')

module Louds
module Data
class Messages

class Louds::Data::Messages::YAML < Louds::Data::Messages
  # YAML-specific method for pulling data - returns an empty array if the YAML file isn't there
  def retrieve_messages
    return FileTest.exist?(@file) ? ::YAML.load_file(@file) : []
  end

  # Stores messages into a YAML file
  def serialize
    return unless dirty?

    # Convert from Message objects to raw hashes
    hashes = []
    @messages.each {|k, v| hashes.push v.to_hash}
    File.open(@file, "w") {|f| f.puts hashes.to_yaml}
    @dirty = false
  end
end

end
end
end