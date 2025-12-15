# frozen_string_literal: true

module QueryBuilder
  extend ActiveSupport::Concern

  private

  # Builds a paginated query with common includes and ordering
  # @param [ActiveRecord::Relation] scope Base scope
  # @param [Hash] options Query options
  # @option options [Symbol, Array<Symbol>] :includes Associations to eager load
  # @option options [String, Symbol] :order_column Column to order by
  # @option options [Symbol] :order_direction Order direction (:asc or :desc)
  # @option options [Integer] :limit Maximum number of records
  # @return [ActiveRecord::Relation] Built query
  def build_paginated_query(scope, options = {})
    includes = options[:includes] || []
    order_column = options[:order_column] || :created_at
    order_direction = options[:order_direction] || :desc
    limit = options[:limit] || 100

    query = scope
    query = query.includes(includes) if includes.any?
    query = query.order(order_column => order_direction)
    query = query.limit(limit) if limit
    query
  end
end
