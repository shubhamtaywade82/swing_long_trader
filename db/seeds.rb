# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Seed default index instruments: NIFTY, BANKNIFTY, SENSEX
# Dhan index segment is IDX_I; common security_ids:
#   NIFTY index value: 13
#   BANKNIFTY index value: 25
#   SENSEX index value: 51

# Ensure instrument import is present and recent before seeding
last_import_raw = Setting.fetch("instruments.last_imported_at")
if last_import_raw.blank?
  Rails.logger.debug "Skipping seed: no instrument import recorded. Run `bin/rails instruments:import` first."
else
  imported_at = begin
    Time.zone.parse(last_import_raw.to_s)
  rescue StandardError
    nil
  end
  if imported_at.nil?
    Rails.logger.debug { "Skipping seed: could not parse last import timestamp (#{last_import_raw.inspect})." }
  else
    max_age = InstrumentsImporter::CACHE_MAX_AGE
    age = Time.current - imported_at
    if age > max_age
      Rails.logger.debug { "Skipping seed: import is stale (age=#{age.round(1)}s > #{max_age.inspect}). Run `bin/rails instruments:reimport`." }
    else
      # Verify that key index instruments exist
      queries = [
        { label: "NIFTY",      exchange: "NSE", symbol_like: "%NIFTY%" },
        { label: "BANKNIFTY",  exchange: "NSE", symbol_like: "%BANKNIFTY%" },
        { label: "SENSEX",     exchange: "BSE", symbol_like: "%SENSEX%" },
      ]

      found = 0
      queries.each do |q|
        instrument = Instrument
                     .where(exchange: q[:exchange])
                     .where(segment: "index")
                     .where("(instrument_code = ? OR instrument_type = ?)", "INDEX", "INDEX")
                     .where("symbol_name ILIKE ?", q[:symbol_like])
                     .order(Arel.sql("LENGTH(symbol_name) ASC"))
                     .first

        if instrument
          Rails.logger.debug { "✅ Found #{q[:label]}: security_id=#{instrument.security_id}, symbol=#{instrument.symbol_name}" }
          found += 1
        else
          Rails.logger.debug { "⚠️  #{q[:label]} not found (exchange=#{q[:exchange]} segment=index symbol_name ILIKE #{q[:symbol_like]})" }
        end
      end

      Rails.logger.debug { "\n✅ Verified #{found}/#{queries.size} key index instruments are available" }
    end
  end
end
