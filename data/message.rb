module Louds
module Data

class Message
  attr_reader :author, :views, :score, :text
  attr_accessor :container

  include Comparable

  # Loads a message's attributes from a hash
  def self.from_hash(hsh)
    hsh[:score] ||= 1
    hsh[:views] ||= 0
    msg = Message.new(hsh[:text], hsh[:author], hsh[:score], hsh[:views])

    return msg
  end

  def initialize(text, author, score = 1, views = 0)
    @text = text
    @author = author
    @views = views
    @score = score
  end

  def view!
    @views += 1
    @container.dirty!
  end

  def upvote!
    @score += 1
    @container.dirty!
  end

  def downvote!
    @score -= 1
    @container.dirty!
  end

  # Converts all important attributes to a hash of data, primarily to ease exporting
  def to_hash
    return { :author => @author, :views => @views, :score => @score, :text => @text }
  end

  # Comparisons are somewhat meaningless, but they allow easier operations like == and simple
  # sorting by text
  def <=>(message)
    for field in [:text, :score, :views, :author]
      val = self.send(field) <=> message.send(field)
      return val unless val.zero?
    end

    return 0
  end
end

end
end