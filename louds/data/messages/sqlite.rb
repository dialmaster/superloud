require "sqlite3"
lib 'data/messages'

module Louds
module Data

class Messages::SQLite < Messages
  # We expect to pull at least this many messages from sqlite
  MINIMUM_RETRIEVAL_SIZE = 100

  # We limit our query to no more than 100x the minimum set
  MAXIMUM_RETRIEVAL_SIZE = MINIMUM_RETRIEVAL_SIZE * 100

  def initialize(filename)
    # TODO: Figure out a smarter way to test for the messages table
    db_exists = FileTest.exists?(filename)

    super

    @db = SQLite3::Database.new(filename)
    @db.results_as_hash = true

    # Create the db if it doesn't exist
    if !db_exists
      sql = %Q|
        BEGIN;

        CREATE TABLE messages (
          id INTEGER PRIMARY KEY,
          text TEXT,
          author TEXT,
          score INTEGER,
          views INTEGER
        );

        CREATE INDEX messages_id_idx ON messages (id);
        CREATE UNIQUE INDEX messages_text_idx ON messages (text);
        CREATE INDEX messages_author_idx ON messages (author);
        CREATE INDEX messages_score_idx ON messages (score);
        CREATE INDEX messages_views_idx ON messages (views);

        COMMIT;
      |

      @db.execute_batch(sql)
    end

    # This hash maps our messages to their ids on load, so we can update by id instead of searching
    # message text to do the update
    @message_ids = {}
  end

  # Returns true if the item exists anywhere in our database
  def exists?(text)
    # First look for the item in memory
    return true if @messages[text]

    # If not in memory, since we don't always load everything, we have to check the db
    results = @db.execute("SELECT id FROM messages WHERE text = ?", text)
    return results.length > 0
  end

  def write_data
    # Add new messages
    for message in @new_messages
      statement = "INSERT INTO messages (text, score, author, views) VALUES (?, ?, ?, ?)"
      args = [statement, message.text, message.score, message.author, message.views]
      $stderr.puts(args.inspect)
      @db.execute(*args)
      $stderr.puts "Last autoinsert id: #{@db.last_insert_row_id}"
      message.instance_variable_set("@uid", @db.last_insert_row_id)
    end

    # Update changed messages
    for message in @changed_messages
      statement = "UPDATE messages SET score = ?, views = ? WHERE id = ?"
      args = [statement, message.score, message.views, message.uid]
      $stderr.puts(args.inspect)
      @db.execute(*args)
    end
  end

  # Uses our exciting scoring logic to determine what messages to pull for a given "round" of
  # messages.  First, we pull all messages from the DB one at a time, with a minimum score
  # threshold.
  def retrieve_messages
    # First, pull messages from the DB, favoring items with fewer views.  Skip anything
    # with a score of -10 or lower.
    results = @db.execute(%Q|
      SELECT id AS uid, text, score, author, views
      FROM messages WHERE score > -1
      ORDER BY views
      LIMIT #{MAXIMUM_RETRIEVAL_SIZE}
    |)

    # We don't really care about order - we use "ORDER BY views" simply to
    # ensure new items get into the list in the unlikely event that we actually
    # accumulate more than 10k messages
    results.shuffle!

    while results.length > MINIMUM_RETRIEVAL_SIZE
      # Take an item off the front of the stack
      message = results.shift

      # Everything gets a 100% chance at first
      weight = 1.00

      # Modify chance of keeping based on score.  This formula penalizes
      # 0-point louds significantly:
      #
      # * 0:  -0.433
      # * 1:  -0.097
      # * 2:  +0.065
      # * 3:  +0.159
      # * 4:  +0.221
      # * 5:  +0.265
      # * 10: +0.370
      # * 20: +0.433
      # * 50: +0.474
      weight += 0.50 - (2.0 / ((message["score"] + 2) ** 1.1))

      # Modify chance of keeping based on views to give a very high chance to
      # items not viewed, and stiff penalties to items viewed many times
      weight += (100.0 / ((9 + message["views"]) ** 2)) - 0.75

      # As a special case, 0-view louds get a 200% base chance since their
      # score/views are pretty meaningless
      weight = 2.0 if message["views"] == 0

      # We only want to pull MINIMUM_RETRIEVAL_SIZE items on average, so our final
      # modifier multiplies weight by the actual ratio of items to keep
      weight *= MINIMUM_RETRIEVAL_SIZE / results.count

      # If we decide to keep it, push this message to the back of the stack
      if rand < weight
        results.push message
      end
    end

    return results
  end
end

end
end
