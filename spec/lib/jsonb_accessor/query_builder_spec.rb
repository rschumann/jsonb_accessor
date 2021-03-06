# frozen_string_literal: true
require "spec_helper"

RSpec.describe JsonbAccessor::QueryBuilder do
  describe ".jsonb_contains" do
    let(:title) { "title" }
    let!(:matching_record) { Product.create!(title: title) }
    let!(:other_matching_record) { Product.create!(title: title) }
    let!(:ignored_record) { Product.create!(title: "ignored") }
    subject { Product.all }

    it "is a collection of records that match the query" do
      query = subject.jsonb_contains(:options, title: title)
      expect(query).to exist
      expect(query).to match_array([matching_record, other_matching_record])
    end

    it "escapes sql" do
      expect do
        subject.jsonb_contains(:options, title: "foo\"};delete from products where id = #{matching_record.id}").to_a
      end.to_not raise_error
      expect(subject.count).to eq(3)
    end

    context "table names" do
      let!(:product_category) { ProductCategory.create!(title: "category") }

      before do
        product_category.products << matching_record
        product_category.products << other_matching_record
      end

      it "is not ambigious which table is being referenced" do
        expect do
          subject.joins(:product_category).merge(ProductCategory.jsonb_contains(:options, title: "category")).to_a
        end.to_not raise_error
      end
    end
  end

  describe "#jsonb_number_where" do
    let!(:high_rank_record) { Product.create!(rank: 5) }
    let!(:middle_rank_record) { Product.create!(rank: 4) }
    let!(:low_rank_record) { Product.create!(rank: 0) }
    subject { Product.all }

    context "greater than" do
      it "is matching records" do
        [:>, :greater_than, :gt, ">", "greater_than", "gt"].each do |operator|
          query = subject.jsonb_number_where(:options, :rank, operator, middle_rank_record.rank)
          expect(query).to exist
          expect(query).to eq([high_rank_record])
        end
      end
    end

    context "less than" do
      it "is matching records" do
        [:<, :less_than, :lt, "<", "less_than", "lt"].each do |operator|
          query = subject.jsonb_number_where(:options, :rank, operator, middle_rank_record.rank)
          expect(query).to exist
          expect(query).to eq([low_rank_record])
        end
      end
    end

    context "less than or equal to" do
      it "is matching records" do
        [:<=, :less_than_or_equal_to, :lte, "<=", "less_than_or_equal_to", "lte"].each do |operator|
          query = subject.jsonb_number_where(:options, :rank, operator, middle_rank_record.rank)
          expect(query).to exist
          expect(query).to match_array([low_rank_record, middle_rank_record])
        end
      end
    end

    context "greater than or equal to" do
      it "is matching records" do
        [:>=, :greater_than_or_equal_to, :gte, ">=", "greater_than_or_equal_to", "gte"].each do |operator|
          query = subject.jsonb_number_where(:options, :rank, operator, middle_rank_record.rank)
          expect(query).to exist
          expect(query).to match_array([high_rank_record, middle_rank_record])
        end
      end
    end
  end

  describe "#jsonb_time_where" do
    let!(:early_record) { Product.create!(made_at: 10.days.ago) }
    let!(:late_record) { Product.create!(made_at: 2.days.from_now) }
    subject { Product.all }

    context "before" do
      it "is matching records" do
        [:before, "before"].each do |operator|
          query = subject.jsonb_time_where(:options, :made_at, operator, Time.current)
          expect(query).to exist
          expect(query).to eq([early_record])
        end
      end
    end

    context "after" do
      it "is matching records" do
        [:after, "after"].each do |operator|
          query = subject.jsonb_time_where(:options, :made_at, operator, Time.current)
          expect(query).to exist
          expect(query).to eq([late_record])
        end
      end
    end
  end

  describe "#jsonb_where" do
    let(:title) { "title" }
    let!(:matching_record) { Product.create!(title: title, rank: 4, made_at: Time.current) }
    let!(:ignored_record) { Product.create!(title: "ignored", rank: 3, made_at: 3.years.ago) }
    let!(:blank_record) { Product.create! }
    subject { Product.all }

    context "contains" do
      it "is matching records" do
        query = subject.jsonb_where(:options, title: title)
        expect(query).to exist
        expect(query).to eq([matching_record])
      end
    end

    context "number queries" do
      it "is records matching the criteria" do
        query = subject.jsonb_where(:options, rank: { greater_than: 3, less_than: 7 })
        expect(query).to exist
        expect(query).to eq([matching_record])
      end
    end

    context "time queries" do
      it "is records matching the criteria" do
        query = subject.jsonb_where(:options, made_at: { before: 2.days.from_now, after: 2.days.ago })
        expect(query).to exist
        expect(query).to eq([matching_record])
      end
    end

    context "smoke test" do
      it "is records matching the criteria" do
        query = subject.jsonb_where(
          :options,
          title: title,
          rank: { greater_than: 3, less_than: 7 },
          made_at: { before: 2.days.from_now, after: 2.days.ago }
        )
        expect(query).to exist
        expect(query).to eq([matching_record])
      end
    end
  end

  describe "->is_number_query_arguments" do
    subject { JsonbAccessor::IS_NUMBER_QUERY_ARGUMENTS }

    context "not a hash" do
      it "is false" do
        expect(subject.call(nil)).to eq(false)
        expect(subject.call("foo")).to eq(false)
      end
    end

    context "hash that is not for a number query" do
      it "is false" do
        expect(subject.call("before" => 12)).to eq(false)
        expect(subject.call("title" => "foo")).to eq(false)
      end
    end

    context "hash that is for a number query" do
      it "is true" do
        expect(subject.call(greater_than: 5, "less_than" => 10)).to eq(true)
      end
    end
  end

  describe "->is_time_query_arguments" do
    subject { JsonbAccessor::IS_TIME_QUERY_ARGUMENTS }

    context "not a hash" do
      it "is false" do
        expect(subject.call(nil)).to eq(false)
        expect(subject.call("foo")).to eq(false)
      end
    end

    context "hash that is not for a number query" do
      it "is false" do
        expect(subject.call("greater_than" => 12)).to eq(false)
        expect(subject.call("title" => "foo")).to eq(false)
      end
    end

    context "hash that is for a number query" do
      it "is true" do
        expect(subject.call(before: 10, "after" => 5)).to eq(true)
      end
    end
  end
end
