# frozen_string_literal: true

# Optional second layer of Regexp coverage for libFuzzer. When the
# `regexp_parser` gem is installed, `sample_for` parses a Regexp's AST and
# synthesizes one matching sample string per pattern, caching the result.
# Without the gem, `sample_for` returns nil and behavior is byte-identical to
# the Onigmo-exact-only setup.

module Ruzzy
  module RegexSamples
    AVAILABLE = begin
      require 'regexp_parser'
      true
    rescue LoadError
      false
    end

    # Sentinel cached when we walked a pattern but couldn't synthesize a usable
    # sample. Distinguished from a real String so we don't re-walk every call.
    NONE = Object.new.freeze
    CACHE = ObjectSpace::WeakMap.new

    # Re-entry guard key. Computing a sample requires `Regexp::Parser.parse`,
    # which uses Regexp internally — those Regexp#=== / #match? calls flow
    # back through our monkey-patches and would infinitely recurse into
    # `sample_for`. Thread-local so multi-threaded callers don't clobber each
    # other's guards.
    COMPUTING_KEY = :ruzzy_regex_samples_computing

    # Single representative character used to satisfy a CharacterType node.
    # libFuzzer treats these as opaque bytes; the only requirement is that the
    # synthesized string actually matches the original Regexp (we verify with
    # `match?` before caching).
    CHAR_TYPE_REPRESENTATIVES = if AVAILABLE
      {
        Regexp::Expression::CharacterType::Digit => '0',
        Regexp::Expression::CharacterType::NonDigit => 'a',
        Regexp::Expression::CharacterType::Hex => '0',
        Regexp::Expression::CharacterType::NonHex => 'g',
        Regexp::Expression::CharacterType::Word => 'a',
        Regexp::Expression::CharacterType::NonWord => ' ',
        Regexp::Expression::CharacterType::Space => ' ',
        Regexp::Expression::CharacterType::NonSpace => 'a',
        Regexp::Expression::CharacterType::Linebreak => "\n",
        Regexp::Expression::CharacterType::Any => 'a',
        Regexp::Expression::CharacterType::ExtendedGrapheme => 'a'
      }.freeze
    else
      {}.freeze
    end

    def self.sample_for(regexp)
      return nil unless AVAILABLE

      cached = CACHE[regexp]
      return (cached.equal?(NONE) ? nil : cached) if cached

      # Cache miss → compute. The recursion guard only wraps compute: the
      # cache lookup above is always safe and re-entry-friendly (a recursive
      # call for an already-computed pattern still gets its cached value).
      return nil if Thread.current[COMPUTING_KEY]
      Thread.current[COMPUTING_KEY] = true
      begin
        computed = compute(regexp) || NONE
        CACHE[regexp] = computed
        computed.equal?(NONE) ? nil : computed
      ensure
        Thread.current[COMPUTING_KEY] = false
      end
    end

    def self.compute(regexp)
      ast = Regexp::Parser.parse(regexp)
      sample = gen_sample(ast)

      # libFuzzer considers strings <= 1 as "not interesting"
      return nil if sample.nil? || sample.length <= 1

      regexp.match?(sample) ? sample.freeze : nil
    rescue StandardError, ScriptError
      # A walker bug or unsupported pattern must not crash a long-running
      # fuzzer. Silently degrade.
      nil
    end

    def self.gen_sample(node)
      return nil if node.nil?
      base = gen_base(node)
      return nil if base.nil?
      apply_quantifier(node.quantifier, base)
    end

    def self.gen_base(node)
      case node
      when Regexp::Expression::Alternation
        first = node.alternatives.first
        first && gen_sample(first)
      when Regexp::Expression::CharacterSet
        gen_charset(node)
      when Regexp::Expression::CharacterSet::Range
        gen_sample(node.expressions.first)
      when Regexp::Expression::CharacterType::Base
        CHAR_TYPE_REPRESENTATIVES[node.class]
      when Regexp::Expression::PosixClass
        pick_for_posix_class(node)
      when Regexp::Expression::UnicodeProperty::Base
        pick_for_unicode_property(node)
      when Regexp::Expression::EscapeSequence::Base
        node.char
      when Regexp::Expression::Literal
        node.text
      when Regexp::Expression::Anchor::Base
        ''
      when Regexp::Expression::Assertion::Base
        # Skip lookaround bodies; validation via `match?` will drop samples
        # that contradict the assertion.
        ''
      when Regexp::Expression::Backreference::Base,
           Regexp::Expression::Conditional::Expression
        nil
      when Regexp::Expression::Group::Base
        gen_sequence(node.expressions)
      else
        # Root, Alternative, anything else that's a Subexpression with
        # children: treat as a sequence.
        node.respond_to?(:expressions) ? gen_sequence(node.expressions) : nil
      end
    end

    def self.gen_sequence(children)
      parts = []
      children.each do |child|
        piece = gen_sample(child)
        return nil if piece.nil?
        parts << piece
      end
      parts.join
    end

    def self.gen_charset(node)
      # Negative character sets: skip. Picking a "negative" code point safely
      # against arbitrary Unicode classes is a tarpit, and the reg->exact
      # path already covers patterns with a forced literal.
      return nil if node.negative
      node.expressions.each do |member|
        result = gen_sample(member)
        return result if result && !result.empty?
      end
      nil
    end

    def self.pick_for_posix_class(node)
      # PosixClass is the [:digit:] form. `node.text` is like "[:digit:]" or
      # "[:^digit:]". Identify by the bracketed name.
      text = node.text.to_s
      return nil if text.include?(':^')
      case text
      when /:digit:|:xdigit:/ then '0'
      when /:alpha:|:alnum:|:word:|:upper:|:lower:|:ascii:|:print:|:graph:/ then 'a'
      when /:space:|:blank:/ then ' '
      when /:punct:/ then '.'
      when /:cntrl:/ then "\t"
      end
    end

    def self.pick_for_unicode_property(node)
      # \p{Foo} is positive, \P{Foo} is negative. Negative skipped.
      return nil if node.token.to_s.start_with?('non')
      # Pick a generous default. The exact class member doesn't matter as
      # long as `match?` accepts it.
      case node.token
      when :digit, :decimal_digit, :number then '0'
      when :space, :whitespace, :blank then ' '
      when :punct, :punctuation then '.'
      else
        'a'
      end
    end

    def self.apply_quantifier(quantifier, sample)
      return sample if quantifier.nil?
      max = quantifier.max
      # `{0}` and `{0,0}`: drop the content entirely.
      return '' if max == 0
      min = quantifier.min
      # For optional/star quantifiers (min == 0), still produce one instance
      # so the synthesized sample carries useful bytes.
      n = min < 1 ? 1 : min
      sample * n
    end
  end
end
