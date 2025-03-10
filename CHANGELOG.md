### 1.0.38

2025-03-03 05:22

#### IMPROVED

- Code cleanup
- Check DT version and use DT4 commands if available

### 1.0.37

2025-03-03 03:48

#### NEW

- Add --back option

#### IMPROVED

- Update README

### 1.0.36

2025-03-01 08:23

#### FIXED

- Group should be set to incoming not inbox

### 1.0.35

2025-03-01 07:17

#### IMPROVED

- Further improve highlighter regex

### 1.0.34

2025-03-01 06:47

#### IMPROVED

- Capture quotes and surrounding html tags when performing Markdown highlighting.

### 1.0.33

#### IMPROVED

- Improve --help output

### 1.0.19

2025-02-11 06:12

#### IMPROVED

- You can now create a config file at ~/.local/share/devonthink/rw2dt.yaml to add config options without editing the script

### 1.0.18

2025-02-11 05:39

### 1.0.17

2025-02-11 05:39

#### IMPROVED

- Just adding versioning and a build system

### 1.0.15

2025-02-11 05:02

#### FIXED

- When database is not set to global and group was set to inbox, entries were still going to global inbox

### 1.0.14

2025-02-09

- Add debug and verbose options
- Better search for existing notes (remove punctuation that breaks search)
- Add --quiet option to suppress output
- Highlight only selected text instead of whole paragraph
- Sort highlights by position

### 1.0.13

2025-02-10:

- Switch to using Marky the Markdownifier (v2) for article content
  - fixes issues with non-ascii characters
- Add --apply-tags option to apply tags from Readwise and Marky
- fix highlighting with superscript
