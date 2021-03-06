--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  bc_constants.lua

  Constants for writing compiled grammars in Bitcode format.  See
  FILEFORMAT for more details.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

BC_INTFAS = 8
BC_INTFA = 9
BC_STRINGS = 10
BC_RTNS = 11
BC_RTN = 12

BC_INTFA_STATE = 0
BC_INTFA_FINAL_STATE = 1
BC_INTFA_TRANSITION = 2
BC_INTFA_TRANSITION_RANGE = 3

BC_STRING = 0

BC_RTN_INFO = 0
BC_RTN_STATE = 1
BC_RTN_TRANSITION_TERMINAL = 2
BC_RTN_TRANSITION_NONTERM = 3
BC_RTN_DECISION = 4
BC_RTN_IGNORE = 5

-- vim:et:sts=2:sw=2
