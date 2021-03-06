--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  compile.lua

  The top-level file for compiling an input grammar (written in a
  human-readable text format) into a compiled grammar in Bitcode.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "bootstrap/rtn"
require "bc"
require "bc_constants"

TerminalTransition = {name="TerminalTransition", order=1}
NontermTransition = {name="NontermTransition", order=2}
Decision = {name="Decision", order=3}

require "ll"
require "pp"

function load_grammar(file)
  -- First read grammar file

  local grm = io.open(file, "r")
  local grm_str = grm:read("*a")

  local grammar, attributes = parse_grammar(CharStream:new(grm_str))
  local first = compute_first_sets(grammar)
  local follow = compute_follow_sets(grammar, first)
  print(serialize(first))
  print(serialize(follow))


  -- First, determine what terminals (if any) conflict with each other.
  -- In this context, "conflict" means that a string of characters can
  -- be interpreted as one or more terminals.
  local conflicts = {}
  do
    local nfas = {}
    for name, terminal in pairs(attributes.terminals) do
      if type(terminal) == "string" then
        terminal = fa.IntFA:new{string=terminal}
      end
      table.insert(nfas, {terminal, name})
    end
    local uber_dfa = nfas_to_dfa(nfas, true)
    for state in each(uber_dfa:states()) do
      if type(state.final) == "table" then  -- more than one terminal ended in this state
        for term1 in each(state.final) do
          for term2 in each(state.final) do
            if term1 ~= term2 then
              conflicts[term1] = conflicts[term1] or Set:new()
              conflicts[term1]:add(term2)
            end
          end
        end
      end
    end
  end

  -- For each state in the grammar, create (or reuse) a DFA to run
  -- when we hit that state.
  local dfas = {}

  function has_conflicts(conflicts, dfa, terminals)
    for term in each(terminals) do
      if conflicts[term] then
        for conflict in each(conflicts[term]) do
          if dfa:contains(conflict) then
            return true, term, conflict
          end
        end
      end
    end
  end

  for nonterm, rtn in pairs(grammar) do
    -- print(nonterm)
    -- print(rtn)
    for state in each(rtn:states()) do
      local terminals = Set:new()
      for edge_val in state:transitions() do
        if not fa.is_nonterm(edge_val) then
          terminals:add(edge_val)
        end
      end

      state.lookahead = compute_lookahead_for_state(nonterm, state, first, follow)

      for terminal, nonterms in pairs(state.lookahead) do

        if terminals:contains(terminal) then
          error(string.format("Grammar is not LL(1): in nonterm %s, terminal %s leads to both a terminal and nonterms %s!", nonterm, terminal, serialize(nonterms)))
        elseif #nonterms > 1 then
          error(string.format("Grammar is not LL(1): in nonterm %s, terminal %s leads to more than one nonterminal (%s)!", nonterm, terminal, serialize(nonterms)))
        end

        terminals:add(terminal)
      end

      if has_conflicts(conflicts, terminals, terminals) then
        local has_conflict, c1, c2 = has_conflicts(conflicts, terminals, terminals)
        error(string.format("Can't build DFA inside %s, because terminals %s and %s conflict",
                            nonterm, c1, c2))
      end

      if terminals:count() > 0 then
        -- We now have a list of terminals we want to find when we are in this RTN
        -- state.  Now get a DFA that will match all of them, either by creating
        -- a new DFA or by finding an existing one that will work (without conflicting
        -- with any of our terminals).
        local found_dfa = false
        for i, dfa in ipairs(dfas) do
          -- will this dfa do?  it will if none of our terminals conflict with any of the
          -- existing terminals in this dfa.
          -- (we can probably compute this faster by pre-computing equivalence classes)
          if not has_conflicts(conflicts, dfa, terminals) then
            found_dfa = i
            break
          end
        end

        if found_dfa == false then
          new_dfa = Set:new()
          table.insert(dfas, new_dfa)
          found_dfa = #dfas
        end

        -- add all the terminals for this state to the dfa we found
        for term in each(terminals) do
          dfas[found_dfa]:add(term)
        end

        state.dfa = found_dfa
      end
    end
  end

  local real_dfas = {}
  for dfa in each(dfas) do
    local nfas = {}
    print(serialize(dfa))
    for term in each(dfa) do
      local target = attributes.terminals[term]
      if type(target) == "string" then
        target = fa.IntFA:new{string=target}
      end
      table.insert(nfas, {target, term})
    end
    local real_dfa = hopcroft_minimize(nfas_to_dfa(nfas))
    table.insert(real_dfas, real_dfa)
  end

  return grammar, attributes, real_dfas
end

function write_grammar(infilename, outfilename)
  local grammar, attributes, intfas = load_grammar(infilename)

  -- write Bitcode header
  bc_file = bc.File:new(outfilename, "GH")

  -- Enter a BLOCKINFO record to define abbreviations for all our records.
  -- See FILEFORMAT for a description of what all the record types mean.
  bc_file:enter_subblock(bc.BLOCKINFO)

  -- IntFA abbreviations
  bc_file:write_unabbreviated_record(bc.SETBID, BC_INTFA)

  bc_intfa_final_state = bc_file:define_abbreviation(4,
                                      bc.LiteralOp:new(BC_INTFA_FINAL_STATE),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(5))

  bc_intfa_state = bc_file:define_abbreviation(5,
                                      bc.LiteralOp:new(BC_INTFA_STATE),
                                      bc.VBROp:new(5))

  bc_intfa_transition = bc_file:define_abbreviation(6,
                                      bc.LiteralOp:new(BC_INTFA_TRANSITION),
                                      bc.VBROp:new(8),
                                      bc.VBROp:new(6))

  bc_intfa_transition_range = bc_file:define_abbreviation(7,
                                      bc.LiteralOp:new(BC_INTFA_TRANSITION_RANGE),
                                      bc.VBROp:new(8),
                                      bc.VBROp:new(8),
                                      bc.VBROp:new(6))

  -- Strings abbreviations
  bc_file:write_unabbreviated_record(bc.SETBID, BC_STRINGS)

  bc_string = bc_file:define_abbreviation(4,
                                      bc.LiteralOp:new(BC_STRING),
                                      bc.ArrayOp:new(bc.FixedOp:new(7)))

  -- RTN abbreviations
  bc_file:write_unabbreviated_record(bc.SETBID, BC_RTN)

  bc_rtn_info = bc_file:define_abbreviation(4,
                                      bc.LiteralOp:new(BC_RTN_INFO),
                                      bc.VBROp:new(6),
                                      bc.VBROp:new(4))

  bc_rtn_state = bc_file:define_abbreviation(5,
                                      bc.LiteralOp:new(BC_RTN_STATE),
                                      bc.VBROp:new(4),
                                      bc.VBROp:new(4),
                                      bc.FixedOp:new(1))

  bc_rtn_transition_terminal = bc_file:define_abbreviation(6,
                                      bc.LiteralOp:new(BC_RTN_TRANSITION_TERMINAL),
                                      bc.VBROp:new(6),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(4))

  bc_rtn_transition_nonterm = bc_file:define_abbreviation(7,
                                      bc.LiteralOp:new(BC_RTN_TRANSITION_NONTERM),
                                      bc.VBROp:new(6),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(4))

  bc_rtn_ignore = bc_file:define_abbreviation(8,
                                      bc.LiteralOp:new(BC_RTN_IGNORE),
                                      bc.VBROp:new(6))

  bc_rtn_decision = bc_file:define_abbreviation(9,
                                      bc.LiteralOp:new(BC_RTN_DECISION),
                                      bc.VBROp:new(6),
                                      bc.ArrayOp:new(bc.VBROp:new(4)))

  bc_file:end_subblock(bc.BLOCKINFO)

  print(string.format("Writing grammar to disk..."))

  local strings = {}
  local string_offsets = {}

  -- gather a list of all the strings from intfas
  for intfa in each(intfas) do
    for state in each(intfa:states()) do
      if state.final and not string_offsets[state.final] then
        string_offsets[state.final] = #strings
        table.insert(strings, state.final)
      end
    end
  end

  -- build an ordered list of RTNs and gather the strings from them
  local rtns = {{attributes.start, grammar[attributes.start]}}
  local rtns_offsets = {}
  rtns_offsets[grammar[attributes.start]] = 0
  for name, rtn in pairs(grammar) do
    if name ~= attributes.start then
      rtns_offsets[rtn] = #rtns
      if not string_offsets[name] then
        string_offsets[name] = #strings
        table.insert(strings, name)
      end

      table.insert(rtns, {name, rtn})

      for rtn_state in each(rtn:states()) do
        for edge_val, target_state, properties in rtn_state:transitions() do
          if properties and not string_offsets[properties.name] then
            string_offsets[properties.name] = #strings
            table.insert(strings, properties.name)
          end
        end
      end
    end
  end

  -- emit the strings
  print(string.format("Writing %d strings...", #strings))
  bc_file:enter_subblock(BC_STRINGS)
  for string in each(strings) do
    bc_file:write_abbreviated_record(bc_string, string)
  end
  bc_file:end_subblock(BC_STRINGS)

  -- emit the intfas
  print(string.format("Writing %d IntFAs...", #intfas))
  bc_file:enter_subblock(BC_INTFAS)
  for intfa in each(intfas) do
    bc_file:enter_subblock(BC_INTFA)
    local intfa_state_offsets = {}
    local intfa_transitions = {}

    -- make sure the start state is emitted first
    local states = intfa:states()
    states:remove(intfa.start)
    states = states:to_array()
    table.insert(states, 1, intfa.start)
    for i, state in ipairs(states) do
      intfa_state_offsets[state] = i - 1
      local this_state_transitions = {}
      for edge_val, target_state, properties in state:transitions() do
        for range in edge_val:each_range() do
          table.insert(this_state_transitions, {range, target_state})
        end
      end
      table.sort(this_state_transitions, function (a, b) return a[1].low < b[1].low end)
      for t in each(this_state_transitions) do table.insert(intfa_transitions, t) end
      if state.final then
        bc_file:write_abbreviated_record(bc_intfa_final_state, #this_state_transitions, string_offsets[state.final])
      else
        bc_file:write_abbreviated_record(bc_intfa_state, #this_state_transitions)
      end
    end

    print(string.format("  %d states, %d transitions", #states, #intfa_transitions))

    for transition in each(intfa_transitions) do
      local range, target_state = unpack(transition)
      target_state_offset = intfa_state_offsets[target_state]
      if range.low == range.high then
        bc_file:write_abbreviated_record(bc_intfa_transition, range.low, target_state_offset)
      else
        if range.high == math.huge then range.high = 255 end  -- temporary ASCII-specific hack
        bc_file:write_abbreviated_record(bc_intfa_transition_range, range.low, range.high, target_state_offset)
      end
    end

    bc_file:end_subblock(BC_INTFA)
  end
  bc_file:end_subblock(BC_INTFAS)

  -- create a sorted list of transitions out of each RTN state, for all RTNs
  local rtn_state_transitions = {}
  for name_rtn_pair in each(rtns) do
    local name, rtn = unpack(name_rtn_pair)
    for rtn_state in each(rtn:states()) do
      local this_state_transitions = {}
      for edge_val, target_state, properties in rtn_state:transitions() do
        if fa.is_nonterm(edge_val) then
          table.insert(this_state_transitions, {NontermTransition, rtn_state, {edge_val, target_state, properties}})
        else
          table.insert(this_state_transitions, {TerminalTransition, rtn_state, {edge_val, target_state, properties}})
        end
      end
      -- TODO adjust this for lookahead
      -- for terminal, stack in pairs(rtn_state.decisions) do
      --   table.insert(this_state_transitions, {Decision, rtn_state, {terminal, stack}})
      -- end

      table.sort(this_state_transitions, function (a, b) return a[1].order < b[1].order end)
      rtn_state_transitions[rtn_state] = this_state_transitions
    end
  end

  -- emit the RTNs
  bc_file:enter_subblock(BC_RTNS)
  print(string.format("Writing %d RTNs...", #rtns))
  for name_rtn_pair in each(rtns) do
    local name, rtn = unpack(name_rtn_pair)
    bc_file:enter_subblock(BC_RTN)
    bc_file:write_abbreviated_record(bc_rtn_info, string_offsets[name], attributes.slot_counts[name]-1)

    if attributes.ignore[name] then
      for ign_terminal in each(attributes.ignore[name]) do
        bc_file:write_abbreviated_record(bc_rtn_ignore, string_offsets[ign_terminal])
      end
    end

    local rtn_states = {}
    local rtn_state_offsets = {}
    local rtn_transitions = {}

    -- make sure the start state is emitted first
    local states = rtn:states()
    states:remove(rtn.start)
    states = states:to_array()
    table.insert(states, 1, rtn.start)

    -- emit states
    for i, rtn_state in pairs(states) do
      rtn_state_offsets[rtn_state] = i - 1
      local is_final = 0
      if rtn_state.final then is_final = 1 end
      -- states don't have an associated DFA if there are no outgoing transitions
      rtn_state.dfa = rtn_state.dfa or 1
      bc_file:write_abbreviated_record(bc_rtn_state, #rtn_state_transitions[rtn_state], rtn_state.dfa - 1, is_final)
      for t in each(rtn_state_transitions[rtn_state]) do
        table.insert(rtn_transitions, t)
      end
    end

    print(string.format("  %s: %d states, %d transitions", name, #states, #rtn_transitions))

    -- emit transitions
    for transition in each(rtn_transitions) do
      local transition_type, src_state, data = unpack(transition)
      if transition_type == Decision then
        local terminal, stack = unpack(data)
        local stack_str = ""
        for i, step in ipairs(stack) do
          --print(string.format("Trying to find %s, %d transitions to consider", serialize(step), #rtn_state_transitions[src_state]))
          for j, transition2 in ipairs(rtn_state_transitions[src_state]) do
            local transition_type2, src_state2, data2 = unpack(transition2)
            local edge_val, target_state, properties = unpack(data2)
            --print(string.format("Is it %s?", serialize(edge_val)))
            if edge_val == step then
              --print("Transition found!")
              stack_str = stack_str .. string.char(j-1)
              if i < #stack then
                src_state = grammar[edge_val.name].start
              end
              break
            end
            if j == #rtn_state_transitions[src_state] then
              error(string.format("Transition not found!  Step=%s", step))
            end
          end
        end
        -- print(serialize(stack))
        bc_file:write_abbreviated_record(bc_rtn_decision, string_offsets[terminal], stack_str)
      else
        local edge_val, target_state, properties = unpack(data)
        target_state_offset = rtn_state_offsets[target_state]
        if transition_type == TerminalTransition then
          bc_file:write_abbreviated_record(bc_rtn_transition_terminal, string_offsets[edge_val],
                                           rtn_state_offsets[target_state], string_offsets[properties.name],
                                           properties.slotnum-1)
        else
          bc_file:write_abbreviated_record(bc_rtn_transition_nonterm, rtns_offsets[grammar[edge_val.name]],
                                           rtn_state_offsets[target_state], string_offsets[properties.name],
                                           properties.slotnum-1)
        end
      end
    end

    bc_file:end_subblock(BC_RTN)
  end
  bc_file:end_subblock(BC_RTNS)
end

write_grammar(arg[1], arg[2])

-- vim:et:sts=2:sw=2
