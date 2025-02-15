# frozen_string_literal: true

class SearchQueryTransformer < Parslet::Transform
  class Query
    attr_reader :should_clauses, :must_not_clauses, :must_clauses, :filter_clauses, :order_clauses

    def initialize(clauses)
      grouped = clauses.chunk(&:operator).to_h
      @should_clauses = grouped.fetch(:should, [])
      @must_not_clauses = grouped.fetch(:must_not, [])
      @must_clauses = grouped.fetch(:must, [])
      @filter_clauses = grouped.fetch(:filter, [])
      @order_clauses = grouped.fetch(:order, [])
    end

    def apply(search, account)
      should_clauses.each { |clause| search = search.query.should(clause_to_query(clause)) }
      must_clauses.each { |clause| search = search.query.must(clause_to_query(clause)) }
      must_not_clauses.each { |clause| search = search.query.must_not(clause_to_query(clause)) }
      filter_clauses.each { |clause| search = search.filter(**clause_to_filter(clause, account)) }
      if order_clauses.empty?
        # Default to most recent results first.
        search = search.order(created_at: :desc)
      else
        order_clauses.each { |clause| search = search.order(**clause_to_order(clause)) }
      end
      search.query.minimum_should_match(1)
    end

    private

    def clause_to_query(clause)
      case clause
      when TermClause
        { multi_match: { type: 'most_fields', query: clause.term, fields: ['text', 'text.stemmed'] } }
      when PhraseClause
        { match_phrase: { text: { query: clause.phrase } } }
      when PrefixClause
        { term: { clause.filter => clause.term } }
      else
        raise "Unexpected clause type: #{clause}"
      end
    end

    def clause_to_filter(clause, account)
      case clause
      when PrefixClause
        { clause.query => { clause.filter => clause.term == :account_id_placeholder ? account.id : clause.term } }
      else
        raise "Unexpected clause type: #{clause}"
      end
    end

    def clause_to_order(clause)
      case clause
      when PrefixClause
        { clause.term => clause.order }
      else
        raise "Unexpected clause type: #{clause}"
      end
    end
  end

  class Operator
    class << self
      def symbol(str)
        case str
        when '+'
          :must
        when '-'
          :must_not
        when nil
          :should
        else
          raise "Unknown operator: #{str}"
        end
      end
    end
  end

  class TermClause
    attr_reader :prefix, :operator, :term

    def initialize(prefix, operator, term)
      @prefix = prefix
      @operator = Operator.symbol(operator)
      @term = term
    end
  end

  class PhraseClause
    attr_reader :prefix, :operator, :phrase

    def initialize(prefix, operator, phrase)
      @prefix = prefix
      @operator = Operator.symbol(operator)
      @phrase = phrase
    end
  end

  class PrefixClause
    attr_reader :filter, :operator, :term, :order, :query

    def initialize(prefix, operator, term)
      @query = :term

      case operator
      when '+', nil
        @operator = :filter
      when '-'
        @operator = :must_not
      else
        raise "Unknown operator: #{str}"
      end

      case prefix
      when 'domain', 'is', 'has', 'lang', 'visibility'
        @filter = prefix.to_s
        @term = term
      when 'before', 'after'
        @query = :range
        @filter = 'created_at'
        case prefix
        when 'before'
          @term = { lt: term }
        when 'after'
          @term = { gt: term }
        else
          raise Mastodon::SyntaxError
        end
      when 'from'
        @filter = :account_id

        username, domain = term.gsub(/\A@/, '').split('@')
        domain           = nil if TagManager.instance.local_domain?(domain)
        account          = Account.find_remote!(username, domain)

        @term = account.id
      when 'scope'
        raise Mastodon::SyntaxError unless operator.nil?
        raise Mastodon::SyntaxError unless term == 'classic'
        @filter = 'searchable_by'
        @term = :account_id_placeholder
      when 'sort'
        raise Mastodon::SyntaxError unless operator.nil?

        @operator = :order
        @term = :created_at

        case term
        when 'oldest'
          @order = :asc
        when 'newest'
          @order = :desc
        else
          raise Mastodon::SyntaxError
        end
      else
        raise Mastodon::SyntaxError
      end
    end
  end

  rule(clause: subtree(:clause)) do
    prefix   = clause[:prefix][:term].to_s if clause[:prefix]
    operator = clause[:operator]&.to_s

    if clause[:prefix]
      PrefixClause.new(prefix, operator, clause[:term].to_s)
    elsif clause[:term]
      TermClause.new(prefix, operator, clause[:term].to_s)
    elsif clause[:shortcode]
      TermClause.new(prefix, operator, ":#{clause[:term]}:")
    elsif clause[:phrase]
      PhraseClause.new(prefix, operator, clause[:phrase].is_a?(Array) ? clause[:phrase].map { |p| p[:term].to_s }.join(' ') : clause[:phrase].to_s)
    else
      raise "Unexpected clause type: #{clause}"
    end
  end

  rule(query: sequence(:clauses)) { Query.new(clauses) }
end
