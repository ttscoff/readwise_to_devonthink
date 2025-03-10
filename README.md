# Readwise to DEVONthink

![Banner Image][banner]

[banner]: https://cdn3.brettterpstra.com/uploads/2025/02/readwise_devonthink-rb.avif

[![License: MIT][mitshield]][mit]

[mitshield]: https://img.shields.io/badge/License-MIT-yellow.svg
[mit]: https://opensource.org/licenses/MIT

Reader articles with highlights become searchable text with
annotations in DEVONthink.

- Gets new highlights on schedule using launchd
- Adds Markdown file for urls, bookmarks for other types
- Adds finder comments and annotations with highlighted text and their notes and tags, with a link to the Reader highlight
- Highlights text in Markdown documents, full paragraph, using CriticMarkup
- Can merge new highlights into existing documents
- Add DEVONthink tags from Readwise document tags

## Installation/Usage

1. Save the [script][raw] to disk, or clone this repository and link the script into your $PATH[^link]
2. Edit config options hash in the script, external config file ([see below](#external-configuration)), or pass as command line flags
3. Make the script executable

        $ chmod a+x /path/to/readwise_to_devonthink.rb

4. Run the script once to get all existing highlights:

        $ /path/to/readwise_to_devonthink.rb

5. Set up a launchd job ([see below](#setting-up-a-launchd-job)) to run script at desired interval

[raw]: https://raw.githubusercontent.com/ttscoff/readwise_to_devonthink/refs/heads/main/readwise_to_devonthink.rb

[^link]: Creating a symlink, e.g. `ln -s ~/path/to/repo/readwise_to_devonthink.rb /usr/local/bin/readwise_to_devonthink.rb` makes it easy to update just by pulling the repo. Make sure your config is in the separate config file to avoid overwriting it.

### External configuration

You can also create a YAML file at `~/.local/share/devonthink/rw2md.yaml` and include the config options:

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

```console
$ readwise_to_devonthink.rb -h

Usage: readwise_to_devonthink.rb [options]
        --token TOKEN                Readwise API token
        --database DATABASE          Database to save to
    -g, --group GROUP                Group to save to
    -t, --type TYPE                  Type of archive to save (markdown, bookmark, archive, pdf)
        --apply-tags                 Apply tags from Marky generated markdown
    -b, --back BACK                  Get highlights back to date using string XdXhXm

    -d, --debug                      Turn on debugging output
    -q, --quiet                      Turn off all output
    -v, --verbose                    Turn on verbose output
        --version                    Display version
    -h, --help                       Show this help message

Configuration can be defined in /Users/ttscoff/.local/share/devonthink/rw2md.yaml
```

### Setting up a launchd job

The easiest way to set up a launchd job is with a GUI like [Lingon][peterborgapps] or [LaunchControl][soma-zone].

If you prefer to do it by hand, you can edit the PLIST below and place it in `~/Library/LaunchAgents/com.brettterpstra.readwise.plist`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.brettterpstra.readwise</string>
	<key>Program</key>
	<string>[/path/to]/readwise_to_devonthink.rb</string>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardErrorPath</key>
	<string>[/path/to/]/readwise.stderr</string>
	<key>StandardOutPath</key>
	<string>[/path/to]/readwise.stdout</string>
	<key>StartInterval</key>
	<integer>3600</integer>
</dict>
</plist>
```

Edit all of the `[/path/to]` to point to your script. The
`StandardErrorPath` and `StandardOutPath` are optional and can
be removed, but if provided with a path, will output useful
information. The `StandardErrorPath` will contain most of the
output, including warnings and errors. If you add `-d` to
the Program key command, you can get more debug info in the
STDERR file.

The `StartInterval` key determines how often the script will
run, in seconds (e.g. 3600 = 1 hour). The script will always
gather any new highlights since the last run, so this can be
spread out as far as you want, e.g. 86400 for once a day.

[peterborgapps]: https://www.peterborgapps.com/lingon/
[soma-zone]: https://www.soma-zone.com/LaunchControl/

### Debugging

If you run into issues, please follow these steps

1. Ensure that you've created the config file at `~/.local/share/devonthink/rw2md.yaml`. This will make it easier to update the script with revisions because you won't have to edit the config at the top every time.
2. Use the `--back` option to parse back a set period of time, e.g. `3h` or `1d`. Increase period as needed to replicate the issue. Include `readwise_to_devonthink.rb -v` to get verbose output. The final command should look like:

        readwise_to_devonthink.rb --back 1d -v

3. Copy the output from step 3 to a private gist, or to a text file you can attach to a forum post.
4. Share the gist in the Issues [here](https://github.com/ttscoff/readwise_to_devonthink/issues), or create a post on <https://forum.brettterpstra.com> and attach the text file there.

**NOTE:** The verbose output will likely contain the content of the highlight or the entire Markdown content of the highlighted page/text. If this is private for any reason, [share it with me privately](https://brettterpstra.com/contact/), or try to replicate the issue with non-private content and redact the output as needed.

### Caveats

- does not handle deletions
- does not highlight images


