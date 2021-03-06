# This is a demonstration of net-yail just to see what a "real" bot could do without much work.
# Chances are good that you'll want to put things in classes and/or modules rather than go this
# route, so take this example with a grain of salt.
#
# Yes, this is a very simple copy of an existing "loudbot" implementation, but using YAIL to
# demonstrate the INCREDIBLE POWER THAT IS Net::YAIL.  Plus, plagiarism is a subset of the cool
# crime of stealing.
#
# Example of running this thing:
#     ruby bot_runner.rb --network irc.somewhere.org --channel "#bots"

require 'rubygems'
require 'net/yail'
require 'getopt/long'
require 'ostruct'

# Project-level includes all parts of the app expect - anything using classes in isolation should
# require this file first!
require "./utils/utils.rb"

# Hacks Array#shuffle and Array#shuffle! for people not using the latest ruby
lib 'lib/shuffle'

# Pulls in all of loudbot's methods - filter/callback handlers for IRC events
lib 'commands', 'loudbot'
lib 'loudbot'

# Set up RPS game
lib "rps/rps_object"
RPSObject.load_rps("rps/rps.yml")

# User specifies network, channel and nick
opt = Getopt::Long.getopts(
  ['--network', Getopt::REQUIRED],
  ['--channel', Getopt::REQUIRED],
  ['--nick', Getopt::REQUIRED],
  ['--port', Getopt::REQUIRED],
  ['--debug', Getopt::BOOLEAN],
  ['--ssl', Getopt::BOOLEAN]
)

# Create bot object
@irc = Net::YAIL.new(
  :address    => opt['network'],
  :username   => '2LOUD4U',
  :realname   => 'John Botfrakker',
  :port       => opt["port"],
  :nicknames  => [opt['nick'] || "SUPERLOUD"],
  :use_ssl    => opt["ssl"]
)

@ssl_users = Hash.new

# If --debug is passed on the command line, we spew lots of filth at the user
@irc.log.level = Logger::DEBUG if opt['debug']

# Initialize all louds data
init_data

# Init data which changes daily
init_daily_data

#####
#
# To learn the YAIL, begin below with attentiveness to commented wording
#
#####

# This is a filter.  Because it's past-tense ("heard"), it runs after the server's welcome message
# has been read - i.e., after any before-filters and the main handler happen.
@irc.heard_welcome { |e| @irc.join(opt['channel']) if opt['channel'] }

# on_xxx means it's a callback for an incoming event.  Callbacks run after before-filters, and
# replaces any existing incoming invite callback.  YAIL has very few built-in callbacks, so
# this is a safe operation.
@irc.on_invite { |e| @irc.join(e.channel) }

# This is just another callback, using the do/end block form.  We auto-message the channel on join,
# but only if the nick is @irc.me.  This is done using the conditional filtering syntax which makes
# code slightly shorter, but a lot less readable!  AWESOME!
@irc.on_join(:if => lambda {|e| e.nick == @irc.me}) do |e|
  @irc.msg(e.channel, "WHATS WRONG WITH BEING SEXY")
  @channel_list.push(e.channel)
end

@irc.heard_namreply do |e|
  names = e.msg.params[3].split(/\s+/)
  for nick in names
    nick = nick.sub(/^%/, "").sub(/^@/, "")
    @irc.whois(nick)
  end
end

@irc.heard_join(:if => lambda {|e| e.nick != @irc.me}) do |e|
  @irc.whois(e.nick)
end

@irc.heard_numeric_671 do |e|
  nick = e.msg.params[1].sub(/^%/, "").sub(/^@/, "")
  @ssl_users[nick] = true
  @irc.log.debug("Setting #{nick} as an SSL user")
end

@irc.heard_nick do |e|
  @ssl_users[e.message] = @ssl_users[e.nick]
  @ssl_users[e.nick] = false
  @irc.log.debug("New SSL list:")
  @irc.log.debug(@ssl_users.inspect)
end

# You should *never* override the on_ping callback unless you handle the PONG manually!!
# Filters, however, are perfectly fine.
#
# Here we're using the ping filter to actually do the serialization of our messages hash.  Since
# we know pings are regular, this is kind of a hack to serialize every few minutes.
@irc.heard_ping do
  @messages.serialize

  # Reset any daily stuffs
  if @last_ping_day != Date.today
    init_daily_data
  end
end

# This is a before-filter - using the present tense means it's a before-filter, and using a tense
# of "hear" means it's for incoming messages (as opposed to "saying" and "said", where we'd filter
# our outgoing messages).
#
# Intercept all potential commands (strings starting with a "bang", or exclamation mark)
# and send them to a method for command-handling.
@irc.hearing_msg do |e|
  (command, *params) = e.message.split(/\s+/)
  next unless command =~ /^!/

  command.sub!(/^!/, "")
  next unless command.upcase.strip == command

  do_command(e, command, params)
end

# Another filter, but in-line this time - we intercept messages directly to the bot.  The call to
# +handled!+ tells the event not to run any more filters or the main callback.
@irc.hearing_msg do |e|
  if e.message =~ /^#{@irc.me}/
    random_message(e.channel)
    e.handled!
  end
end

# This filter does some horrible trickery to fake event data when an alias
# regex matches the event.  This allows us to "dedupe" users who have multiple
# handles / logins.
@irc.hearing_msg do |e|
  @message = OpenStruct.new(:nick => e.nick, :prefix => e.msg.prefix, :user => e.msg.user, :host => e.msg.host)
  for regex,data in @aliases["patterns"]
    if e.msg.prefix =~ regex
      @irc.log.debug "Alias detected (#{regex.inspect})!"
      @message = OpenStruct.new(data)
    end
  end
end

# This is a magic filter that allows an optional *whitelist* of users to let
# through in case you have classics abusing your system.  Note that this
# requires a channel over which you have essentially complete control!
@irc.hearing_msg do |e|
  good = @whitelist_regexes == []
  for regex in @whitelist_regexes
    if e.msg.prefix =~ regex
      good = true
    end
  end

  if !good
    @irc.log.debug "Ignoring message: #{e.msg.prefix} didn't match any regex"
    e.handled!
  end
end

# Our first before-filter is declared last!  This is a bit confusing.  Maybe I'll change it.  Why
# did I do this???  Anyway, this filter ignores messages from anybody whose nick + host match any
# regex in ignores.txt.  Anything caught here is skipped prior to the above filters running.
#
# This simply checks nick + host against our ignores regexes, and calls +handled!+ to end the filter
# and callback chain on a match.  In other words, undesireable users' messages don't get handled by
# any of the below filters or handlers.
@irc.hearing_msg do |e|
  for regex in @ignore_regexes
    if e.msg.prefix =~ regex
      @irc.log.debug "Ignoring message: #{e.msg.prefix} matched #{regex.inspect}"
      e.handled!
      break
    end
  end
end

# This is our primary message callback.  We know our filters have caught people talking to us and
# any command-style messages, so we don't need to worry about those situations here.  The decision
# to make this the primary callback is pretty arbitrary - do what makes the most sense to you.
#
# Note that this is a proc-based filter - we handle the message entirely in incoming_message.
@irc.on_msg self.method(:incoming_message)

# Start the bot - the bang (!) calls the version of start_listening that runs an endless loop
@irc.start_listening!
