# frozen_string_literal: true

require 'ruzzy/regex_samples'
require 'test/unit'

class RegexSamplesTest < Test::Unit::TestCase
  def test_multi_char_literal
    assert_sample_match(/FUZZREGEX/)
  end

  def test_two_char_literal
    assert_sample_match(/ab/)
  end

  def test_single_char_literal_filtered
    # libFuzzer's memcmp hook needs n > 1, so single-byte samples are dropped
    assert_no_sample(/a/)
  end

  def test_empty_pattern_filtered
    assert_no_sample(//)
  end

  def test_anchor_caret
    assert_sample_match(/^foo/)
  end

  def test_anchor_dollar
    assert_sample_match(/foo$/)
  end

  def test_anchor_uppercase_a
    assert_sample_match(/\Afoo/)
  end

  def test_anchor_lowercase_z
    assert_sample_match(/foo\z/)
  end

  def test_anchor_word_boundary
    assert_sample_match(/\bword\b/)
  end

  def test_only_anchors_filtered
    # /^$/ generates "" which has length 0
    assert_no_sample(/^$/)
  end

  def test_alternation
    assert_sample_match(/(foo|bar)/)
  end

  def test_alternation_picks_first_branch
    assert_equal 'FUZZ_FOO', Ruzzy::RegexSamples.sample_for(/(FUZZ_FOO|FUZZ_BAR)/)
  end

  def test_top_level_alternation
    assert_sample_match(/aa|bb|cc/)
  end

  def test_nested_alternation
    assert_sample_match(/(foo|(bazz|quxx))/)
  end

  def test_alternation_with_different_length_branches
    assert_sample_match(/(short|much_longer)/)
  end

  def test_digit
    assert_sample_match(/\d\d/)
  end

  def test_non_digit
    assert_sample_match(/\D\D/)
  end

  def test_word
    assert_sample_match(/\w\w/)
  end

  def test_non_word
    assert_sample_match(/\W\W/)
  end

  def test_space
    assert_sample_match(/\s\s/)
  end

  def test_non_space
    assert_sample_match(/\S\S/)
  end

  def test_hex
    assert_sample_match(/\h\h/)
  end

  def test_dot_any
    # Use [^\n] semantics — Onigmo's . matches anything but newline by default
    assert_sample_match(/../)
  end

  def test_linebreak
    assert_sample_match(/\R\R/)
  end

  def test_character_set_literal_members
    assert_sample_match(/[abc][abc]/)
  end

  def test_character_set_range
    assert_sample_match(/[a-z][a-z]/)
  end

  def test_character_set_digit_range
    assert_sample_match(/[0-9][0-9]/)
  end

  def test_character_set_hex_range
    assert_sample_match(/[0-9a-f][0-9a-f]/)
  end

  def test_character_set_with_char_type
    assert_sample_match(/[\d][\d]/)
  end

  def test_character_set_mixed_members
    assert_sample_match(/[a\d][a\d]/)
  end

  def test_negative_character_set_returns_nil
    # Walker explicitly skips negative sets — inverting Unicode safely is a
    # tarpit and the existing reg->exact path covers patterns with a forced
    # literal anyway.
    assert_no_sample(/[^abc]+/)
  end

  def test_posix_class_in_set
    assert_sample_match(/[[:digit:]][[:digit:]]/)
  end

  def test_posix_class_alpha
    assert_sample_match(/[[:alpha:]][[:alpha:]]/)
  end

  def test_posix_class_space
    assert_sample_match(/[[:space:]][[:space:]]/)
  end

  def test_plus
    # /a+/ would emit "a" (1 byte), which the compute() length guard drops.
    # /ab+/ emits "ab" — clears the threshold and exercises the quantifier path.
    assert_sample_match(/ab+/)
  end

  def test_star_inside_sequence
    # `a*b*c` — quantifier min=0; walker still emits 1 rep so sample is "abc"
    assert_sample_match(/a*b*c/)
  end

  def test_optional_inside_sequence
    assert_sample_match(/ab?c/)
  end

  def test_exact_count
    sample = Ruzzy::RegexSamples.sample_for(/a{3}/)
    assert_equal 'aaa', sample
  end

  def test_range_count_uses_min
    sample = Ruzzy::RegexSamples.sample_for(/a{2,5}/)
    assert_equal 'aa', sample
  end

  def test_quantifier_on_char_class
    assert_sample_match(/[0-9a-f]{4}/)
  end

  def test_quantifier_on_group
    assert_sample_match(/(ab){3}/)
  end

  def test_zero_quantifier_drops_content
    # `(ab){0}cd` — `ab` is dropped, only `cd` remains
    sample = Ruzzy::RegexSamples.sample_for(/(ab){0}cd/)
    assert_equal 'cd', sample
  end

  def test_capturing_group
    assert_sample_match(/(foo)/)
  end

  def test_non_capturing_group
    assert_sample_match(/(?:foo)/)
  end

  def test_named_group
    assert_sample_match(/(?<name>foo)/)
  end

  def test_atomic_group
    assert_sample_match(/(?>foo)/)
  end

  def test_options_group
    assert_sample_match(/(?i:FOO)/)
  end

  def test_nested_groups
    assert_sample_match(/((foo))/)
  end

  def test_newline_escape
    assert_sample_match(/a\nb/)
  end

  def test_tab_escape
    assert_sample_match(/a\tb/)
  end

  def test_return_escape
    assert_sample_match(/a\rb/)
  end

  def test_hex_escape
    # \x41 is 'A'
    assert_sample_match(/a\x41b/)
  end

  def test_unicode_codepoint_escape
    assert_sample_match(/aBb/)
  end

  def test_octal_escape
    assert_sample_match(/a\101b/)
  end

  def test_backreference_returns_nil
    assert_no_sample(/(\d+)-\1/)
  end

  def test_named_backreference_returns_nil
    assert_no_sample(/(?<n>\d+)-\k<n>/)
  end

  def test_lookahead_matched_after_body
    # Walker treats lookahead body as empty contribution; validation drops
    # samples that don't satisfy the assertion. `/foo(?=bar)bar/` is satisfiable
    # because the lookahead at position 3 sees "bar" which is also the literal
    # that follows. Synthesized "foobar" matches.
    assert_sample_match(/foo(?=bar)bar/)
  end

  def test_lookahead_unsatisfied_returns_nil
    # `/foo(?=bar)/` requires "bar" after "foo" but doesn't emit those bytes.
    # Walker generates "foo"; validation fails because there's no "bar" after.
    assert_no_sample(/foo(?=bar)/)
  end

  def test_negative_lookahead_doesnt_crash
    # May or may not produce a sample depending on validation; just ensure no
    # exception escapes.
    assert_nothing_raised do
      Ruzzy::RegexSamples.sample_for(/foo(?!xyz)bar/)
    end
  end

  def test_lookbehind_doesnt_crash
    assert_nothing_raised do
      Ruzzy::RegexSamples.sample_for(/(?<=foo)bar/)
    end
  end

  def test_version_string
    assert_sample_match(/v\d+\.\d+/)
  end

  def test_phone_number
    assert_sample_match(/\d{3}-\d{4}/)
  end

  def test_http_version
    assert_sample_match(%r{\bHTTP/\d\.\d})
  end

  def test_fuzz_regex_with_hex_tail
    assert_sample_match(/FUZZREGEX-[0-9a-f]{4}/)
  end

  def test_email_like
    assert_sample_match(/\w+@\w+\.\w+/)
  end

  def test_uuid_like
    assert_sample_match(/[0-9a-f]{8}-[0-9a-f]{4}/)
  end

  def test_anchored_alternation
    assert_sample_match(/\A(begin|start)/)
  end

  def test_content_type_header
    assert_sample_match(%r{\bContent-Type:\s*\w+/\w+})
  end

  def test_cache_returns_identical_string_object
    re = /FUZZCACHE/
    first = Ruzzy::RegexSamples.sample_for(re)
    second = Ruzzy::RegexSamples.sample_for(re)
    assert_same first, second
  end

  def test_cache_remembers_nil_result
    # /[^abc]/ has a negative set and a single-char body; walker returns nil.
    # The cache stores the NONE sentinel so a second lookup is still nil.
    re = /[^abc]/
    first = Ruzzy::RegexSamples.sample_for(re)
    second = Ruzzy::RegexSamples.sample_for(re)
    assert_nil first
    assert_nil second
  end

  def test_distinct_regexps_get_distinct_samples
    sample_foo = Ruzzy::RegexSamples.sample_for(/FUZZ_FOO/)
    sample_bar = Ruzzy::RegexSamples.sample_for(/FUZZ_BAR/)
    assert_not_equal sample_foo, sample_bar
  end

  def test_returned_sample_is_frozen
    sample = Ruzzy::RegexSamples.sample_for(/FUZZFROZEN/)
    assert_true sample.frozen?
  end

  def test_conditional_group_returns_nil
    # Conditional groups aren't synthesizable
    assert_no_sample(/(foo)(?(1)bar|baz)/)
  end

  private

  def assert_sample_match(regexp)
    sample = Ruzzy::RegexSamples.sample_for(regexp)
    assert_not_nil sample, "Expected a sample for #{regexp.inspect}, got nil"
    assert_match regexp, sample, "Sample #{sample.inspect} doesn't match #{regexp.inspect}"
  end

  def assert_no_sample(regexp)
    sample = Ruzzy::RegexSamples.sample_for(regexp)
    assert_nil sample, "Expected no sample for #{regexp.inspect}, got #{sample.inspect}"
  end
end
