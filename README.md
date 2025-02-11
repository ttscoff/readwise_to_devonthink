# Readwise to DEVONthink

Reader articles with highlights become searchable text with
annotations in DEVONthink.

- Gets new highlights on schedule using launchd
- Adds Markdown file for urls, bookmarks for other types
- Adds finder comments and annotations with highlighted text and their notes and tags, with a link to the Reader highlight
- Highlights text in Markdown documents, full paragraph, using CriticMarkup
- Can merge new highlights into existing documents
- Add DEVONthink tags from Readwise document tags

## Installation/Usage

1. Save the [script][raw] to disk, or clone this gist and link the script into your $PATH
2. Edit config options hash in the script, external config file (see below), or pass as command line flags
3. Make script executable, `chmod a+x /path/to/readwise_to_devonthink.rb`
4. Run script once to get all previous highlights, `/path/to/readwise_to_devonthink.rb`
5. Set up a launchd job to run script at desired interval

[raw]: https://gist.githubusercontent.com/ttscoff/0a14fcd621526f1ab2ac6fa027df0dea/raw/3f74ca4a6b0ecc3b7bc8a83dbd585e8b43217a74/readwise_to_devonthink.rb

### External configuration

You can also create a YAML file at `~/.local/share/devonthink/rw2dt.yaml` and include the config options:

```yaml
---
# Readwise API token, required, see <https://readwise.io/access_token>
token: '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
# Type to save urls as, :markdown is default and preferred
# Can also be :bookmark, :archive, or :pdf
# Highlighting can only be done on :markdown type
type: :markdown
# Database name, global is default
database: 'global'
# Group name or inbox, inbox is default
group: 'inbox'
# If true will apply tags found in Marky-generated markdown
# and Readwise document tags
apply_tags: true
```

Any options left out above will be replaced with values in
the script. Only the token is required.

### Command line options

In lieu of setting config options in the script or external
file, you can pass them as command line flags:

- Pass the token with the `--token` option
- Pass the type with the `--type` option
- Pass database and/or group with `--database` and `--group`

Config options not passed on the command line will be read
from the config file or the hash in the script (in that
order).

### Caveats

- does not handle deletions
- does not highlight images
