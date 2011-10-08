# Stores a LOUD message into the hash and responds.
def it_was_loud(message, channel)
  @irc.log.debug "IT WAS LOUD!  #{message.inspect}"

  @messages[message] ||= 1
  random_message(channel)
end

# This is our main message handler.
#
# We store and respond if messages meet the following criteria:
# * It is long (11 characters or more)
# * It has at least one space
# * It has no lowercase letters
# * At least 60% of the characters are uppercase letters
def incoming_message(e)
  # We don't respond to "private" messages
  return if e.pm?

  text = e.message

  return if text =~ /[a-z]/

  # Count various exciting things
  len = text.length
  uppercase_count = text.scan(/[A-Z]/).length
  space_count = text.scan(/\s/).length

  if len >= 11 && uppercase_count >= (len * 0.60) && space_count >= 1 && text !~ /retard/i
    it_was_loud(e.message, e.channel)
  end
end

# Pulls a random message from our messages array and sends it to the given channel.  Reshuffles
# the main array if the randomized array is empty.
def random_message(channel)
  @random_messages = @messages.keys.shuffle if @random_messages.empty?
  @last_message = @random_messages.pop
  @irc.msg(channel, @last_message)
end

# Handles a command (string begins with ! - to keep with the pattern, I'm making our loudbot only
# respond to loud commands)
def do_command(command, e)
  # Commands must be all-caps
  return unless command =~ /\A[A-Z]+\Z/

  # Convert to a method symbol
  command = command.downcase.to_sym

  # If valid, send it off
  if VALID_COMMANDS.include?(command)
    method = self.method(command)
    method.call(e)
  end

  # Here we're saying that we don't want any other handling run - no filters, no handler.  For
  # commands, I put this here because I know I don't want any other handlers having to deal with
  # strings beginning with a bang.
  e.handled!
end
