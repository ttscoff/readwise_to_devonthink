#!/usr/bin/env ruby
require 'English'
require 'json'
require 'date'
require 'fileutils'
require 'optparse'

# Reader articles with highlights become searchable text with annotations in DEVONthink.
#
# - Gets new highlights on schedule using launchd
# - Adds Markdown file for urls, bookmarks for other types
# - Adds finder comments and annotations with highlighted text and their notes and tags, with a link to the Reader highlight
# - Highlights text in Markdown documents, full paragraph, using CriticMarkup
# - Can merge new highlights
#
# ### Installation/Usage
#
# 1. Save script to disk
# 2. Edit config options hash below with API key and preferences
# 3. Make script executable, `chmod a+x /path/to/readwise_to_devonthink.rb`
# 4. Run script once to get all previous highlights, `/path/to/readwise_to_devonthink.rb`
# 5. Set up a launchd job to run script at desired interval
#
# ### Notes
#
# In lieu of setting config options in the script, you can pass them as command line options:
#
# - Pass the token with the `--token` option
# - Pass the type with the `--type` option
# - Pass database and group with `--database` and `--group` options
#
# ### Caveats
#
# - does not handle deletions
# - does not highlight images
#
# ### Changelog
#
# 2025-02-09:
# - Add debug and verbose options
# - Better search for existing notes (remove punctuation that breaks search)
# - Add --quiet option to suppress output
# - Highlight only selected text instead of whole paragraph
# - Sort highlights by position

options = {
  # Readwise API token, required, see <https://readwise.io/access_token>
  token: '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
  # Type to save urls as, :markdown is default and preferred
  # Can also be :bookmark, :archive, or :pdf
  # Highlighting can only be done on :markdown types
  type: :markdown,
  # Database name, global is default
  database: 'global',
  # Group name or inbox, inbox is default
  group: 'inbox'
}

LAST_UPDATE = File.expand_path("~/.local/share/devonthink/readwise_last_update")

module Term
  class << self
    def silent
      @silent ||= false
    end

    def silent=(silent)
      @silent = silent ? true : false
    end

    def debug
      @debug ||= 0
    end

    def debug=(level)
      if level >= 2
        @debug = 2
      else
        @debug = level
      end
    end

    def log(message = nil, verbose = nil, level: :info)
      return if debug == 0

      if message
        case level
        when :error
          warn "ERROR: #{message}"
        when :info
          warn "INFO: #{message}"
        else
          warn "DEBUG: #{message}"
        end
      end

      warn "\n#{verbose}" if verbose && debug == 2
    end

    # Print a message to STDERR unless Term.silent is true
    def warn(message)
      return if silent

      STDERR.puts message
    end
  end
end

# String extensions
class ::String
  # Remove all non-alphanumeric characters
  def no_punc
    gsub(/[^a-z0-9 ]/i, ' ').gsub(/ +/, ' ').strip
  end

  def fix_unicode
    gsub(/\\u2014/, '[-—]+')
      .gsub(/\\u2018/, '‘')
      .gsub(/\\u2019/, '’')
      .gsub(/\\u201c/, '“')
      .gsub(/\\u201d/, '”')
  end

  def greedy
    gsub(/\(http.*?\)/, '!')
    .gsub(/[^a-z0-9\-—]+/i, '.*?')
    .gsub(/(\.\*\? *)+/, '.*?')
  end

  # Make string searchable as regex
  def content_rx
    Regexp.escape(fix_unicode)
      .gsub(/[^a-z0-9\-—‘’“”,!?:;.*()\/\\\s]+/i, '.*?').gsub(/(\.\*\? *)+/, '.*?')
  end

  # Normalize type
  #
  # @return [Symbol] type
  def normalize_type
    case downcase
    when /(^b|loc$)/
      :bookmark
    when /^a/
      :archive
    when /^p/
      :pdf
    else
      :markdown
    end
  end

  # Escape special characters for AppleScript
  def e_as
    to_s.gsub(/(?=["\\])/, '\\')
  end

  # Convert to Markdown blockquote
  #
  # @return [String] Markdown blockquote
  def block_quote
    split(/\n/).map { |s| "> #{s}" }.join("\n")
  end

  # Convert to Markdown italicized text, line by line
  #
  # @return [String] Markdown italicized text
  def italicize
    split(/\n/).map { |s| s.strip.empty? ? '' : "_#{s}_" }.join("\n")
  end

  #
  # Some fixes for Marky output
  #
  # - Removes metadata to be replaced by this script's metadata
  def marky_fix
    content = strip.scrub
    content.gsub!(/^(date|title|tags|source|description):.*?\n/, '')
    content.strip
  end

  #
  # Discard invalid characters and output a UTF-8 String
  #
  # @return     [String] UTF-8 encoded string
  #
  def scrub
    encode('utf-16', invalid: :replace).encode('utf-8')
  end

  #
  # Destructive version of #utf8
  #
  # @return     [String] UTF-8 encoded string, in place
  #
  def scrub!
    replace scrub
  end

  # Remove all non-ASCII characters from a string
  #
  # @example
  #  \u00fe\u00ffEhlers \u0013Danlos Syndrome - Wikipedia".ascii
  #  # => "Ehlers Danlos Syndrome - Wikipedia"
  #
  # @note Replaces common non-ASCII punctuation with their ASCII equivalents, strips the rest
  #
  # @return [String] a new string with only ASCII characters
  def ascii
    # See String#encode documentation
    encoding_options = {
      invalid: :replace, # Replace invalid byte sequences
      undef: :replace, # Replace anything not defined in ASCII
      replace: '', # Use a blank for those replacements
      universal_newline: true # Always break lines with \n
    }

    gsub(/[\u0080-\u00ff]/, '')
      .gsub(/[—–]/, '-')
      .gsub(/[“”]/, '"')
      .gsub(/[‘’]/, "'")
      .gsub(/…/, '...')
      .gsub(/[\u2018-\u2019]/, "'")
      .gsub(/[\u201C-\u201D]/, '"')
      .gsub(/\u2026/, '...')
      .gsub(/\u00A0/, ' ')
      .gsub(/\u00A9/, '(c)')
      .gsub(/\u00AE/, '(r)')
      .gsub(/\u2122/, '(tm)')
      .gsub(/\u2014/, '--')
      .gsub(/\u2015/, '---')
      .gsub(/\u2010/, '-')
      .gsub(/[\u2011-\u2012]/, '-')
      .encode(Encoding.find('ASCII'), **encoding_options)
      .chars.reject { |char| char.ascii_only? && (char.ord < 32 || char.ord == 127) }.join
  end

  # Strip Markdown formatting
  #
  # @return [String] stripped text
  def strip_markdown
    gsub(/!?\[(.*?)\]([(\[].*?[\])])/, '\1')
      .gsub(/(\*+)(.*?)\1/, '\2')
      .gsub(/(_+)(.*?)\1/, '\2')
      .gsub(/^#+ */, '')
      .gsub(/^(> *)+/, '')
  end

  # Check if a line matches any of the highlights
  #
  # @param highlights [Array<Highlight>] highlights to check
  #
  # @return [Boolean] true if line matches a highlight
  def matches_highlight(highlights)
    matches = false
    highlights.each_with_index do |highlight, i|
      next if highlight.text.scrub.strip_markdown.empty?

      if strip_markdown =~ /#{highlight.text.scrub.strip_markdown.content_rx}/
        matches = i
        break
      end
    end

    matches
  end

  # Formats text as a markdown highlight
  #
  # @param highlight [String] The text to be formatted as a highlight
  # @return [String] The text wrapped in markdown highlight syntax {== ==}
  # @example
  #   highlight("some text")
  #   # => "{==some text==}"
  # @note Strips existing highlight markers if present
  def highlight(highlight)
    rx = /(\{==)?\[?#{highlight.text.fix_unicode.greedy}[.?!;:]*([\])][\[(].*?[)\]])?(==\})?[.?!;:]*/im
    gsub(/(\{==|==\})/, '').gsub(rx, '{==\0==}')
    # "{==#{gsub(/(\{==|==\})/, '')}==}"
    # if (highlight.note && !highlight.note.whitespace_only?) || (highlight.tags && !highlight.tags.empty?)
    #   comment = []
    #   comment << highlight.note if highlight.note && !highlight.note.whitespace_only?
    #   comment << highlight.tags.to_hashtags if highlight.tags && !highlight.tags.empty?
    #   out << "{>>#{comment.join(" ")}<<}"
    # end
  end

  # Highlight paragraphs in Markdown containing a highlight
  # Takes an array of highlight definitions and applies highlighting to non-empty
  # lines that match any of the highlight patterns.
  #
  # @param highlights [Array<Hash>] An array of Highlight objects
  # @return [String] The text with highlighting applied, lines joined with newlines
  def highlight_markdown(highlights)
    lines = dup.scrub.split(/\n/)
    output = []
    lines.each do |line|
      m = line.matches_highlight(highlights)
      output << if m && !line.whitespace_only?
                  line.highlight(highlights[m])
                else
                  line
                end
    end

    output.join("\n")
  end

  # Convert to Markdown blockquote
  #
  # @return [String] Markdown blockquote
  def block_quote
    split(/\n/).map { |s| "> #{s}" }.join("\n")
  end

  # Convert to Markdown italicized text, line by line
  #
  # @return [String] Markdown italicized text
  def italicize
    split(/\n/).map { |s| s.strip.empty? ? '' : "_#{s}_" }.join("\n")
  end

  # Test if a string is empty or whitespace only
  def whitespace_only?
    strip.empty?
  end

  # Merge two strings, line by line, removing repeats
  #
  # @param other [String] other string to merge
  #
  # @return [String] merged string
  def merge(other)
    mine = split(/\n/).delete_if(&:whitespace_only?)
    other = other.split(/\n/).delete_if(&:whitespace_only?)

    other.each do |line|
      mine << line unless mine.include?(line)
    end

    mine.join("\n\n")
  end
end

class Highlight
  attr_reader :text, :note, :tags, :location, :url

  # Initialize a new highlight object
  #
  # @param options [Hash] The options to create the highlight with
  # @option options [String] :text The text of the highlight
  # @option options [String] :note Any notes associated with the highlight
  # @option options [Array<String>] :tags Array of tags for the highlight
  # @option options [String] :location The location/source of the highlight
  # @option options [String] :url The Readwise URL for the highlight
  # @return [void]
  def initialize(options)
    @text = options[:text]
    @note = options[:note]
    @tags = options[:tags]
    @location = options[:location]
    @url = options[:url]
  end

  # Converts the highlight and its metadata to a Markdown string
  #
  # @return [String] A formatted Markdown string containing:
  #   - highlight text
  #   - note (if present) formatted as a blockquote
  #   - tags (if present) formatted with hashtags
  #   - source URL as a Markdown link
  #
  # @example
  #   highlight.to_md
  #   # => "Highlight text
  #
  #        > Note text
  #        Tags: #tag1 #tag2
  #
  #        - [Highlight link](http://example.com)"
  def to_md
    out = []
    out << @text
    out << @note.block_quote if @note && !@note.empty?
    out << "Tags: #{@tags.to_hashtags}" unless @tags.empty?
    out << "- [Highlight link](#{@url})"

    "#{out.join("\n\n")}\n\n"
  end
end

# Bookmark class, represents a single bookmark
class Bookmark
  attr_reader :url, :type, :title, :author, :image, :annotation, :highlights, :tags, :doc_note, :summary

  # Initialize a new instance
  #
  # @param options [Hash] Options for creating a new instance
  # @option options [String] :url The URL of the document
  # @option options [String] :type The type of the document
  # @option options [String] :title The title of the document
  # @option options [String] :author The author of the document
  # @option options [String] :image The cover image URL or path
  # @option options [String] :annotation Collated highlights and summary
  # @option options [Array] :highlights Array of highlights from the document
  # @option options [Array] :tags Array of tags associated with the document
  # @option options [String] :doc_note Document notes
  # @option options [String] :summary Summary of the document
  # @return [void]
  def initialize(options)
    @url = options[:url]
    @type = options[:type]
    @title = options[:title]
    @author = options[:author]
    @image = options[:image]
    @annotation = options[:annotation]
    @highlights = options[:highlights]
    @tags = options[:tags]
    @doc_note = options[:doc_note]
    @summary = options[:summary]
  end
end

# Tags class, represents an array<String> of tag names
class Tags < Array
  # Initializes a new instance with an array of tag hashes
  #
  # @param [Array<Hash>] tags An array of hashes containing tag information
  #   Each hash should have a 'name' key with the tag name as value
  # @return [nil] if tags parameter is nil
  # @return [self] otherwise
  def initialize(tags)
    super()
    return nil if tags.nil?

    tags.each do |tag|
      push(tag['name'])
    end
  end

  # Converts array to AppleScript list format
  #
  # @return [String] Comma-separated string of array elements, or empty string if array is empty
  #
  # @example Convert non-empty array
  #   ['one', 'two'].to_as #=> 'one,two'
  #
  # @example Convert empty array
  #   [].to_as #=> ''
  def to_as
    empty? ? '' : join(',')
  end

  # Converts array of tags to hashtag format
  #
  # @return [String] space-separated string of hashtags, empty string if array is empty
  # @example
  #   ['code', 'ruby'].to_hashtags #=> "#code #ruby"
  #   [].to_hashtags #=> ""
  def to_hashtags
    empty? ? '' : map { |tag| "##{tag}" }.join(' ')
  end
end

# Import bookmarks from a folder

class Import
  # Initializes a new instance of the class
  #
  # @param options [Hash] Configuration options for processing highlights
  # @return [void]
  def initialize(options)
    @options = options
    @bookmarks = fetch_highlights
  end

  # Save all bookmarks
  # @param type [Symbol] type of archive to save
  #
  # @return [Array] success status
  def save_all(type = :markdown)
    @bookmarks.map do |bookmark|
      save_to_dt(type, bookmark)
    end

    sleep 5

    return unless type == :markdown

    @bookmarks.each do |bookmark|
      highlight_markdown(bookmark) if bookmark.type == :article
    end
  rescue StandardError => p
    Term.log("Error #{p.message}", p.backtrace, level: :error)
  end

  private

  # Processes an array of highlight data and creates Highlight objects
  #
  # @param result [Hash] A hash containing an array of highlight data under the 'highlights' key
  # @return [Array<Highlight>] An array of processed Highlight objects
  # @example
  #   result = { 'highlights' => [
  #     { 'text' => 'example text', 'note' => 'example note', 'tags' => [],
  #       'location' => '1241', 'url' => 'http://example.com' }
  #   ]}
  #   extract_highlights(result) #=> [#<Highlight:...>]
  def extract_highlights(result)
    highlights = []
    result['highlights'].each do |highlight|
      next if highlight['is_deleted']

      highlights << Highlight.new({ text: highlight['text'].scrub,
                                    note: highlight['note'].scrub,
                                    tags: Tags.new(highlight[:tags]),
                                    location: highlight['location'],
                                    url: highlight['url'] })
    end

    highlights.sort_by { |h| h.location }
  end

  # Fetches reading highlights from Readwise API and converts them to bookmarks
  #
  # @return [Array<Bookmark>] Array of Bookmark objects containing highlight data
  # @raise [JSON::ParserError] if the API response cannot be parsed as JSON
  #
  # Each bookmark contains:
  # - url: The source URL or unique URL for the highlight
  # - type: The type of content (:article, :email, or :book)
  # - title: The readable title of the content
  # - author: The author of the content
  # - image: URL of the cover image
  # - annotation: Formatted highlights as markdown
  # - highlights: Array of individual highlights
  # - tags: Associated tags
  # - doc_note: Any document notes
  # - summary: Content summary if available
  def fetch_highlights
    bookmarks = []
    after = last_update ? "?updatedAfter=#{last_update}" : ''

    res = `curl -SsL -H "Authorization: Token #{@options[:token]}" https://readwise.io/api/v2/export#{after}`
    data = JSON.parse(res)
    Term.log("#{data['results'].count} new highlights", level: :info)
    data['results'].each do |result|
      type = :article
      url = result['source_url']
      if url =~ /^mailto:/
        url = result['unique_url']
        type = :email
      elsif url =~ /^private:/
        url = result['unique_url']
        type = :book
      end
      title = result['readable_title'].ascii.scrub.strip
      author = result['author']
      image = result['cover_image_url']
      doc_note = result['document_note'] ? "**Note:** #{result['document_note'].italicize}" : ''
      tags = Tags.new(result['book_tags'])
      highlights = extract_highlights(result)
      annotation = "### Highlights\n\n#{highlights.map(&:to_md).join("\n\n")}"
      summary = result['summary'] ? "**Summary**: #{result['summary']}" : ''
      bookmarks << Bookmark.new({ url: url,
                                  type: type,
                                  title: title,
                                  author: author,
                                  image: image,
                                  annotation: annotation,
                                  highlights: highlights,
                                  tags: tags,
                                  doc_note: doc_note,
                                  summary: summary })
    end

    save_last_update

    bookmarks
  rescue StandardError => p
    Term.log("Error fetching bookmark JSON", p, level: :error)
  end

  # Returns the DevonThink database target as an AppleScript string
  #
  # @return [String] 'inbox' if no database specified or database is 'global',
  #                  otherwise returns 'database "[name]"' command string
  def database
    if !@options.key?(:database) || @options[:database] =~ /^global$/i
      'inbox'
    else
      %(database "#{@options[:database]}")
    end
  end

  # @return [String] Returns AppleScript commands as string
  # Determines target group for new records
  #
  # If no :group option is specified or if group is "inbox", returns AppleScript command
  # to set target to inbox. Otherwise returns commands to either get existing group or
  # create new group at specified location.
  #
  # @example Setting inbox as target
  #   group # => "set theGroup to inbox"
  #
  # @example Setting custom group as target
  #   @options[:group] = "Research"
  #   group # => Creates/gets "Research" group
  def group
    if !@options.key?(:group) || @options[:group] =~ /^inbox$/i
      %(set theGroup to inbox)
    else
      %(set theGroup to get record at "#{@options[:group]}" in #{database}
        if theGroup is missing value or type of theGroup is not group then
          set theGroup to create location "#{@options[:group]}" in #{database}
        end if)
    end
  end

  # Creates an AppleScript command to import a bookmark to DEVONthink based on the target type
  #
  # @param type [Symbol] The type of record to create (:markdown, :bookmark, :archive, :pdf)
  # @param bookmark [Bookmark] A Bookmark object containing title and URL information
  #
  # @return [String] An AppleScript command string for creating the specified record type
  #
  # @example Create a markdown record
  #   command_for_type(:markdown, bookmark)
  #   #=> 'set theRecord to create Markdown from "http://example.com" readability true name "Example" in theGroup'
  #
  # @example Create a bookmark record
  #   command_for_type(:bookmark, bookmark)
  #   #=> "set theRecord to create record with {name:"Example", type:bookmark, URL:"http://example.com"} in theGroup'
  #
  # @note Non-article bookmarks will always create a basic bookmark record regardless of specified type
  def command_for_type(type, bookmark)
    name = bookmark.title.e_as

    if bookmark.type != :article
      cmd = %(set theRecord to create record with {name:"#{name}", type:bookmark, URL:"#{bookmark.url}"} in theGroup)
    else
      cmd = case type
            when :markdown
              %(set theRecord to create Markdown from "#{bookmark.url}" readability true name "#{name}" in theGroup)
            when :bookmark
              %(set theRecord to create record with {name:"#{name}", type:bookmark, URL:"#{bookmark.url}"} in theGroup)
            when :archive
              %(set theRecord to create web document from "#{bookmark.url}" readability true name "#{name}" in theGroup )
            when :pdf
              %(set theRecord to create PDF document from "#{bookmark.url}" pagination true readability true name "#{name}" in theGroup)
            end
    end
  end

  # Save a bookmark to DEVONthink
  # @param type [Symbol] type of archive to save
  # @param bookmark [Bookmark] bookmark to save
  #
  # @return [Boolean] success status
  def save_to_dt(type = :markdown, bookmark)
    name = bookmark.title.e_as
    annotation = [bookmark.summary, bookmark.doc_note, bookmark.annotation].delete_if(&:empty?).join("\n\n").e_as
    tags = bookmark.tags.to_as

    cmd = command_for_type(type, bookmark)

    existing_annotation = annotation_for_title(bookmark.title)

    annotation = annotation.merge(existing_annotation.e_as) unless existing_annotation.empty?

    cmd = %(tell application id "DNtp"
            #{group}

            -- search for an existing record matching title
            set searchResults to search "name:\\"#{name.no_punc.e_as}\\"" in theGroup
            if searchResults is not {} then
              set theRecord to item 1 of searchResults
            else
              #{cmd}
            end if

            if theRecord is missing value then
              error "Failed to create record"
            end if

            -- set the URL of the entry to the bookmark url
            set URL of theRecord to "#{bookmark.url}"

            -- add annotation as Finder comment
            set comment of theRecord to "#{annotation}"

            -- add an annotation link (same content as Finder comment)
            set theAnnotation to annotation of theRecord
			      if theAnnotation is not missing value then
				      update record theAnnotation with text "#{annotation}" mode replacing
			      else
				      set annotation of theRecord to create record with {name:((name of theRecord) as string) & " (Annotation)", type:markdown, content:"#{annotation}"} in (annotations group of database of theRecord)
            end if

            -- add any Readwise document tags
            set AppleScript's text item delimiters to ","
            set theList to every text item of "#{tags}"
            if theList is not {} then
              set tags of theRecord to theList
            end if

            -- Set thumbnail if available
            if "#{bookmark.image}" is not ""
              set thumbnail of theRecord to "#{bookmark.image}"
            end if
			end tell)

    `osascript <<'APPLESCRIPT'
      #{cmd}
APPLESCRIPT`

    if $CHILD_STATUS.success?
      Term.warn "🔖 Saved #{bookmark.title}"
    else
      Term.warn "⁉️ Error saving #{bookmark.title}"
      Term.log("Error saving bookmark #{bookmark.title}", cmd, level: :error)
    end

    $CHILD_STATUS.success?
  end

  # Search for a record in DEVONthink by title and return its annotation
  #
  # @param title [String] The title of the record to search for
  # @return [String] The plain text annotation of the matching record, or empty string if not found
  # @example
  #   annotation_for_title("My Document") #=> "This is the annotation text"
  def annotation_for_title(title)
    cmd = %(tell application id "DNtp"
        #{group}

        set searchResults to search "name:\\"#{title.no_punc.e_as}\\"" in theGroup
        if searchResults is not {} then
          set theRecord to item 1 of searchResults
          return plain text of (annotation of theRecord)
        end if
      end tell)

    annotation = `osascript <<'APPLESCRIPT'
      #{cmd}
APPLESCRIPT`.strip
      if $CHILD_STATUS.success?
        annotation
      else
        Term.log("Error getting annotation for #{title}", cmd, level: :error)
      end
  end

  # Retrieves content from DEVONthink record matching the given title
  #
  # @param title [String] The title of the DEVONthink record to search for
  # @return [String] The plain text content of the matching record, or nil if not found
  # @note Uses AppleScript to interact with DEVONthink
  # @example
  #   content = content_for_title("My Document")
  def content_for_title(title)
    cmd = %(tell application id "DNtp"
        #{group}

        set searchResults to search "name:\\"#{title.no_punc.e_as}\\"" in theGroup
        if searchResults is not {} then
          set theRecord to item 1 of searchResults
          return plain text of theRecord
        end if
      end tell)

    content = `osascript <<'APPLESCRIPT'
        #{cmd}
APPLESCRIPT`
    if $CHILD_STATUS.success?
      content
    else
      Term.log("Error getting content for #{title}", cmd, level: :error)
      false
    end
  end

  # Updates DevonThink record with highlighted markdown for a given bookmark
  #
  # @param bookmark [Bookmark] The bookmark object containing title and highlights
  # @return [Boolean] true if the update was successful, false otherwise
  #
  # @example
  #   highlight_markdown(bookmark)
  #
  # @note Uses AppleScript to interface with DevonThink
  # @see #content_for_title
  def highlight_markdown(bookmark)
    content = content_for_title(bookmark.title)

    if content && !content.whitespace_only?
      content = content.highlight_markdown(bookmark.highlights)

      cmd = %(tell application id "DNtp"
          #{group}

          set searchResults to search "name:\\"#{bookmark.title.no_punc.e_as}\\"" in theGroup
          if searchResults is not {} then
            set theRecord to item 1 of searchResults
            set plain text of theRecord to "#{content.e_as}"
          end if
        end tell)

      `osascript <<'APPLESCRIPT'
        #{cmd}
APPLESCRIPT`
      if $CHILD_STATUS.success?
        Term.warn "🔆 Highlighted #{bookmark.title}"
        Term.log("#{bookmark.highlights.count} highlights", bookmark.highlights.map { |h| h.text }.join("\n\n"), level: :info)
        return true
      else
        Term.log("Error getting content for #{bookmark.title}", cmd, level: :error)
        return false
      end
    else
      Term.warn "⁉️ Content not found for #{bookmark.title}"
      return false
    end
  end

  # Returns the timestamp of the last update from a file
  #
  # @return [String, nil] timestamp of last update or nil if file doesn't exist
  def last_update
    if File.exist?(LAST_UPDATE)
      last = IO.read(LAST_UPDATE).strip
      last.whitespace_only? ? nil : last
    else
      Term.log("Last update record does not exist", level: :info)
      nil
    end
  end

  # Saves the current timestamp to a file specified by LAST_UPDATE constant
  #
  # @example
  #   save_last_update # => Writes current timestamp to LAST_UPDATE file
  #
  # @return [String] The timestamp string that was written to file
  # @raise [SystemCallError] If the file cannot be created or written to
  def save_last_update
    FileUtils.mkdir_p(File.dirname(LAST_UPDATE)) unless File.directory?(File.dirname(LAST_UPDATE))

    date = Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z')
    File.write(LAST_UPDATE, date)
    Term.log("Saved last update: #{date}", level: :info)
  rescue StandardError => p
    Term.log("Error saving last update", p, level: :error)
  end
end

def parse_options(options)
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options]"

    opts.on('--token TOKEN', 'Readwise API token') do |token|
      options[:token] = token
    end

    opts.on('-t', '--type TYPE', 'Type of archive to save (markdown, bookmark, archive, pdf)') do |type|
      options[:type] = type.normalize_type
    end

    opts.on('-b', '--database DATABASE', 'Database to save to') do |db|
      options[:database] = db
    end

    opts.on('-g', '--group GROUP', 'Group to save to') do |group|
      options[:group] = group
    end

    opts.on_tail('-d', '--debug', 'Turn on debugging output') do |d|
      Term.debug = 1 if Term.debug == 0
    end

    opts.on_tail('-v', '--verbose', 'Turn on verbose output') do |d|
      Term.debug = 2
    end

    opts.on_tail('-q', '--quiet', 'Turn off all output') do
      Term.silent = true
    end

    opts.on_tail('-h', '--help', 'Show this help message') do
      puts opts
      puts "\nConfiguration is defined at the top of #{File.expand_path(__FILE__)}"
      exit
    end
  end

  opt_parser.parse!
  options
end

Term.debug = 0
Term.silent = false
options = parse_options(options)
import = Import.new(options)
import.save_all(options[:type])
