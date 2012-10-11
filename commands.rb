# THIS IS WHERE ALL OF MY COMMANDS LIVE PLEASE DO NOT CHANGE STUFF HERE UNLESS IT IS REALLY REALLY
# A DIRECT PART OF COMMANDS OKAY

# Commands we support
VALID_COMMANDS = [
  :dongme, :redongme, :upvote, :downvote, :score, :help, :rps, :biggestdong, :size, :sizeme
]

# RPS stuff is complicated enough to centralize all functionality in here
require "./rps/rps_command"

#####
# Command handlers
#####

def biggestdong(e, params)
  if @size_data.empty?
    @irc.msg(e.channel || e.nick, "ONOES NO DONGS TODAY SIRS")
    return
  end

  big_winner = Hash.new(0)
  tielist = Array.new
  for user_hash, data in @size_data
    if big_winner[:size] < data[:size]
      big_winner = data
      tielist = [data[:nick]]
    elsif (big_winner[:size] == data[:size])
      tielist.push(data[:nick])
    end
  end

  nick = big_winner[:nick]
  cm = big_winner[:size]
  inches = cm / 2.54

  tielist.sort!
  tie_text = case tielist.length
    when 2 then tielist.join(" AND ")
    else        tielist[0..-2].join(", ") + ", AND #{tielist.last}"
  end

  if (tielist.length <=1)
    @irc.msg(e.channel || e.nick, "THE BIGGEST I'VE SEEN TODAY IS #{nick.upcase}'S WHICH IS %0.1f INCHES (%d CM)" % [inches, cm])
  else
    @irc.msg(e.channel || e.nick, "THE BIGGEST I'VE SEEN TODAY IS... OMFG... IT'S A TIE BETWEEN #{tie_text.upcase}!  THEY'RE %s %0.1f INCHES (%d CM)!!!1!!" % [(tielist.length == 2 ? "BOTH" : "ALL"), inches, cm])
  end
end

def dongme(e, params)
  send_dong(e)
end

# Increments rerolls and sends inappropriate imagery
def redongme(e, params)
  # Clear old size data for this user
  @size_data[user_hash(e.msg)] = Hash.new(0)

  # Increment mulligan count
  @redongs[user_hash(e.msg)] += 1

  # Send a BRAND NEW DONG!!!
  send_dong(e)
end

# Votes the current message +1
def upvote(e, params)
  vote(1)
end

def downvote(e, params)
  vote(-1)
end

# Reports the last message's score
def score(e, params)
  if !@last_message
    @irc.msg(e.channel || e.nick, "NO LAST MESSAGE OR IT WAS DELETED BY !DOWNVOTE")
    return
  end

  @irc.msg(e.channel || e.nick, "#{@last_message}: #{@messages[@last_message]}")
end

def help(e, params)
  commands = VALID_COMMANDS.collect {|cmd| "!" + cmd.to_s.upcase}.join(" ")
  target = e.channel || e.nick
  send = lambda{|msg| @irc.msg(target, msg)}

  # Show generic help if no specific command is given
  if params.empty?
    send.call "I HAVE COMMANDS AND THEY ARE: #{commands}"
    return
  end

  # Two or more params == bad news
  if params.length > 1
    send.call "WTF ARE YOU DUMB?  I OFFER HELP FOR ONE COMMAND AT A TIME JERKFACE"
    return
  end

  # Only allow valid commands' sub-help
  unless VALID_COMMANDS.include?(params.first.downcase.to_sym)
    send.call "!#{params.first} IS NOT A COMMAND YOU TWIT"
    return
  end

  case params.first
    when "SIZE" then      send.call "!SIZE [USERNAME]: GIVES YOU THE ONLY THING THAT MATTERS ABOUT SOMEBODY: SIZE"
    when "SIZEME" then    send.call "!SIZEME: TELLS YOU IF YOU ARE WORTH ANYTHING TO SOCIETY"
    when "HELP" then      send.call "OH WOW YOU ARE SO META I AM SO IMPRESSED WE SHOULD GO HAVE SEX NOW"
    when "DONGME" then    send.call "!DONGME: SHOWS HOW MUCH OF A MAN YOU ARE"
    when "REDONGME" then  send.call "!REDONGME: LETS YOU TRY TO MAKE YOURSELF INTO MORE OF A MAN BUT WITH DANGER RISK!"
    else                  send.call "!#{params.first}: DOES SOMETHING AWESOME"
  end
end

# Reports anybody's current dong size
def size(e, params)
  if (params.empty?)
    help(e, ["SIZE"])
    return
  end

  name = params.first.upcase
  msg = nil

  for key, data in @size_data
    datanick = data[:nick].upcase
    if datanick == name
     cm = data[:size]
     inches = cm / 2.54
     fmt = name == e.nick.upcase ? "HEY %s YOUR DONG IS" : "%s'S DONG IS"
     msg = "#{fmt} %0.1f INCHES (%d CM)" % [name, inches, cm]
     break
    end
  end

  msg ||= "ONOES THERE IS NO DONG FOR #{name}"

  @irc.msg(e.channel || e.nick, msg.upcase)
end

# Reports users's current dong size
def sizeme(e, params)
  size(e, [e.nick])
end

#####
# Command helpers
#####

# Takes an event message and returns a semi-unique hash number representing the user + host
def user_hash(message)
  return message.user.hash + message.host.hash
end

# Computes and seeds RNG with the given event's user hash combined with today's date and optional
# added value, yields to the passed-in block, and then resets the seed to the old value.
def user_seed(user_hash, add)
  old_seed = srand(user_hash + Date.today.strftime("%Y%m%d").to_i + add)
  yield
  srand(old_seed)
end

# Computes size for a given event message.  Stores data into list of sizes for the day.
def compute_size(e)
  user_hash = user_hash(e.msg)
  mulligans = @redongs[user_hash]

  # -2 to size for each !REDONGME command
  size_modifier = mulligans * -2

  # Get size by using daily seed
  size = 0
  user_seed(user_hash, mulligans * 53) do
    size = [2, rand(20).to_i + 8 + size_modifier].max
  end

  @size_data[user_hash] = {:size => size, :nick => e.nick}

  return size
end

# Just keepin' the plagiarism alive, man.  At least in my version, size is always based on requester.
def send_dong(e)
  size = compute_size(e)
  @irc.msg(e.channel || e.nick, "8%sD" % ['=' * size])
end

# Adds +value+ to the score of the last message, if there was one.  If the score goes too low, we
# remove that message forever.
def vote(value)
  return unless @last_message

  @messages[@last_message] += value
  if @messages[@last_message] <= -1
    @messages.delete(@last_message)
    @last_message = nil
  end
  @dirty_messages = true
end
