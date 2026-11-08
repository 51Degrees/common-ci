# Shared by select-options.ps1, which dot-sources it. Decides whether a change
# to a file touches only its comments, by removing the comments from the old
# and the new text and comparing what is left, so that a comment marker which
# turns code into a comment counts as a change to code.

# Each pattern matches the strings and the comments of a group of languages.
# Strings are matched only so that a comment marker inside one is left alone,
# and are kept. A line comment that ends in a backslash continues onto the
# next line in C and C++, so it is kept too.
$DoubleQuoted = '"(?:\\.|[^"\\\n])*"'
$Character = "'(?:\\.|[^'\\\n]){1,8}'"
$CComments = '//[^\n]*|/\*[\s\S]*?\*/'
$CommentPatterns = @{
    c = "$DoubleQuoted|$Character|$CComments"
    cs = "@`"(?:`"`"|[^`"])*`"|$DoubleQuoted|$Character|$CComments"
    go = "``[^``]*``|$DoubleQuoted|$Character|$CComments"
    js = "``(?:\\.|[^``\\])*``|$DoubleQuoted|'(?:\\.|[^'\\\n])*'|$CComments"
    php = '"(?:\\.|[^"\\])*"|' + "'(?:\\.|[^'\\])*'|$CComments"
}

# Languages whose comments start with # and run to the end of the line. Only
# whole line comments are removed, which keeps the indentation Python and
# YAML depend on. A #! line names the interpreter, and #Requires is a
# PowerShell statement, so both are kept.
$HashComment = '(?m)^[ \t]*#(?!!).*$'
$PowerShellComment = '(?mi)^[ \t]*#(?!!|requires\b).*$'

$CommentStyles = @{
    '.c' = 'c'; '.h' = 'c'; '.cpp' = 'c'; '.hpp' = 'c'; '.cc' = 'c'
    '.cxx' = 'c'; '.hh' = 'c'; '.i' = 'c'; '.java' = 'c'
    '.cs' = 'cs'; '.go' = 'go'
    '.js' = 'js'; '.mjs' = 'js'; '.cjs' = 'js'; '.ts' = 'js'
    '.php' = 'php'
    '.py' = 'hash'; '.sh' = 'hash'; '.yml' = 'hash'; '.yaml' = 'hash'
    '.toml' = 'hash'; '.cmake' = 'hash'
    '.ps1' = 'ps'; '.psm1' = 'ps'; '.psd1' = 'ps'
}

# The comment style of a file, or null when it is not known, so that the
# change counts as a change to code.
function Get-CommentStyle([string]$Path) {
    $name = [IO.Path]::GetFileName($Path)
    if ($name -ceq 'CMakeLists.txt') { return 'hash' }
    return $CommentStyles[[IO.Path]::GetExtension($name).ToLowerInvariant()]
}

# The lines of the text that are not comments or blank, without trailing
# space, joined by new lines.
function Get-CodeLines([AllowNull()][string]$Text, [string]$Style) {
    $text = "$Text" -replace "`r`n", "`n"
    if ($Style -eq 'hash') {
        $text = $text -replace $HashComment, ''
    } elseif ($Style -eq 'ps') {
        $text = $text -replace $PowerShellComment, ''
    } else {
        $text = [regex]::Replace($text, $CommentPatterns[$Style], {
            param($match)
            $value = $match.Value
            if ($value.StartsWith('//')) {
                return $value.TrimEnd().EndsWith('\') ? $value : ''
            }
            if ($value.StartsWith('/*')) {
                # The new lines are kept, so the code around the comment stays
                # on its own lines.
                return $value -replace '[^\n]', ''
            }
            return $value
        })
    }
    $lines = $text -split "`n" | ForEach-Object { $_.TrimEnd() } |
        Where-Object { $_ }
    return $lines -join "`n"
}

# True when the old and new text of a file differ only in comments and blank
# lines. Old is null for an added file and New for a removed one.
function Test-CommentOnlyChange([string]$Path, [AllowNull()][string]$Old,
    [AllowNull()][string]$New) {
    $style = Get-CommentStyle $Path
    if (!$style) { return $false }
    return (Get-CodeLines $Old $style) -ceq (Get-CodeLines $New $style)
}
