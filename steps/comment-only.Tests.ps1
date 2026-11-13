# Tests for steps/comment-only.ps1, which decides from a file's old and new
# text whether a change touches only its comments.

BeforeAll {
    . (Join-Path $PSScriptRoot 'comment-only.ps1')

    # Joins the lines given into one text, as git show gives them.
    function Lines([string[]]$Lines) { return $Lines -join "`n" }
}

Describe 'Test-CommentOnlyChange' {

    Context 'C, C++, Java and SWIG' {

        It 'counts a change to a copyright line in a block comment' {
            $old = Lines '/* ****', ' * Copyright 2025 51 Degrees', ' * **** */', 'int x;'
            $new = Lines '/* ****', ' * Copyright 2026 51 Degrees', ' * **** */', 'int x;'
            Test-CommentOnlyChange 'src/a.c' $old $new | Should -BeTrue
        }

        It 'counts a new comment above code and one after it' {
            $old = Lines 'int x;', 'int y;'
            $new = Lines '// The first.', 'int x; // trailing', '', '/** The', ' * second. */', 'int y;'
            Test-CommentOnlyChange 'src/a.cpp' $old $new | Should -BeTrue
        }

        It 'does not count a change to code' {
            Test-CommentOnlyChange 'src/a.c' 'int x = 1;' 'int x = 2;' | Should -BeFalse
        }

        It 'does not count a comment that makes code into a comment' {
            $old = Lines 'int x;', 'int y;', 'int z;'
            $new = Lines 'int x;', '/*', 'int y;', '*/', 'int z;'
            Test-CommentOnlyChange 'src/a.c' $old $new | Should -BeFalse
        }

        It 'does not count a line comment that runs on to the next line' {
            $old = Lines '// note', 'int y;'
            $new = Lines '// note \', 'int y;'
            Test-CommentOnlyChange 'src/a.c' $old $new | Should -BeFalse
        }

        It 'does not count a change after // inside a string' {
            $old = 'const char *u = "https://51degrees.com/a";'
            $new = 'const char *u = "https://51degrees.com/b";'
            Test-CommentOnlyChange 'src/a.c' $old $new | Should -BeFalse
        }

        It 'does not count a change to a string with an escaped quote' {
            $old = 'String s = "say \"hi\" // x";'
            $new = 'String s = "say \"hi\" // y";'
            Test-CommentOnlyChange 'src/A.java' $old $new | Should -BeFalse
        }

        It 'does not count a change in indentation' {
            Test-CommentOnlyChange 'src/a.c' 'int x;' '  int x;' | Should -BeFalse
        }

        It 'counts an added file that holds only comments' {
            Test-CommentOnlyChange 'src/a.h' $null '/* Nothing yet. */' | Should -BeTrue
        }

        It 'does not count a removed file that held code' {
            Test-CommentOnlyChange 'src/a.h' 'int x;' $null | Should -BeFalse
        }
    }

    Context 'C#' {

        It 'counts a change to an XML documentation comment' {
            $old = Lines '/// <summary>Old.</summary>', 'void F() {}'
            $new = Lines '/// <summary>New.</summary>', 'void F() {}'
            Test-CommentOnlyChange 'A.cs' $old $new | Should -BeTrue
        }

        It 'does not count a change after a verbatim string that ends in a backslash' {
            $old = 'var p = @"C:\dir\"; var u = "https://a"; // x'
            $new = 'var p = @"C:\dir\"; var u = "https://b"; // x'
            Test-CommentOnlyChange 'A.cs' $old $new | Should -BeFalse
        }
    }

    Context 'Go' {

        It 'does not count a change after // inside a raw string' {
            $old = 'var u = `https://51degrees.com/a`'
            $new = 'var u = `https://51degrees.com/b`'
            Test-CommentOnlyChange 'a.go' $old $new | Should -BeFalse
        }

        It 'counts a change to a comment' {
            Test-CommentOnlyChange 'a.go' (Lines '// Old.', 'func F() {}') `
                (Lines '// New.', 'func F() {}') | Should -BeTrue
        }
    }

    Context 'JavaScript and PHP' {

        It 'does not count a change after // inside a template string' {
            $old = 'const u = `https://51degrees.com/${a}`;'
            $new = 'const u = `https://51degrees.com/${b}`;'
            Test-CommentOnlyChange 'a.js' $old $new | Should -BeFalse
        }

        It 'does not count a change after // inside a single quoted string' {
            Test-CommentOnlyChange 'a.php' "`$u = 'https://a';" "`$u = 'https://b';" |
                Should -BeFalse
        }

        It 'counts a change to a PHP block comment' {
            Test-CommentOnlyChange 'a.php' (Lines '<?php', '/** Old. */', 'f();') `
                (Lines '<?php', '/** New. */', 'f();') | Should -BeTrue
        }
    }

    Context 'Python, YAML, CMake and PowerShell' {

        It 'counts a change to a whole line comment' {
            Test-CommentOnlyChange 'a.py' (Lines '# Old.', 'x = 1') (Lines '# New.', 'x = 1') |
                Should -BeTrue
            Test-CommentOnlyChange 'w.yml' (Lines '# Old.', 'a: 1') (Lines '# New.', 'a: 1') |
                Should -BeTrue
            Test-CommentOnlyChange 'CMakeLists.txt' (Lines '# Old.', 'project(a)') `
                (Lines '# New.', 'project(a)') | Should -BeTrue
            Test-CommentOnlyChange 'a.ps1' (Lines '# Old.', '$x = 1') (Lines '# New.', '$x = 1') |
                Should -BeTrue
        }

        It 'does not count a change in indentation' {
            Test-CommentOnlyChange 'a.py' (Lines 'if a:', '    x = 1') `
                (Lines 'if a:', 'x = 1') | Should -BeFalse
        }

        It 'does not count a change to a trailing comment, which may be in a string' {
            Test-CommentOnlyChange 'a.py' 'x = "a #b"' 'x = "a #c"' | Should -BeFalse
        }

        It 'does not count a change to a #! line' {
            Test-CommentOnlyChange 'a.sh' (Lines '#!/bin/sh', 'ls') (Lines '#!/bin/bash', 'ls') |
                Should -BeFalse
        }

        It 'does not count a change to #Requires' {
            Test-CommentOnlyChange 'a.ps1' (Lines '#Requires -Version 7', '$x = 1') `
                (Lines '#Requires -Version 7.4', '$x = 1') | Should -BeFalse
        }
    }

    It 'does not count a file of a kind it does not know' {
        Test-CommentOnlyChange 'pom.xml' '<!-- a -->' '<!-- b -->' | Should -BeFalse
        Test-CommentOnlyChange 'device-detection-data' 'Subproject commit a' `
            'Subproject commit b' | Should -BeFalse
    }
}
