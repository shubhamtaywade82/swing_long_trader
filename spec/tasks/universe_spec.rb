# frozen_string_literal: true

require "rails_helper"
require "rake"
require "csv"

RSpec.describe "universe rake tasks", type: :task do
  let(:csv_dir) { Rails.root.join("tmp/universe/csv") }
  # Sample CSV content matching NSE index constituent format
  let(:nifty50_csv_content) do
    <<~CSV
      Company Name,Industry,Symbol,Series,ISIN Code
      Reliance Industries Ltd.,Oil & Gas,RELIANCE,EQ,INE467B01029
      Tata Consultancy Services Ltd.,Information Technology,TCS,EQ,INE467B01030
      HDFC Bank Ltd.,Financial Services,HDFCBANK,EQ,INE040A01034
      Infosys Ltd.,Information Technology,INFY,EQ,INE009A01021
      ICICI Bank Ltd.,Financial Services,ICICIBANK,EQ,INE090A01021
    CSV
  end

  before do
    Rake::Task.clear
    Rails.application.load_tasks
    csv_dir.mkpath
    IndexConstituent.delete_all
    # Clear any existing CSV files in test
    Dir[csv_dir.join("*.csv")].each { |f| File.delete(f) }
    # Stub all HTTP requests to prevent downloads - we only test CSV processing
    stub_request(:get, %r{niftyindices\.com/IndexConstituent/.*\.csv})
      .to_return(status: 200, body: "Company Name,Industry,Symbol,Series,ISIN Code\n", headers: { "Content-Type" => "text/csv" })
  end

  after do
    Rake::Task.clear
    # Clean up test CSV files but keep directory
    Dir[csv_dir.join("*.csv")].each { |f| File.delete(f) }
    IndexConstituent.delete_all
  end

  # Helper to re-enable tasks after invocation
  def invoke_task(task_name)
    Rake::Task[task_name].reenable
    Rake::Task[task_name].invoke
  end

  describe "universe:build" do
    context "when processing CSV files" do
      it "reads CSV files and inserts records into database" do
        File.write(csv_dir.join("nifty50.csv"), nifty50_csv_content)

        expect do
          invoke_task("universe:build")
        end.to change(IndexConstituent, :count).by(5)
      end

      it "extracts all required fields correctly from CSV" do
        File.write(csv_dir.join("nifty50.csv"), nifty50_csv_content)
        invoke_task("universe:build")

        constituent = IndexConstituent.find_by(symbol: "RELIANCE")
        expect(constituent).to be_present
        expect(constituent.company_name).to eq("Reliance Industries Ltd.")
        expect(constituent.industry).to eq("Oil & Gas")
        expect(constituent.symbol).to eq("RELIANCE")
        expect(constituent.series).to eq("EQ")
        expect(constituent.isin_code).to eq("INE467B01029")
        expect(constituent.index_name).to eq("NIFTY50")
      end

      it "cleans symbols correctly by removing known suffixes like -EQ" do
        csv_with_suffix = <<~CSV
          Company Name,Industry,Symbol,Series,ISIN Code
          Test Company Ltd.,Technology,TEST-EQ,EQ,INE123456789
        CSV
        File.write(csv_dir.join("nifty50.csv"), csv_with_suffix)

        invoke_task("universe:build")

        constituent = IndexConstituent.find_by(symbol: "TEST")
        expect(constituent).to be_present
        expect(constituent.symbol).to eq("TEST")
        expect(constituent.index_name).to eq("NIFTY50")
      end

      it "preserves hyphens in symbol names like BAJAJ-AUTO" do
        csv_with_hyphen = <<~CSV
          Company Name,Industry,Symbol,Series,ISIN Code
          Bajaj Auto Ltd.,Automobile,BAJAJ-AUTO,EQ,INE917I01010
        CSV
        File.write(csv_dir.join("nifty50.csv"), csv_with_hyphen)

        invoke_task("universe:build")

        constituent = IndexConstituent.find_by(symbol: "BAJAJ-AUTO")
        expect(constituent).to be_present
        expect(constituent.symbol).to eq("BAJAJ-AUTO")
        expect(constituent.company_name).to eq("Bajaj Auto Ltd.")
      end

      it "handles missing ISIN codes gracefully" do
        csv_without_isin = <<~CSV
          Company Name,Industry,Symbol,Series,ISIN Code
          Test Company Ltd.,Technology,TEST,EQ,
        CSV
        File.write(csv_dir.join("nifty50.csv"), csv_without_isin)

        expect do
          invoke_task("universe:build")
        end.to change(IndexConstituent, :count).by(1)

        constituent = IndexConstituent.find_by(symbol: "TEST")
        expect(constituent.isin_code).to be_nil
        expect(constituent.company_name).to eq("Test Company Ltd.")
      end

      it "deduplicates symbols across multiple indices" do
        # Create two CSV files with overlapping symbols (same symbol in different indices)
        File.write(csv_dir.join("nifty50.csv"), nifty50_csv_content)
        File.write(csv_dir.join("nifty100.csv"), nifty50_csv_content)

        invoke_task("universe:build")

        # Should have only 5 unique records (deduplicated by symbol)
        expect(IndexConstituent.count).to eq(5)
        # Each symbol should appear only once
        expect(IndexConstituent.where(symbol: "RELIANCE").count).to eq(1)
        expect(IndexConstituent.where(symbol: "TCS").count).to eq(1)
        expect(IndexConstituent.where(symbol: "HDFCBANK").count).to eq(1)
      end

      it "sets index_name from CSV filename" do
        File.write(csv_dir.join("nifty_bank.csv"), nifty50_csv_content)

        invoke_task("universe:build")

        constituents = IndexConstituent.all
        expect(constituents.count).to eq(5)
        expect(constituents.all? { |c| c.index_name == "NIFTY_BANK" }).to be true
      end

      it "processes multiple CSV files and deduplicates correctly" do
        File.write(csv_dir.join("nifty50.csv"), nifty50_csv_content)
        File.write(csv_dir.join("nifty_bank.csv"), nifty50_csv_content)

        invoke_task("universe:build")

        # Should have only 5 unique records (deduplicated by symbol)
        expect(IndexConstituent.count).to eq(5)
        # All symbols should be unique
        expect(IndexConstituent.distinct.count(:symbol)).to eq(5)
      end
    end

    context "when CSV has invalid format" do
      it "handles parsing errors gracefully" do
        invalid_csv = "invalid,data\nrow1,row2"
        File.write(csv_dir.join("nifty50.csv"), invalid_csv)

        expect do
          invoke_task("universe:build")
        end.not_to raise_error
      end
    end

    context "when required fields are missing" do
      it "skips rows without symbols" do
        csv_missing_symbol = <<~CSV
          Company Name,Industry,Symbol,Series,ISIN Code
          Test Company Ltd.,Technology,,EQ,INE123456789
        CSV
        File.write(csv_dir.join("nifty50.csv"), csv_missing_symbol)

        expect do
          invoke_task("universe:build")
        end.not_to change(IndexConstituent, :count)
      end

      it "skips rows without company names" do
        csv_missing_company = <<~CSV
          Company Name,Industry,Symbol,Series,ISIN Code
          ,Technology,TEST,EQ,INE123456789
        CSV
        File.write(csv_dir.join("nifty50.csv"), csv_missing_company)

        expect do
          invoke_task("universe:build")
        end.not_to change(IndexConstituent, :count)
      end
    end

    context "when no CSV files are available" do
      it "exits with error message" do
        # Ensure no CSV files exist
        Dir[csv_dir.join("*.csv")].each { |f| File.delete(f) }

        expect do
          invoke_task("universe:build")
        end.to raise_error(SystemExit)
      end
    end
  end

  describe "universe:stats" do
    context "when index constituents exist" do
      before do
        IndexConstituent.create!(
          company_name: "Test Company",
          symbol: "TEST",
          isin_code: "INE123456789",
          index_name: "NIFTY50",
        )
        IndexConstituent.create!(
          company_name: "Another Company",
          symbol: "ANOTHER",
          isin_code: nil,
          index_name: "NIFTY50",
        )
      end

      it "displays statistics without errors" do
        expect do
          invoke_task("universe:stats")
        end.not_to raise_error
      end

      it "shows correct counts" do
        expect do
          invoke_task("universe:stats")
        end.to output(/Total records: 2.*Unique symbols: 2.*Records with ISIN: 1.*Records without ISIN: 1/m).to_stdout
      end
    end

    context "when no index constituents exist" do
      it "handles empty database gracefully" do
        expect do
          invoke_task("universe:stats")
        end.not_to raise_error
      end
    end
  end

  describe "universe:validate" do
    context "when instruments match universe" do
      before do
        # Create universe constituents
        IndexConstituent.create!(
          company_name: "Reliance Industries",
          symbol: "RELIANCE",
          isin_code: "INE467B01029",
          index_name: "NIFTY50",
        )

        # Create matching instruments
        Instrument.create!(
          exchange: "NSE",
          segment: "E",
          security_id: "12345",
          symbol_name: "RELIANCE",
          isin: "INE467B01029",
        )
      end

      it "validates successfully" do
        expect do
          invoke_task("universe:validate")
        end.not_to raise_error
      end

      it "shows matched instruments" do
        expect do
          invoke_task("universe:validate")
        end.to output(/Matched by symbol: 1.*Matched by ISIN: 1/m).to_stdout
      end
    end

    context "when instruments don't match universe" do
      before do
        IndexConstituent.create!(
          company_name: "Test Company",
          symbol: "TEST",
          isin_code: "INE123456789",
          index_name: "NIFTY50",
        )

        Instrument.create!(
          exchange: "NSE",
          segment: "E",
          security_id: "99999",
          symbol_name: "OTHER",
          isin: "INE999999999",
        )
      end

      it "shows missing instruments" do
        expect do
          invoke_task("universe:validate")
        end.to output(/Missing from DB/).to_stdout
      end
    end

    context "when no instruments exist" do
      before do
        IndexConstituent.create!(
          company_name: "Test Company",
          symbol: "TEST",
          isin_code: "INE123456789",
          index_name: "NIFTY50",
        )
      end

      it "shows all universe symbols as missing" do
        expect do
          invoke_task("universe:validate")
        end.to output(/Missing from DB/).to_stdout
      end
    end

    context "when no universe exists" do
      it "handles empty universe gracefully" do
        expect do
          invoke_task("universe:validate")
        end.not_to raise_error
      end
    end
  end
end
