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
Ruzzy.c_install_regex_hooks
