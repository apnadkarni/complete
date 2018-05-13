#
# repl - a package for Tcl command completion
# (c) 2018 Ashok P. Nadkarni
# See file LICENSE for licensing terms
#
# Credits: thanks to tkcon and various Wiki snippets

package require Tcl 8.6

namespace eval repl {}

proc repl::command {prefix {ip {}} {ns ::}} {
    # Finds all command names with the specified prefix
    #  prefix - a prefix to be matched with command names
    #  ip     - the interpreter whose context is to be used.
    #           Defaults to current interpreter.
    #  ns     - the namespace context for the command. Defaults to
    #           the global namespace if unspecified or the empty string.
    #
    # The command looks for all commands in the specified
    # interpreter and namespace context that begin with $prefix.
    #
    # The return value is a pair consisting of the longest common
    # prefix of all matching commands and a sorted list of all matching
    # commands.
    # If no commands matched, the first element is the passed in prefix
    # and the second element is an empty list.

    # Escape glob special characters in the prefix
    set esc_prefix [string map {* \\* ? \\? \\ \\\\} $prefix]

    #ruff
    # If the $ns is specified as the empty string, it defaults to the
    # global namespace.
    if {$ns eq ""} {
        set ns ::
    }

    # Look for matches in the target context
    set matches [_interp_eval $ip $ns ::info commands ${esc_prefix}*]
    return [_return_matches $prefix $matches]
}

proc repl::variable {prefix {ip {}} {ns ::}} {
    # Finds all variable names with the specified prefix
    #  prefix - a prefix to be matched with variable names
    #  ip     - the interpreter whose context is to be used.
    #           Defaults to current interpreter.
    #  ns     - the namespace context for the command. Defaults to
    #           the global namespace if unspecified or the empty string.
    #
    # The command looks for variable names in the specified
    # interpreter and namespace context that begin with $prefix.
    #
    # The return value is a pair consisting of the longest common
    # prefix of all matching commands and a sorted list of all matching
    # names.
    # If no variable names matched, the first element is the passed in prefix
    # and the second element is an empty list.

    # Escape glob special characters in the prefix
    set esc_prefix [string map {* \\* ? \\? \\ \\\\} $prefix]

    if {$ns eq ""} {
        set ns ::
    }

    # If $prefix is a partial array variable, the matching is done
    # against the array variables
    # Thanks to tkcon for this fragment
    if {[regexp {([^\(]*)\((.*)} $prefix -> arr elem_prefix]} {
        # Escape glob special characters
        set esc_elem [string map {* \\* ? \\? \\ \\\\} $elem_prefix]
        set elems [_interp_eval $ip $ns ::array names $arr ${esc_elem}*]
        if {[llength $elems] == 1} {
	    set var "$arr\([lindex $elems 0]\)"
            return [list $var [list $var]]
	} elseif {[llength $elems] > 1} {
            set common [tcl::prefix longest $elems $elem_prefix]
            set elems [lmap elem $elems {
                return -level 0 "$arr\($elem\)"
            }]
            return [list "$arr\($common" [lsort $elems]]
        }
        # Nothing matched
        return [list $prefix {}]
    } else {
        # Does not look like an array
        set matches [_interp_eval $ip $ns ::info vars ${esc_prefix}*]
        return [_return_matches $prefix $matches]
    }
}

proc repl::method {oo obj prefix {ip {}} {ns ::}} {
    # Finds all method names with the specified prefix for a given TclOO object
    #  oo     - the OO subsystem, one of 'oo', 'nsf', 'xotcl'
    #  obj    - object name token
    #  prefix - a prefix to be matched with the object's method names
    #  ip     - the interpreter whose context is to be used.
    #           Defaults to current interpreter.
    #  ns     - the namespace context for the command. Defaults to
    #           the global namespace if unspecified or the empty string.
    #
    # The command looks for all methods of the object in the specified
    # interpreter and namespace context that begin with $prefix.
    #
    # The return value is a pair consisting of the longest common
    # prefix of all matching methods and a sorted list of all matching
    # methods.  If $obj is not a TclOO object or if no methods
    # matched, the first element is the passed in prefix and the
    # second element is an empty list.

    if {$ns eq ""} {
        set ns ::
    }

    #ruff
    # The $obj argument may be the object name or passed in through
    # a variable reference.
    if {[string index $obj 0] eq "\$"} {
        # Resolve the variable reference
        set obj [_interp_eval $ip $ns set [string range $obj 1 end]]
    }
    
    # Escape glob special characters in the prefix
    set esc_prefix [string map {* \\* ? \\? \\ \\\\} $prefix]

    set matches {}
    switch -exact $oo {
        ensemble {
            TBD
        }
        oo {
            if {![_interp_eval $ip $ns ::info object isa object $obj]} {
                # Not an object.
                return [list $prefix {}]
            }

            set matches [lmap meth [_interp_eval $ip $ns ::info object methods $obj -all] {
                if {![string match ${esc_prefix}* $meth]} continue
                set meth
            }]
        }
        snit {
            TBD
        }
        nsf {
            # Next Scripting Framework
            if {[_interp_eval $ip $ns ::nsf::object::exists $obj]} {
                if {[string match ::* $prefix]} {
                    # NSF allows dispatch of unregistered methods via absolute paths
                    set abs_matches [_interp_eval $ip $ns ::info commands ${esc_prefix}*]
                    set ns_matches  [_interp_eval $ip $ns ::namespace children [namespace qualifiers ${esc_prefix}] ${esc_prefix}*]
                    set matches [concat $abs_matches $ns_matches]
                } else {
                    set matches [_interp_eval $obj ::nsf::methods::object::info::lookupmethods -callprotection public -path -- ${esc_prefix}*]
                }
            } 
        }
        xotcl {
            # XOTcl
            if {[_interp_eval $ip $ns ::info exists ::xotcl::version] &&
                [_interp_eval $ip $ns ::xotcl::Object isobject $obj]} {
                set matches [_interp_eval $ip $ns $obj info methods ${esc_prefix}*]
            }
        }
    }

    return [_return_matches $prefix $matches]
}

# Just a helper proc for constructing return values from match commands
proc repl::_return_matches {prefix matches} {
    if {[llength $matches] == 1} {
        # Single element list. Only one match found
        return [list [lindex $matches 0] $matches]
    } elseif {[llength $matches] > 1} {
        # Multiple matches. Return longest common prefix.
        # Note we need to use $prefix and not $esc_prefix here.
        return [list [tcl::prefix longest $matches $prefix] [lsort $matches]]
    } else {
        return [list $prefix {}]
    }
}

# Helper to evaluate commands in the target interpreter namespace
proc repl::_interp_eval {ip ns args} {
    return [interp eval $ip [list namespace eval $ns $args]]
}
