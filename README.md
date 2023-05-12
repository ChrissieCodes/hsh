# hsh
~~Don't use this, it's not ready!~~
You probably don't want to use this yet, while I have started to dog food this
as my shell... I'm crazy.

## Goals
 - Support *modern* pttys
 - Composable vs decomposable mode

## [De]composable mode
 A default, unconfigured install of hsh should enable all features and
 functionality. Running hsh non-interactive, or [other] should disable all
 helful, or context aware features unless explicitly enabled.

## Install
install zig (you probably need zig master, or atleast > v0.10)<br>
clone [hsh]<br>
~~`zig build run`~~<br>
`zig build`<br>
`./zig-out/bin/hsh`

(`zig build run` does some magic that causes hsh to segv)

## TODO
 - [x] basic parsing
 - [ ] .hshrc support
 - [x] exec
   - [ ] friendly exec
   - [ ] && success
   - [ ] || failues
   - [ ] ; cmd
 - [ ] IoRedir
   - [x] | func
   - [ ] > std clobber
   - [ ] >> std append
   - [ ] 2> err clobber
   - [ ] 2>&1 err to out
   - [ ] < in
   - [ ] << here-doc;
 - [ ] tab complete
   - [x] cwd
   - [ ] the rest
 - [x] history
   - [ ] advanced history
 - [ ] sane error handling
 - [ ] complex parsing
 - [ ] context aware hints
 - [ ] built ins
   - [ ] alias
   - [ ] bg
   - [x] cd
   - [ ] colon
   - [ ] disown
   - [ ] dot
   - [ ] echo
   - [ ] eval
   - [ ] exec
   - [ ] exit
   - [ ] export
   - [ ] fg
   - [ ] help
   - [ ] jobs
   - [ ] kill?
   - [ ] pwd
   - [ ] set
   - [ ] shift
   - [ ] source
   - [ ] unalias
   - [ ] unset
   - [ ] wait
   - [ ] which
   - [ ] the rest?
 - [ ] globs
 - [ ] script support?
   - [ ] logic (if, else, elif, case)
   - [ ] loops (for, while)
 - [ ] env
 - [ ] real path support
 - [ ] debugging configuration

