require "rubygems"
require "rspec"
require "yaml"
require "ostruct"
require File.dirname(__FILE__) + '/../loudbot'
require File.dirname(__FILE__) + '/../data/messages'

describe "loudbot.rb" do
  before(:each) do
    # Hack fake yaml data
    File.stub(:exists? => true)
    @data = {
      "FIRST" => Louds::Data::Message.new("FIRST", "Somebody"),
      "SECOND" => Louds::Data::Message.new("SECOND", "Another Person")
    }
    YAML.stub(:load_file => @data)

    # Set up fake data to ease IRC message tests
    @irc = double("Net::YAIL")
    @event = OpenStruct.new(:channel => "#ngs")
    @irc.stub(:msg)
  end

  describe "#init_data" do
    it "should retrieve messages" do
      @messages = nil
      init_data

      @messages.should be_kind_of(Louds::Data::Messages)

      @messages.instance_variable_get("@messages").should eq(@data)
      @messages.instance_variable_get("@random_messages").sort.should eq(["FIRST", "SECOND"])
    end
  end

  describe "#random_message" do
    before(:each) do
      @messages = Louds::Data::Messages.instance
      @message = Louds::Data::Message.new("foo", "bar")
      @messages.stub(:random => @message)
    end

    it "should spit out the text from @messages.random" do
      @messages.should_receive(:random).and_return(@message)
      @irc.should_receive(:msg).with("foo", @message.text)
      random_message("foo")
    end

    it "should tell the message it's been viewed" do
      @message.should_receive(:view!).once
      random_message("foo")
    end
  end

  describe "#incoming_message" do
    before(:each) do
      @logger = double("logger")
      @logger.stub(:debug)
      @irc.stub(:log => @logger)
      @messages = Louds::Data::Messages.instance
      self.stub(:random_message)

      @invalid_case         = "IT'S ONLY VALID IF ALL WORDS ARE UPPERCASE COMPLETELy"
      @invalid_length       = "LOUD SHORT"
      @invalid_no_vowels    = "TBBSSSDDDFFF FDDSSDJJKLLM FRTGBNMV"
      @invalid_vowels_only  = "AEIOUOUAEU AUIOEEIUO AUIOUA"
      @invalid_dupes        = "BINARY BINARY BINARY BINARY BOO"
      @invalid_words_length = "IS IT VALID NO"
      @invalid_letter_ratio = "THIS                                         ISN'T                                   VALID"
      @valid                = "THIS ISN'T FUNNY, BUT AT LEAST IT'S VALID!"
    end

    it "should ignore invalid stuff" do
      # YES THIS SHOULD DO BETTER TESTING DEAL WITH IT
      # TODO: Break up validations into methods so testing is actually sensible
      @messages.should_not_receive(:add)
      for text in [@invalid_case, @invalid_length, @invalid_no_vowels, @invalid_vowels_only, @invalid_dupes, @invalid_words_length, @invalid_letter_ratio]
        @event.message = text
        incoming_message(@event)
      end
    end

    it "should add valid phrase to message stash" do
      @event.nick = "Dude"
      @messages.should_receive(:add).with(@valid, "Dude")
      @event.message = @valid
      incoming_message(@event)
    end

    it "should ignore pms even if text is valid" do
      @messages.should_not_receive(:add)
      @event.stub(:pm? => true)
      @event.message = @valid
      incoming_message(@event)
    end
  end
end