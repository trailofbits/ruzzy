# frozen_string_literal: true

# Hook Integer operations for tracing in SanitizerCoverage
class Integer
  alias ruzzy_eeql ==
  alias ruzzy_eeeql ===
  alias ruzzy_eql? eql?
  alias ruzzy_spc <=>
  alias ruzzy_lt <
  alias ruzzy_le <=
  alias ruzzy_gt >
  alias ruzzy_ge >=
  alias ruzzy_divo /
  alias ruzzy_div div
  alias ruzzy_divmod divmod

  def ==(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_eeql(other)
  end

  def ===(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_eeeql(other)
  end

  def eql?(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_eql?(other)
  end

  def <=>(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_spc(other)
  end

  def <(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_lt(other)
  end

  def <=(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_le(other)
  end

  def >(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_gt(other)
  end

  def >=(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_ge(other)
  end

  def /(other)
    Ruzzy.c_trace_div8(other)
    ruzzy_divo(other)
  end

  def div(other)
    Ruzzy.c_trace_div8(other)
    ruzzy_div(other)
  end

  def divmod(other)
    Ruzzy.c_trace_div8(other)
    ruzzy_divmod(other)
  end
end

# Hook Regexp match operations for tracing in SanitizerCoverage
class Regexp
  alias ruzzy_reeeql ===
  alias ruzzy_rematch match
  alias ruzzy_rematch_q match?
  alias ruzzy_retilde =~

  def ===(other)
    Ruzzy.c_trace_regex(self, other)
    ruzzy_reeeql(other)
  end

  def match(*args, &blk)
    Ruzzy.c_trace_regex(self, args.first)
    ruzzy_rematch(*args, &blk)
  end

  def match?(*args)
    Ruzzy.c_trace_regex(self, args.first)
    ruzzy_rematch_q(*args)
  end

  def =~(other)
    Ruzzy.c_trace_regex(self, other)
    ruzzy_retilde(other)
  end
end
