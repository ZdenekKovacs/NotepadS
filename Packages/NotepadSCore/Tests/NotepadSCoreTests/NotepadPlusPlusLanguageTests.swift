import XCTest
@testable import NotepadSCore

/// The languages added to match Notepad++: one or a few typical lines each, checked token by token.
final class NotepadPlusPlusLanguageTests: XCTestCase {

    private typealias Pair = TokenizerTests.Pair

    private func tokens(_ grammar: Grammar, _ lines: [String]) -> [[Pair]] {
        var state = LineState.initial
        return lines.map { line in
            let text = line as NSString
            let result = grammar.tokenize(line: text, startingIn: state)
            state = result.endState
            return result.tokens.map { Pair(text.substring(with: $0.range), $0.scope) }
        }
    }

    func testCsharp() {
        XCTAssertEqual(tokens(.csharp, [##"[Obsolete] public async Task<int> Run(string s) { var x = $"Hi {name}!\n"; return 0x1F; } // c"##, ##"var p = @"C:\dir""x"; #region A"##]), [
            [Pair(##"public"##, .keyword), Pair(##"async"##, .keyword), Pair(##"int"##, .keyword), Pair(##"Run"##, .function), Pair(##"string"##, .keyword), Pair(##"var"##, .keyword), Pair(##"$"Hi "##, .string), Pair(##"{name}"##, .variable), Pair(##"!"##, .string), Pair(##"\n"##, .stringEscape), Pair(##"""##, .string), Pair(##"return"##, .keyword), Pair(##"0x1F"##, .number), Pair(##"// c"##, .comment)],
            [Pair(##"var"##, .keyword), Pair(##"@"C:\dir"##, .string), Pair(##""""##, .stringEscape), Pair(##"x""##, .string)],
        ])
    }

    func testVisualBasic() {
        XCTAssertEqual(tokens(.visualBasic, [##"Public Function Add(ByVal a As Integer) As Integer ' comment"##, ##"Dim s = "say ""hi""" : If x Then Return Nothing"##, ##"rem old"##]), [
            [Pair(##"Public"##, .keyword), Pair(##"Function"##, .keyword), Pair(##"Add"##, .function), Pair(##"ByVal"##, .keyword), Pair(##"As"##, .keyword), Pair(##"Integer"##, .keyword), Pair(##"As"##, .keyword), Pair(##"Integer"##, .keyword), Pair(##"' comment"##, .comment)],
            [Pair(##"Dim"##, .keyword), Pair(##""say "##, .string), Pair(##""""##, .stringEscape), Pair(##"hi"##, .string), Pair(##""""##, .stringEscape), Pair(##"""##, .string), Pair(##"If"##, .keyword), Pair(##"Then"##, .keyword), Pair(##"Return"##, .keyword), Pair(##"Nothing"##, .constant)],
            [Pair(##"rem old"##, .comment)],
        ])
    }

    func testPowerShell() {
        XCTAssertEqual(tokens(.powerShell, [##"function Get-Thing { param([string]$Name) if ($Name -eq $null) { Write-Host "Hi $Name`n" -ForegroundColor Red } } # c"##, ##"<# block"##, ##"#>"##, ##"$x = @""##, ##"text $y"##, ##""@"##]), [
            [Pair(##"function"##, .keyword), Pair(##"Get-Thing"##, .function), Pair(##"param"##, .keyword), Pair(##"[string]"##, .keyword), Pair(##"$Name"##, .variable), Pair(##"if"##, .keyword), Pair(##"$Name"##, .variable), Pair(##"-eq"##, .operator), Pair(##"$null"##, .constant), Pair(##"Write-Host"##, .function), Pair(##""Hi "##, .string), Pair(##"$Name"##, .variable), Pair(##"`n"##, .stringEscape), Pair(##"""##, .string), Pair(##"-ForegroundColor"##, .property), Pair(##"# c"##, .comment)],
            [Pair(##"<# block"##, .comment)],
            [Pair(##"#>"##, .comment)],
            [Pair(##"$x"##, .variable), Pair(##"@""##, .string)],
            [Pair(##"text "##, .string), Pair(##"$y"##, .variable)],
            [Pair(##""@"##, .string)],
        ])
    }

    func testBatch() {
        XCTAssertEqual(tokens(.batch, [##"@echo off"##, ##"rem comment"##, ##":loop"##, ##"if exist "%~dp0file.txt" goto :eof"##, ##"set /a COUNT=%COUNT%+1 & echo !VAR! %%i"##, ##":: also comment"##]), [
            [Pair(##"echo"##, .keyword), Pair(##"off"##, .keyword)],
            [Pair(##"rem comment"##, .comment)],
            [Pair(##":loop"##, .function)],
            [Pair(##"if"##, .keyword), Pair(##"exist"##, .keyword), Pair(##""%~dp0file.txt""##, .string), Pair(##"goto"##, .keyword)],
            [Pair(##"set"##, .keyword), Pair(##"/a"##, .property), Pair(##"%COUNT%"##, .variable), Pair(##"1"##, .number), Pair(##"echo"##, .keyword), Pair(##"!VAR!"##, .variable), Pair(##"%%i"##, .variable)],
            [Pair(##":: also comment"##, .comment)],
        ])
    }

    func testRegistry() {
        XCTAssertEqual(tokens(.registry, [##"Windows Registry Editor Version 5.00"##, ##""##, ##"[HKEY_CURRENT_USER\Software\Test]"##, ##""Name"="C:\\Path""##, ##""Count"=dword:00000001"##, ##"@=hex(2):25,00"##, ##"; comment"##]), [
            [Pair(##"Windows Registry Editor Version 5.00"##, .keyword)],
            [],
            [Pair(##"[HKEY_CURRENT_USER\Software\Test]"##, .heading)],
            [Pair(##""Name""##, .property), Pair(##""C:"##, .string), Pair(##"\\"##, .stringEscape), Pair(##"Path""##, .string)],
            [Pair(##""Count""##, .property), Pair(##"dword"##, .keyword), Pair(##"00000001"##, .number)],
            [Pair(##"@"##, .property), Pair(##"hex(2)"##, .keyword), Pair(##"25"##, .number), Pair(##"00"##, .number)],
            [Pair(##"; comment"##, .comment)],
        ])
    }

    func testAutoIt() {
        XCTAssertEqual(tokens(.autoIt, [##"#include <Array.au3>"##, ##"Local $sName = "x" ; c"##, ##"Func Add($a, $b)"##, ##"    Return $a + @ScriptDir"##, ##"EndFunc"##, ##"#cs"##, ##"comment"##, ##"#ce"##]), [
            [Pair(##"#include"##, .keyword)],
            [Pair(##"Local"##, .keyword), Pair(##"$sName"##, .variable), Pair(##""x""##, .string), Pair(##"; c"##, .comment)],
            [Pair(##"Func"##, .keyword), Pair(##"Add"##, .function), Pair(##"$a"##, .variable), Pair(##"$b"##, .variable)],
            [Pair(##"Return"##, .keyword), Pair(##"$a"##, .variable), Pair(##"@ScriptDir"##, .constant)],
            [Pair(##"EndFunc"##, .keyword)],
            [Pair(##"#cs"##, .comment)],
            [Pair(##"comment"##, .comment)],
            [Pair(##"#ce"##, .comment)],
        ])
    }

    func testNsis() {
        XCTAssertEqual(tokens(.nsis, [##"!include "MUI2.nsh""##, ##"Section "Main" SEC01"##, ##"  SetOutPath "$INSTDIR\bin""##, ##"  File /r files ; c"##, ##"  StrCpy $0 "${VERSION}$\r$\n""##]), [
            [Pair(##"!include"##, .keyword), Pair(##""MUI2.nsh""##, .string)],
            [Pair(##"Section"##, .keyword), Pair(##""Main""##, .string)],
            [Pair(##"SetOutPath"##, .keyword), Pair(##"""##, .string), Pair(##"$INSTDIR"##, .variable), Pair(##"\bin""##, .string)],
            [Pair(##"File"##, .keyword), Pair(##"/r"##, .property), Pair(##"; c"##, .comment)],
            [Pair(##"StrCpy"##, .keyword), Pair(##"$0"##, .variable), Pair(##"""##, .string), Pair(##"${VERSION}"##, .variable), Pair(##"$\r"##, .stringEscape), Pair(##"$\n"##, .stringEscape), Pair(##"""##, .string)],
        ])
    }

    func testInnoSetup() {
        XCTAssertEqual(tokens(.innoSetup, [##"[Setup]"##, ##"AppName=My App"##, ##"; comment"##, ##"[Files]"##, ##"Source: "app.exe"; DestDir: "{app}"; Flags: ignoreversion"##, ##"[Code]"##, ##"function InitializeSetup(): Boolean;"##, ##"begin Result := True; end;"##]), [
            [Pair(##"[Setup]"##, .heading)],
            [Pair(##"AppName"##, .property)],
            [Pair(##"; comment"##, .comment)],
            [Pair(##"[Files]"##, .heading)],
            [Pair(##"Source"##, .property), Pair(##""app.exe""##, .string), Pair(##"DestDir"##, .property), Pair(##"""##, .string), Pair(##"{app}"##, .constant), Pair(##"""##, .string), Pair(##"Flags"##, .property)],
            [Pair(##"[Code]"##, .heading)],
            [Pair(##"function"##, .keyword)],
            [Pair(##"begin"##, .keyword), Pair(##"Result"##, .constant), Pair(##"True"##, .constant), Pair(##"end"##, .keyword)],
        ])
    }

    func testKotlin() {
        XCTAssertEqual(tokens(.kotlin, [##"@JvmStatic fun greet(name: String?): String = "Hi $name ${name?.length}" // c"##, ##"val x = 0xFFL; when (x) { else -> null }"##]), [
            [Pair(##"@JvmStatic"##, .function), Pair(##"fun"##, .keyword), Pair(##"greet"##, .function), Pair(##""Hi "##, .string), Pair(##"$name"##, .variable), Pair(##" "##, .string), Pair(##"${name?.length}"##, .variable), Pair(##"""##, .string), Pair(##"// c"##, .comment)],
            [Pair(##"val"##, .keyword), Pair(##"0xFFL"##, .number), Pair(##"when"##, .keyword), Pair(##"else"##, .keyword), Pair(##"null"##, .constant)],
        ])
    }

    func testScala() {
        XCTAssertEqual(tokens(.scala, [##"case class P(x: Int) extends T { def show = s"P($x)" }"##, ##"val xs = List(1, 2) // c"##]), [
            [Pair(##"case"##, .keyword), Pair(##"class"##, .keyword), Pair(##"extends"##, .keyword), Pair(##"def"##, .keyword), Pair(##"show"##, .function), Pair(##"s"P("##, .string), Pair(##"$x"##, .variable), Pair(##")""##, .string)],
            [Pair(##"val"##, .keyword), Pair(##"1"##, .number), Pair(##"2"##, .number), Pair(##"// c"##, .comment)],
        ])
    }

    func testGroovy() {
        XCTAssertEqual(tokens(.groovy, [##"#!/usr/bin/env groovy"##, ##"def greet(String name) { println "Hi ${name}" }"##, ##"dependencies { implementation 'com.x:y:1.0' }"##]), [
            [Pair(##"#!/usr/bin/env groovy"##, .comment)],
            [Pair(##"def"##, .keyword), Pair(##"greet"##, .function), Pair(##""Hi "##, .string), Pair(##"${name}"##, .variable), Pair(##"""##, .string)],
            [Pair(##"dependencies"##, .function), Pair(##"'com.x:y:1.0'"##, .string)],
        ])
    }

    func testDart() {
        XCTAssertEqual(tokens(.dart, [##"@override Widget build(BuildContext context) { final s = 'Hi $name'; return Text(s); }"##, ##"Future<void> main() async => print(r'raw $x');"##]), [
            [Pair(##"@override"##, .function), Pair(##"build"##, .function), Pair(##"final"##, .keyword), Pair(##"'Hi "##, .string), Pair(##"$name"##, .variable), Pair(##"'"##, .string), Pair(##"return"##, .keyword), Pair(##"Text"##, .function)],
            [Pair(##"void"##, .keyword), Pair(##"main"##, .function), Pair(##"async"##, .keyword), Pair(##"print"##, .function), Pair(##"r'raw $x'"##, .string)],
        ])
    }

    func testObjectiveC() {
        XCTAssertEqual(tokens(.objectiveC, [##"#import <Foundation/Foundation.h>"##, ##"@interface Foo : NSObject @property (nonatomic, strong) NSString *name; @end"##, ##"[self setName:@"x" forKey:nil]; return YES;"##]), [
            [Pair(##"#import"##, .keyword), Pair(##" <Foundation/Foundation.h>"##, .string)],
            [Pair(##"@interface"##, .keyword), Pair(##"@property"##, .keyword), Pair(##"nonatomic"##, .keyword), Pair(##"strong"##, .keyword), Pair(##"@end"##, .keyword)],
            [Pair(##"self"##, .constant), Pair(##"setName:"##, .function), Pair(##"@"x""##, .string), Pair(##"forKey:"##, .function), Pair(##"nil"##, .constant), Pair(##"return"##, .keyword), Pair(##"YES"##, .constant)],
        ])
    }

    func testLua() {
        XCTAssertEqual(tokens(.lua, [##"local function add(a, b) return a + b end -- c"##, ##"--[[ block"##, ##"]] x = [[long"##, ##"string]] print 'hi'"##, ##"t = { nil, true, 0x1F }"##]), [
            [Pair(##"local"##, .keyword), Pair(##"function"##, .keyword), Pair(##"add"##, .function), Pair(##"return"##, .keyword), Pair(##"end"##, .keyword), Pair(##"-- c"##, .comment)],
            [Pair(##"--[[ block"##, .comment)],
            [Pair(##"]]"##, .comment), Pair(##"[[long"##, .string)],
            [Pair(##"string]]"##, .string), Pair(##"print"##, .function), Pair(##"'hi'"##, .string)],
            [Pair(##"nil"##, .constant), Pair(##"true"##, .constant), Pair(##"0x1F"##, .number)],
        ])
    }

    func testPerl() {
        XCTAssertEqual(tokens(.perl, [##"#!/usr/bin/perl"##, ##"my $name = "World"; print "Hello, $name!\n"; # c"##, ##"sub greet { my @args = @_; return $#args; }"##, ##"=pod"##, ##"doc"##, ##"=cut"##, ##"__END__"##, ##"data"##]), [
            [Pair(##"#!/usr/bin/perl"##, .comment)],
            [Pair(##"my"##, .keyword), Pair(##"$name"##, .variable), Pair(##""World""##, .string), Pair(##"print"##, .keyword), Pair(##""Hello, "##, .string), Pair(##"$name"##, .variable), Pair(##"!"##, .string), Pair(##"\n"##, .stringEscape), Pair(##"""##, .string), Pair(##"# c"##, .comment)],
            [Pair(##"sub"##, .keyword), Pair(##"greet"##, .function), Pair(##"my"##, .keyword), Pair(##"@args"##, .variable), Pair(##"@_"##, .variable), Pair(##"return"##, .keyword), Pair(##"$#args"##, .variable)],
            [Pair(##"=pod"##, .comment)],
            [Pair(##"doc"##, .comment)],
            [Pair(##"=cut"##, .comment)],
            [Pair(##"__END__"##, .comment)],
            [Pair(##"data"##, .comment)],
        ])
    }

    func testR() {
        XCTAssertEqual(tokens(.r, [##"df <- read.csv("data.csv") # c"##, ##"f <- function(x, y = TRUE) { if (is.na(x)) NULL else x %in% y }"##, ##"x |> mean() -> m; 1e3L"##]), [
            [Pair(##"<-"##, .operator), Pair(##"read.csv"##, .function), Pair(##""data.csv""##, .string), Pair(##"# c"##, .comment)],
            [Pair(##"<-"##, .operator), Pair(##"function"##, .keyword), Pair(##"TRUE"##, .constant), Pair(##"if"##, .keyword), Pair(##"is.na"##, .function), Pair(##"NULL"##, .constant), Pair(##"else"##, .keyword), Pair(##"%in%"##, .operator)],
            [Pair(##"|>"##, .operator), Pair(##"mean"##, .function), Pair(##"->"##, .operator), Pair(##"1e3L"##, .number)],
        ])
    }

    func testTcl() {
        XCTAssertEqual(tokens(.tcl, [##"proc greet {name} { puts "Hello, $name!" }"##, ##"# comment"##, ##"set x [expr {$a + 1}] ; # c"##, ##"if {[string match -nocase a* $s]} { return }"##]), [
            [Pair(##"proc"##, .keyword), Pair(##"greet"##, .function), Pair(##"puts"##, .keyword), Pair(##""Hello, "##, .string), Pair(##"$name"##, .variable), Pair(##"!""##, .string)],
            [Pair(##"# comment"##, .comment)],
            [Pair(##"set"##, .keyword), Pair(##"expr"##, .keyword), Pair(##"$a"##, .variable), Pair(##"1"##, .number), Pair(##"; # c"##, .comment)],
            [Pair(##"if"##, .keyword), Pair(##"string"##, .keyword), Pair(##"-nocase"##, .property), Pair(##"$s"##, .variable), Pair(##"return"##, .keyword)],
        ])
    }

    func testCoffeeScript() {
        XCTAssertEqual(tokens(.coffeeScript, [##"square = (x) -> x * x # c"##, ##"greet = (name) => "Hi #{name}""##, ##"class A extends B then @x = yes"##, ##"###"##, ##"block"##, ##"###"##]), [
            [Pair(##"square"##, .function), Pair(##"# c"##, .comment)],
            [Pair(##"greet"##, .function), Pair(##""Hi "##, .string), Pair(##"#{name}"##, .variable), Pair(##"""##, .string)],
            [Pair(##"class"##, .keyword), Pair(##"extends"##, .keyword), Pair(##"then"##, .keyword), Pair(##"@x"##, .variable), Pair(##"yes"##, .constant)],
            [Pair(##"###"##, .comment)],
            [Pair(##"block"##, .comment)],
            [Pair(##"###"##, .comment)],
        ])
    }

    func testHaskell() {
        XCTAssertEqual(tokens(.haskell, [##"module Main where"##, ##"main :: IO ()"##, ##"main = putStrLn "Hi\n" -- c"##, ##"{- block -} f x' = Just 'a'"##, ##"x --> y"##]), [
            [Pair(##"module"##, .keyword), Pair(##"Main"##, .constant), Pair(##"where"##, .keyword)],
            [Pair(##"main"##, .function), Pair(##"IO"##, .constant)],
            [Pair(##"main"##, .function), Pair(##""Hi"##, .string), Pair(##"\n"##, .stringEscape), Pair(##"""##, .string), Pair(##"-- c"##, .comment)],
            [Pair(##"{- block -}"##, .comment), Pair(##"Just"##, .constant), Pair(##"'a'"##, .string)],
            [Pair(##"x"##, .function)],
        ])
    }

    func testErlang() {
        XCTAssertEqual(tokens(.erlang, [##"-module(hello)."##, ##"-export([start/0])."##, ##"start() -> io:format("Hi ~p~n", [?MODULE]), ok. % c"##, ##"loop(State) -> receive {msg, X} -> X end."##]), [
            [Pair(##"-module"##, .keyword)],
            [Pair(##"-export"##, .keyword), Pair(##"0"##, .number)],
            [Pair(##"start"##, .function), Pair(##"format"##, .function), Pair(##""Hi "##, .string), Pair(##"~p"##, .variable), Pair(##"~n"##, .variable), Pair(##"""##, .string), Pair(##"?MODULE"##, .constant), Pair(##"ok"##, .constant), Pair(##"% c"##, .comment)],
            [Pair(##"loop"##, .function), Pair(##"State"##, .variable), Pair(##"receive"##, .keyword), Pair(##"X"##, .variable), Pair(##"X"##, .variable), Pair(##"end"##, .keyword)],
        ])
    }

    func testLisp() {
        XCTAssertEqual(tokens(.lisp, [##"; AutoLISP"##, ##"(defun c:hello (/ x) (setq x "Hi") (princ x) (princ))"##, ##"(if (> n 0) 'yes nil)"##, ##"#| block |# (define (sq x) (* x x)) :key #t 3.5"##]), [
            [Pair(##"; AutoLISP"##, .comment)],
            [Pair(##"defun"##, .keyword), Pair(##"c:hello"##, .function), Pair(##"setq"##, .keyword), Pair(##""Hi""##, .string)],
            [Pair(##"if"##, .keyword), Pair(##"0"##, .number), Pair(##"'yes"##, .variable), Pair(##"nil"##, .constant)],
            [Pair(##"#| block |#"##, .comment), Pair(##"define"##, .keyword), Pair(##":key"##, .constant), Pair(##"#t"##, .constant), Pair(##"3.5"##, .number)],
        ])
    }

    func testOcaml() {
        XCTAssertEqual(tokens(.ocaml, [##"let rec fact n = if n = 0 then 1 else n * fact (n - 1) (* c *)"##, ##"type t = Some of int | None;; print_string "hi""##]), [
            [Pair(##"let"##, .keyword), Pair(##"rec"##, .keyword), Pair(##"fact"##, .function), Pair(##"if"##, .keyword), Pair(##"0"##, .number), Pair(##"then"##, .keyword), Pair(##"1"##, .number), Pair(##"else"##, .keyword), Pair(##"1"##, .number), Pair(##"(* c *)"##, .comment)],
            [Pair(##"type"##, .keyword), Pair(##"Some"##, .constant), Pair(##"of"##, .keyword), Pair(##"None"##, .constant), Pair(##""hi""##, .string)],
        ])
    }

    func testSmalltalk() {
        XCTAssertEqual(tokens(.smalltalk, [##"Object subclass: #Point instanceVariableNames: 'x y' "comment""##, ##"^ self x: 3 y: $a"##, ##"[:each | each printString] value: 16r1F"##]), [
            [Pair(##"subclass:"##, .function), Pair(##"#Point"##, .constant), Pair(##"instanceVariableNames:"##, .function), Pair(##"'x y'"##, .string), Pair(##""comment""##, .comment)],
            [Pair(##"^"##, .keyword), Pair(##"self"##, .constant), Pair(##"x:"##, .function), Pair(##"3"##, .number), Pair(##"y:"##, .function), Pair(##"$a"##, .string)],
            [Pair(##":each"##, .variable), Pair(##"value:"##, .function), Pair(##"16r1F"##, .number)],
        ])
    }

    func testMatlab() {
        XCTAssertEqual(tokens(.matlab, [##"function [a, b] = stats(x) % c"##, ##"y = x'; s = 'it''s'; t = "d";"##, ##"%{"##, ##"block"##, ##"%}"##, ##"for i = 1:10, z(i) = 3.5e-2i; end"##, ##"function run"##, ##"result = compute(5)"##]), [
            [Pair(##"function"##, .keyword), Pair(##"stats"##, .function), Pair(##"% c"##, .comment)],
            [Pair(##"'it"##, .string), Pair(##"''"##, .stringEscape), Pair(##"s'"##, .string), Pair(##""d""##, .string)],
            [Pair(##"%{"##, .comment)],
            [Pair(##"block"##, .comment)],
            [Pair(##"%}"##, .comment)],
            [Pair(##"for"##, .keyword), Pair(##"1"##, .number), Pair(##"10"##, .number), Pair(##"3.5e-2i"##, .number), Pair(##"end"##, .keyword)],
            [Pair(##"function"##, .keyword), Pair(##"run"##, .function)],
            [Pair(##"5"##, .number)],
        ])
    }

    func testFortran() {
        XCTAssertEqual(tokens(.fortran, [##"program hello ! c"##, ##"  implicit none"##, ##"  real(kind=8) :: x = 1.5d0"##, ##"  if (x .gt. 0 .and. .true.) then"##, ##"    print *, 'It''s'"##, ##"  end if"##, ##"C fixed-form comment"##, ##"      CALL FOO(X)"##]), [
            [Pair(##"program"##, .keyword), Pair(##"! c"##, .comment)],
            [Pair(##"implicit"##, .keyword), Pair(##"none"##, .keyword)],
            [Pair(##"real"##, .keyword), Pair(##"kind"##, .keyword), Pair(##"8"##, .number), Pair(##"1.5d0"##, .number)],
            [Pair(##"if"##, .keyword), Pair(##".gt."##, .operator), Pair(##"0"##, .number), Pair(##".and."##, .operator), Pair(##".true."##, .constant), Pair(##"then"##, .keyword)],
            [Pair(##"print"##, .keyword), Pair(##"'It"##, .string), Pair(##"''"##, .stringEscape), Pair(##"s'"##, .string)],
            [Pair(##"end"##, .keyword), Pair(##"if"##, .keyword)],
            [Pair(##"C fixed-form comment"##, .comment)],
            [Pair(##"CALL"##, .keyword), Pair(##"FOO"##, .function)],
        ])
    }

    func testLatex() {
        XCTAssertEqual(tokens(.latex, [##"\section{Intro} % comment"##, ##"\begin{document} Text with $x^2 + \alpha$ and \textbf{bold}."##, ##"$$"##, ##"E = mc^2"##, ##"$$"##, ##"50\% done"##]), [
            [Pair(##"\section{Intro}"##, .heading), Pair(##"% comment"##, .comment)],
            [Pair(##"\begin{document}"##, .function), Pair(##"$x^2 + "##, .code), Pair(##"\a"##, .code), Pair(##"lpha$"##, .code), Pair(##"\textbf"##, .keyword), Pair(##"{"##, .operator), Pair(##"bold"##, .emphasis), Pair(##"}"##, .operator)],
            [Pair(##"$$"##, .code)],
            [Pair(##"E = mc^2"##, .code)],
            [Pair(##"$$"##, .code)],
            [Pair(##"\%"##, .keyword)],
        ])
    }

    func testPostScript() {
        XCTAssertEqual(tokens(.postScript, [##"%!PS-Adobe-3.0"##, ##"%%BoundingBox: 0 0 100 100"##, ##"/Helvetica findfont 12 scalefont setfont"##, ##"72 72 moveto (Hello \(world\)) show showpage % c"##]), [
            [Pair(##"%!PS-Adobe-3.0"##, .keyword)],
            [Pair(##"%%BoundingBox: 0 0 100 100"##, .keyword)],
            [Pair(##"/Helvetica"##, .constant), Pair(##"findfont"##, .keyword), Pair(##"12"##, .number), Pair(##"scalefont"##, .keyword), Pair(##"setfont"##, .keyword)],
            [Pair(##"72"##, .number), Pair(##"72"##, .number), Pair(##"moveto"##, .keyword), Pair(##"(Hello "##, .string), Pair(##"\("##, .stringEscape), Pair(##"world"##, .string), Pair(##"\)"##, .stringEscape), Pair(##")"##, .string), Pair(##"show"##, .keyword), Pair(##"showpage"##, .keyword), Pair(##"% c"##, .comment)],
        ])
    }

    func testCmake() {
        XCTAssertEqual(tokens(.cmake, [##"cmake_minimum_required(VERSION 3.20) # c"##, ##"project(NotepadS LANGUAGES CXX)"##, ##"if(WIN32 AND NOT "${X}" STREQUAL "")"##, ##"  target_link_libraries(app PUBLIC ${LIBS})"##, ##"endif()"##]), [
            [Pair(##"cmake_minimum_required"##, .function), Pair(##"VERSION"##, .constant), Pair(##"3.20"##, .number), Pair(##"# c"##, .comment)],
            [Pair(##"project"##, .function), Pair(##"LANGUAGES"##, .constant), Pair(##"CXX"##, .constant)],
            [Pair(##"if"##, .keyword), Pair(##"WIN32"##, .constant), Pair(##"AND"##, .constant), Pair(##"NOT"##, .constant), Pair(##"""##, .string), Pair(##"${X}"##, .variable), Pair(##"""##, .string), Pair(##"STREQUAL"##, .constant), Pair(##""""##, .string)],
            [Pair(##"target_link_libraries"##, .function), Pair(##"PUBLIC"##, .constant), Pair(##"${LIBS}"##, .variable)],
            [Pair(##"endif"##, .keyword)],
        ])
    }

    func testPascal() {
        XCTAssertEqual(tokens(.pascal, [##"program Hello; // c"##, ##"{$APPTYPE CONSOLE}"##, ##"uses SysUtils;"##, ##"procedure TForm1.Button1Click(Sender: TObject);"##, ##"var i: Integer;"##, ##"begin { comment }"##, ##"  WriteLn('It''s ', i, #13#10); Result := nil; x := $FF;"##, ##"END."##]), [
            [Pair(##"program"##, .keyword), Pair(##"// c"##, .comment)],
            [Pair(##"{$APPTYPE CONSOLE}"##, .keyword)],
            [Pair(##"uses"##, .keyword)],
            [Pair(##"procedure"##, .keyword), Pair(##"TForm1.Button1Click"##, .function)],
            [Pair(##"var"##, .keyword), Pair(##"Integer"##, .keyword)],
            [Pair(##"begin"##, .keyword), Pair(##"{ comment }"##, .comment)],
            [Pair(##"'It"##, .string), Pair(##"''"##, .stringEscape), Pair(##"s '"##, .string), Pair(##"#13"##, .string), Pair(##"#10"##, .string), Pair(##"Result"##, .constant), Pair(##"nil"##, .constant), Pair(##"$FF"##, .number)],
            [Pair(##"END"##, .keyword)],
        ])
    }

    func testCobol() {
        XCTAssertEqual(tokens(.cobol, [##"       IDENTIFICATION DIVISION."##, ##"       PROGRAM-ID. HELLO."##, ##"      * comment line"##, ##"       01 WS-NAME PIC X(10) VALUE SPACES."##, ##"           DISPLAY "Hello" *> c"##, ##"           IF X > 10 PERFORM P1 END-IF"##, ##"           STOP RUN."##]), [
            [Pair(##"IDENTIFICATION"##, .keyword), Pair(##"DIVISION"##, .keyword)],
            [Pair(##"PROGRAM-ID"##, .keyword)],
            [Pair(##"      * comment line"##, .comment)],
            [Pair(##"01"##, .number), Pair(##"PIC"##, .keyword), Pair(##"10"##, .number), Pair(##"VALUE"##, .keyword), Pair(##"SPACES"##, .constant)],
            [Pair(##"DISPLAY"##, .keyword), Pair(##""Hello""##, .string), Pair(##"*> c"##, .comment)],
            [Pair(##"IF"##, .keyword), Pair(##"10"##, .number), Pair(##"PERFORM"##, .keyword), Pair(##"END-IF"##, .keyword)],
            [Pair(##"STOP"##, .keyword), Pair(##"RUN"##, .keyword)],
        ])
    }

    func testAda() {
        XCTAssertEqual(tokens(.ada, [##"with Ada.Text_IO; use Ada.Text_IO; -- c"##, ##"procedure Hello is"##, ##"   S : String := "Hi ""x""";"##, ##"begin Put_Line (S'Image & 'c'); X := 16#FF#; end Hello;"##]), [
            [Pair(##"with"##, .keyword), Pair(##"use"##, .keyword), Pair(##"-- c"##, .comment)],
            [Pair(##"procedure"##, .keyword), Pair(##"Hello"##, .function), Pair(##"is"##, .keyword)],
            [Pair(##""Hi "##, .string), Pair(##""""##, .stringEscape), Pair(##"x"##, .string), Pair(##""""##, .stringEscape), Pair(##"""##, .string)],
            [Pair(##"begin"##, .keyword), Pair(##"'Image"##, .property), Pair(##"'c'"##, .string), Pair(##"16#FF#"##, .number), Pair(##"end"##, .keyword)],
        ])
    }

    func testAssembly() {
        XCTAssertEqual(tokens(.assembly, [##"section .text"##, ##"global _start ; c"##, ##"_start:"##, ##"    mov eax, 1"##, ##"    xor ebx, ebx"##, ##"    int 0x80"##, ##"loop:  dec rcx"##, ##"  .globl main"##, ##"    movl $42, %eax # gas"##, ##"msg db "Hi", 10"##]), [
            [Pair(##"section"##, .keyword), Pair(##".text"##, .keyword)],
            [Pair(##"global"##, .keyword), Pair(##"; c"##, .comment)],
            [Pair(##"_start:"##, .function)],
            [Pair(##"mov"##, .keyword), Pair(##"eax"##, .variable), Pair(##"1"##, .number)],
            [Pair(##"xor"##, .keyword), Pair(##"ebx"##, .variable), Pair(##"ebx"##, .variable)],
            [Pair(##"int"##, .keyword), Pair(##"0x80"##, .number)],
            [Pair(##"loop:"##, .function), Pair(##"rcx"##, .variable)],
            [Pair(##".globl"##, .keyword)],
            [Pair(##"movl"##, .keyword), Pair(##"$42"##, .number), Pair(##"%eax"##, .variable)],
            [Pair(##"msg"##, .keyword), Pair(##"db"##, .keyword), Pair(##""Hi""##, .string), Pair(##"10"##, .number)],
        ])
    }

    func testD() {
        XCTAssertEqual(tokens(.d, [##"import std.stdio; // c"##, ##"void main() @safe { writeln("Hi"); auto x = 0xFFuL; }"##, ##"/+ nested +/ int[] a = [1, 2];"##]), [
            [Pair(##"import"##, .keyword), Pair(##"// c"##, .comment)],
            [Pair(##"void"##, .keyword), Pair(##"main"##, .function), Pair(##"@safe"##, .function), Pair(##"writeln"##, .function), Pair(##""Hi""##, .string), Pair(##"auto"##, .keyword), Pair(##"0xFFuL"##, .number)],
            [Pair(##"/+ nested +/"##, .comment), Pair(##"int"##, .keyword), Pair(##"1"##, .number), Pair(##"2"##, .number)],
        ])
    }

    func testVerilog() {
        XCTAssertEqual(tokens(.verilog, [##"module counter(input clk, output reg [7:0] q); // c"##, ##"  always @(posedge clk) q <= q + 8'h01;"##, ##"  initial $display("hi");"##, ##"`define WIDTH 8"##, ##"endmodule"##]), [
            [Pair(##"module"##, .keyword), Pair(##"input"##, .keyword), Pair(##"output"##, .keyword), Pair(##"reg"##, .keyword), Pair(##"7"##, .number), Pair(##"0"##, .number), Pair(##"// c"##, .comment)],
            [Pair(##"always"##, .keyword), Pair(##"posedge"##, .keyword), Pair(##"8'h01"##, .number)],
            [Pair(##"initial"##, .keyword), Pair(##"$display"##, .function), Pair(##""hi""##, .string)],
            [Pair(##"`define"##, .keyword), Pair(##"8"##, .number)],
            [Pair(##"endmodule"##, .keyword)],
        ])
    }

    func testVhdl() {
        XCTAssertEqual(tokens(.vhdl, [##"library IEEE; use IEEE.STD_LOGIC_1164.ALL; -- c"##, ##"entity Counter is port (clk : in std_logic); end Counter;"##, ##"if rising_edge(clk) and clk'event then q <= '1'; x <= X"FF"; end if;"##]), [
            [Pair(##"library"##, .keyword), Pair(##"use"##, .keyword), Pair(##"ALL"##, .keyword), Pair(##"-- c"##, .comment)],
            [Pair(##"entity"##, .keyword), Pair(##"is"##, .keyword), Pair(##"port"##, .keyword), Pair(##"in"##, .keyword), Pair(##"std_logic"##, .constant), Pair(##"end"##, .keyword)],
            [Pair(##"if"##, .keyword), Pair(##"rising_edge"##, .constant), Pair(##"and"##, .keyword), Pair(##"'event"##, .property), Pair(##"then"##, .keyword), Pair(##"'1'"##, .number), Pair(##"X"FF""##, .number), Pair(##"end"##, .keyword), Pair(##"if"##, .keyword)],
        ])
    }

    // MARK: - Detection

    func testObjectiveCAndMATLABShareDotM() {
        XCTAssertEqual(Language.detect(fileName: "AppDelegate.m", firstLine: "#import \"AppDelegate.h\""), .objectiveC)
        XCTAssertEqual(Language.detect(fileName: "View.m", firstLine: "//  View.m"), .objectiveC)
        XCTAssertEqual(Language.detect(fileName: "View.m", firstLine: "@implementation View"), .objectiveC)
        XCTAssertEqual(Language.detect(fileName: "stats.m", firstLine: "function y = stats(x)"), .matlab)
        XCTAssertEqual(Language.detect(fileName: "script.m", firstLine: "% Script"), .matlab)
        XCTAssertEqual(Language.detect(fileName: "empty.m", firstLine: ""), .matlab)
        XCTAssertEqual(Language.detect(fileName: "Bridge.mm", firstLine: nil), .objectiveC)
    }

    func testDetectionOfNewLanguages() {
        XCTAssertEqual(Language.detect(fileName: "CMakeLists.txt", firstLine: nil), .cmake)
        XCTAssertEqual(Language.detect(fileName: "build.gradle", firstLine: nil), .groovy)
        XCTAssertEqual(Language.detect(fileName: "Jenkinsfile", firstLine: nil), .groovy)
        XCTAssertEqual(Language.detect(fileName: "acad.LSP", firstLine: nil), .lisp)
        XCTAssertEqual(Language.detect(fileName: "Unit1.pas", firstLine: nil), .pascal)
        XCTAssertEqual(Language.detect(fileName: "Project1.dpr", firstLine: nil), .pascal)
        XCTAssertEqual(Language.detect(fileName: "PAYROLL.CBL", firstLine: nil), .cobol)
        XCTAssertEqual(Language.detect(fileName: "setup.reg", firstLine: nil), .registry)
        XCTAssertEqual(Language.detect(fileName: "run.BAT", firstLine: nil), .batch)
        XCTAssertEqual(Language.detect(fileName: "boot.S", firstLine: nil), .assembly)
        XCTAssertEqual(Language.detect(fileName: "main.f90", firstLine: nil), .fortran)
        XCTAssertEqual(Language.detect(fileName: "thesis.tex", firstLine: nil), .latex)
    }

    func testEveryLanguageNameMatchesItsGrammar() {
        for language in Language.allCases {
            guard let grammar = language.grammar else { continue }
            XCTAssertEqual(language.displayName, grammar.name)
        }
    }

    // MARK: - Menu groups

    func testLanguagesGroupedByInitial() {
        let groups = Language.groupedByInitial
        let listed = groups.flatMap(\.languages)
        XCTAssertEqual(listed.count, Language.allCases.count - 1, "every language once, plain text not grouped")
        XCTAssertEqual(Set(listed).count, listed.count)
        XCTAssertFalse(listed.contains(.plainText))
        XCTAssertEqual(groups.map(\.initial), groups.map(\.initial).sorted(), "letters in order")
        for group in groups {
            XCTAssertTrue(group.languages.allSatisfy { $0.displayName.uppercased().hasPrefix(group.initial) })
        }
        XCTAssertEqual(groups.first { $0.initial == "P" }?.languages,
                       [.pascal, .perl, .php, .postScript, .powerShell, .python])
    }
}
