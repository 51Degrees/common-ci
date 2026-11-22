# Dot-sourced by package-update-required.ps1 and select-options.ps1. Matches
# the path of a documentation file, being any Markdown file and anything in a
# docs folder, which no package includes. -match ignores case.
$DocumentationPattern = '\.md$|(^|/)docs/'
