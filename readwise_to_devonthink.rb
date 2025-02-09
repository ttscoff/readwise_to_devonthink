#!/usr/bin/env ruby
require 'English'
require 'json'
require 'date'
require 'fileutils'

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
# ### Caveats
#
# - does not handle deletions
# - does not highlight images

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

LAST_UPDATE = File.expand_path('~/.local/share/devonthink/readwise_last_update')

# String extensions
class ::String
  # Make string searchable as regex
  def content_rx
    gsub(/\\u2014/, '[-—]+')
      .gsub(/\\u2018/, '‘')
      .gsub(/\\u2019/, '’')
      .gsub(/\\u201c/, '“')
      .gsub(/\\u201d/, '”')
      .gsub(/[^a-zA-Z0-9\-— ‘’“”,!?;]+/, '.*?')
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

  def highlight(highlight)
    "{==#{gsub(/(\{==|==\})/, '')}==}"
    # if (highlight.note && !highlight.note.whitespace_only?) || (highlight.tags && !highlight.tags.empty?)
    #   comment = []
    #   comment << highlight.note if highlight.note && !highlight.note.whitespace_only?
    #   comment << highlight.tags.to_hashtags if highlight.tags && !highlight.tags.empty?
    #   out << "{>>#{comment.join(" ")}<<}"
    # end
  end

  # Highlight paragraphs in Markdown containing a highlight
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

  def initialize(options)
    @text = options[:text]
    @note = options[:note]
    @tags = options[:tags]
    @location = options[:location]
    @url = options[:url]
  end

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
  def initialize(tags)
    super()
    return nil if tags.nil?

    tags.each do |tag|
      push(tag['name'])
    end
  end

  def to_as
    empty? ? '' : join(',')
  end

  def to_hashtags
    empty? ? '' : map { |tag| "##{tag}" }.join(' ')
  end
end

# Import bookmarks from a folder

class Import
  def initialize(options)
    @options = options
    @bookmarks = fetch_highlights
  end

  def extract_highlights(result)
    highlights = []
    result['highlights'].each do |highlight|
      next if highlight['is_deleted']

      highlights << Highlight.new({ text: highlight['text'].scrub,
                                    note: highlight['note'].scrub,
                                    tags: Tags.new(highlight[:tags]),
                                    locations: highlight['location'],
                                    url: highlight['url'] })
    end

    highlights
  end

  def fetch_highlights
    bookmarks = []
    after = last_update ? "?updatedAfter=#{last_update}" : ''

    res = `curl -SsL -H "Authorization: Token #{@options[:token]}" https://readwise.io/api/v2/export#{after}`
    data = JSON.parse(res)
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
  end

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
            set searchResults to search "name:\\"#{name}\\"" in theGroup
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
			end tell)

    `osascript <<'APPLESCRIPT'
      #{cmd}
APPLESCRIPT`

    if $CHILD_STATUS.success?
      warn "🔖 Saved #{bookmark.title}"
    else
      warn "⁉️ Error saving #{bookmark.title}"
      puts cmd
    end

    $CHILD_STATUS.success?
  end

  def database
    if !@options.key?(:database) || @options[:database] =~ /^global$/i
      'inbox'
    else
      %(database "#{@options[:database]}")
    end
  end

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

  def annotation_for_title(title)
    `osascript <<'APPLESCRIPT'
      tell application id "DNtp"
        #{group}

        set searchResults to search "name:\\"#{title.e_as}\\"" in theGroup
        if searchResults is not {} then
          set theRecord to item 1 of searchResults
          return plain text of (annotation of theRecord)
        end if
      end tell
APPLESCRIPT`.strip
  end

  def content_for_title(title)
    `osascript <<'APPLESCRIPT'
      tell application id "DNtp"
        #{group}

        set searchResults to search "name:\\"#{title.e_as}\\"" in theGroup
        if searchResults is not {} then
          set theRecord to item 1 of searchResults
          return plain text of theRecord
        end if
      end tell
APPLESCRIPT`
  end

  def highlight_markdown(bookmark)
    content = content_for_title(bookmark.title)

    if content && !content.whitespace_only?
      content = content.highlight_markdown(bookmark.highlights)

      cmd = %(tell application id "DNtp"
          #{group}

          set searchResults to search "name:\\"#{bookmark.title.e_as}\\"" in theGroup
          if searchResults is not {} then
            set theRecord to item 1 of searchResults
            set plain text of theRecord to "#{content.e_as}"
          end if
        end tell)

      `osascript <<'APPLESCRIPT'
        #{cmd}
APPLESCRIPT`
      warn "🔆 Highlighted #{bookmark.title}"
    else
      warn "⁉️ Content not found for #{bookmark.title}"
    end

    $CHILD_STATUS.success?
  end

  def last_update
    if File.exist?(LAST_UPDATE)
      IO.read(LAST_UPDATE).strip
    else
      nil
    end
  end

  def save_last_update
    FileUtils.mkdir_p(File.dirname(LAST_UPDATE)) unless File.directory?(File.dirname(LAST_UPDATE))

    File.write(LAST_UPDATE, Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z'))
  end
end

# Parse options
# --folder [folder] - folder to import
# --type [type] - type of archive to save
# --database [database] - database to save to
# --group [group] - group to save to
# --help - show help
#
# @return [Hash] options
def parse_options(options)
  ARGV.each_with_index do |arg, i|
    case arg
    when '--token'
      options[:token] = ARGV[i + 1]
    when '--type'
      options[:type] = ARGV[i + 1].normalize_type
    when '--database'
      options[:database] = ARGV[i + 1]
    when '--group'
      options[:group] = ARGV[i + 1]
    when /-*h(elp)?/
      puts <<~HELP
        Configuration is defined at the top of #{File.expand_path(__FILE__)}

        The following options override config settings:

        --token [token] - Readwise API token
        --type [type] - type of archive to save
        --database [database] - database to save to
        --group [group] - group to save to
        --help - show help
      HELP
      exit
    end
  end

  options
end

options = parse_options(options)
import = Import.new(options)
import.save_all(options[:type])
