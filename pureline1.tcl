  #! /usr/bin/env tclsh
  # tclline: An attempt at a pure tcl readline.
  
  # Use Tclx if available:
  catch {
      package require Tclx
  
      # Prevent sigint from killing our shell:
      signal ignore SIGINT
  }
  
  # Initialise our own env variables:
  foreach {var val} {
      PROMPT ">"
  } {
      if {![info exists env($var)]} {
          set env($var) $val
      }
  }
  foreach {var val} {
      CMDLINE ""
      CMDLINE_CURSOR 0
      CMDLINE_LINES 0
  } {
      set env($var) $val
  }
  unset var val

  set forever 0
  
  # Resource & history files:
  set RCFILE $env(HOME)/.tcllinerc
  
  proc ESC {} {
      return "\033"
  }
  
  proc shift {ls} {
      upvar 1 $ls LIST
      set ret [lindex $LIST 0]
      set LIST [lrange $LIST 1 end]
      return $ret
  }
  
  proc readbuf {txt} {
      upvar 1 $txt STRING
      
      set ret [string index $STRING 0]
      set STRING [string range $STRING 1 end]
      return $ret
  }
  
  proc goto {row {col 1}} {
      switch -- $row {
          "home" {set row 1}
      }
      print "[ESC]\[${row};${col}H" nowait
  }
  
  proc gotocol {col} {
      print "\r" nowait
      if {$col > 0} {
          print "[ESC]\[${col}C" nowait
      }
  }
  
  proc clear {} {
      print "[ESC]\[2J" nowait
      goto home
  }
  
  proc clearline {} {
      print "[ESC]\[2K\r" nowait
  }
  
  proc getColumns {} {
	  lassign [exec stty size] rows cols
      return $cols
  }
  
  proc prompt {{txt ""}} {
      global env
      
      set prompt "> "
      set txt "$prompt$txt"
      foreach {end mid} $env(CMDLINE_LINES) break
      
      # Calculate how many extra lines we need to display.
      # Also calculate cursor position:
      set n -1
      set totalLen 0
      set cursorLen [expr {$env(CMDLINE_CURSOR)+[string length $prompt]}]
      set row 0
      set col 0
      
      # Render output line-by-line to $out then copy back to $txt:
      set found 0
      set out [list]
      foreach line [split $txt "\n"] {
          set len [expr {[string length $line]+1}]
          incr totalLen $len
          if {$found == 0 && $totalLen >= $cursorLen} {
              set cursorLen [expr {$cursorLen - ($totalLen - $len)}]
              set col [expr {$cursorLen % $env(COLUMNS)}]
              set row [expr {$n + ($cursorLen / $env(COLUMNS)) + 1}]
              
              if {$cursorLen >= $len} {
                  set col 0
                  incr row
              }
              set found 1
          }
          incr n [expr {int(ceil(double($len)/$env(COLUMNS)))}]
          while {$len > 0} {
              lappend out [string range $line 0 [expr {$env(COLUMNS)-1}]]
              set line [string range $line $env(COLUMNS) end]
              set len [expr {$len-$env(COLUMNS)}]
          }
      }
      set txt [join $out "\n"]
      set row [expr {$n-$row}]
      
      # Reserve spaces for display:
      if {$end} {
          if {$mid} {
              print "[ESC]\[${mid}B" nowait
          }
          for {set x 0} {$x < $end} {incr x} {
              clearline
              print "[ESC]\[1A" nowait
          }
      }
      clearline
      set env(CMDLINE_LINES) $n
      
      # Output line(s):
      print "\r$txt"
      
      if {$row} {
          print "[ESC]\[${row}A" nowait
      }
      gotocol $col
      lappend env(CMDLINE_LINES) $row
  }
  
  proc print {txt {wait wait}} {
      # Sends output to stdout chunks at a time.
      # This is to prevent the terminal from
      # hanging if we output too much:
      while {[string length $txt]} {
          puts -nonewline [string range $txt 0 2047]
          set txt [string range $txt 2048 end]
          if {$wait == "wait"} {
              after 1
          }
      }
  }
  
  rename unknown _unknown
  proc unknown {args} {
      global env
  
      set name [lindex $args 0]
      set cmdline $env(CMDLINE)
      set cmd [string trim [regexp -inline {^\s*[^\s]+} $cmdline]]
      
      set new [auto_execok $name]
      if {$new != ""} {
          set redir ""
          if {$name == $cmd && [info command $cmd] == ""} {
              set redir ">&@ stdout <@ stdin"
          }
          if {[catch {
              uplevel 1 exec $redir $new [lrange $args 1 end]} ret]
          } {
              return
          }
          return $ret
      }
      
      eval _unknown $args
  }
  
  ################################
  # Key bindings
  ################################
  proc handleEscapes {} {
      global env
      upvar 1 keybuffer keybuffer
      set seq ""
      set found 0
      while {[set ch [readbuf keybuffer]] != ""} {
          append seq $ch
  
          switch -exact -- $seq {
              "\[A" { ;# Cursor Up (cuu1,up)}
              "\[B" { ;# Cursor Down}
              "\[C" { ;# Cursor Right (cuf1,nd)
                  if {$env(CMDLINE_CURSOR) < [string length $env(CMDLINE)]} {
                      incr env(CMDLINE_CURSOR)
                  }
                  set found 1; break
              }
              "\[D" { ;# Cursor Left
                  if {$env(CMDLINE_CURSOR) > 0} {
                      incr env(CMDLINE_CURSOR) -1
                  }
                  set found 1; break
              }
              "\[H" -
              "\[7~" -
              "\[1~" { ;# home
                  set env(CMDLINE_CURSOR) 0
                  set found 1; break
              }
              "\[3~" { ;# delete
                  if {$env(CMDLINE_CURSOR) < [string length $env(CMDLINE)]} {
                      set env(CMDLINE) [string replace $env(CMDLINE) \
                          $env(CMDLINE_CURSOR) $env(CMDLINE_CURSOR)]
                  }
                  set found 1; break
              }
              "\[F" -
              "\[K" -
              "\[8~" -
              "\[4~" { ;# end
                  set env(CMDLINE_CURSOR) [string length $env(CMDLINE)]
                  set found 1; break
              }
              "\[5~" { ;# Page Up }
              "\[6~" { ;# Page Down }
          }
      }
      return $found
  }
  
  proc handleControls {} {
      global env
      upvar 1 char char
      upvar 1 keybuffer keybuffer
  
      # Control chars start at a == \u0001 and count up.
      switch -exact -- $char {
          \u0003 { ;# ^c
              # doExit
          }
          \u0008 -
          \u007f { ;# ^h && backspace ?
              if {$env(CMDLINE_CURSOR) > 0} {
                  incr env(CMDLINE_CURSOR) -1
                  set env(CMDLINE) [string replace $env(CMDLINE) \
                      $env(CMDLINE_CURSOR) $env(CMDLINE_CURSOR)]
              }
          }
          \u001b { ;# ESC - handle escape sequences
              handleEscapes
          }
      }
      # Rate limiter:
      set keybuffer ""
  }

  
  ################################
  # main()
  ################################
  
  proc rawInput {} {
      fconfigure stdin -buffering none -blocking 0
      fconfigure stdout -buffering none -translation crlf
      exec stty raw -echo
  }
  
  proc lineInput {} {
      fconfigure stdin -buffering line -blocking 1
      fconfigure stdout -buffering line
      exec stty -raw echo
  }
  
  proc doExit {{code 0}} {
      global env HISTFILE
      
      # Reset terminal:
      print "[ESC]c[ESC]\[2J" nowait
      lineInput

      exit $code
  }
  
  if {[file exists $RCFILE]} {
      source $RCFILE
  }
  
  rawInput
  
  # This is to restore the environment on exit:
  # Do not unalias this!
  alias exit doExit
  
  proc tclline {} {
      global env
      set char ""
      set keybuffer [read stdin]
      set env(COLUMNS) [getColumns]
      
      while {$keybuffer != ""} {
          if {[eof stdin]} return
          set char [readbuf keybuffer]
          if {$char == ""} {
              # Sleep for a bit to reduce CPU time:
              after 40
              continue
          }
          
          if {[string is print $char]} {
              set x $env(CMDLINE_CURSOR)
              
              if {$x < 1 && [string trim $char] == ""} continue
              
              set trailing [string range $env(CMDLINE) $x end]
              set env(CMDLINE) [string replace $env(CMDLINE) $x end]
              append env(CMDLINE) $char
              append env(CMDLINE) $trailing
              incr env(CMDLINE_CURSOR)
          } elseif {$char == "\n" || $char == "\r"} {
              if {[info complete $env(CMDLINE)] &&
                  [string index $env(CMDLINE) end] != "\\"} {
                  lineInput
                  print "\n" nowait
                  uplevel #0 {
                      global env

                      set cmdline $env(CMDLINE)
                                           
                      # Run the command:
                      catch $cmdline res
                      if {$res != ""} {
                          print "$res\n"
                      }
                      
                      set env(CMDLINE) ""
                      set env(CMDLINE_CURSOR) 0
                      set env(CMDLINE_LINES) {0 0}
                  }
                  rawInput
              } else {
                  set x $env(CMDLINE_CURSOR)
                  
                  if {$x < 1 && [string trim $char] == ""} continue
                  
                  set trailing [string range $env(CMDLINE) $x end]
                  set env(CMDLINE) [string replace $env(CMDLINE) $x end]
                  append env(CMDLINE) $char
                  append env(CMDLINE) $trailing
                  incr env(CMDLINE_CURSOR)
              }
          } else {
              handleControls
          }
      }
      prompt $env(CMDLINE)
  }
  tclline
  
  fileevent stdin readable tclline
  vwait forever
  doExit