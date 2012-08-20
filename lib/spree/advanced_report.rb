module Spree
  class AdvancedReport
    include Ruport
    attr_accessor :orders, :product_text, :date_text, :taxon_text, :ruportdata, :data, :params, :taxon, :product, :product_in_taxon, :unfiltered_params

    def name
      I18n.t("adv_report.base.name")
    end

    def description
      I18n.t("adv_report.base.description")
    end

    def initialize(params)
      self.params = params
      self.data = {}
      self.ruportdata = {}
      self.unfiltered_params = params[:search].blank? ? {} : params[:search].clone

      params[:search] ||= {}

      if Order.count > 0
        begin
          params[:search][:created_at_gt] = Time.zone.parse(params[:search][:created_at_gt]).beginning_of_day
        rescue 
          params[:search][:created_at_gt] = Date.today.beginning_of_day
        end

        # TODO if lt is defined, and gt is not, gt then should use better default than end of today
        # maybe 24 hours before the defined lt end of day
        
        begin
          params[:search][:created_at_lt] = Time.zone.parse(params[:search][:created_at_lt]).end_of_day
        rescue
          params[:search][:created_at_lt] = Date.today.end_of_day
        end
      end

      params[:search][:completed_at_not_null] = true
      params[:search][:state_not_eq] = 'canceled'

      search = Order.search(params[:search])

      # angelim/i18n-1-0
      params[:search][:state_equals] ||= "complete"

      # choosing not to do any state filtering here, this is left to the report writer
      # self.orders = search.state_does_not_equal('canceled')

      self.orders = search.result

      self.product_in_taxon = true
      if params[:advanced_reporting]
        if params[:advanced_reporting][:taxon_id] && params[:advanced_reporting][:taxon_id] != ''
          self.taxon = Taxon.find(params[:advanced_reporting][:taxon_id])
        end
        if params[:advanced_reporting][:product_id] && params[:advanced_reporting][:product_id] != ''
          self.product = Product.find(params[:advanced_reporting][:product_id])
        end
      end
      if self.taxon && self.product && !self.product.taxons.include?(self.taxon)
        self.product_in_taxon = false
      end

      if self.product
        self.product_text = "Product: #{self.product.name}<br />"
      end
      if self.taxon
        self.taxon_text = "Taxon: #{self.taxon.name}<br />"
      end

      # Above searchlogic date settings
      self.date_text = "#{I18n.t("adv_report.base.range")}:"
      if self.unfiltered_params
        if self.unfiltered_params[:created_at_gt] != '' && self.unfiltered_params[:created_at_lt] != ''
          self.date_text += " From #{self.unfiltered_params[:created_at_gt]} to #{self.unfiltered_params[:created_at_lt]}"
        elsif self.unfiltered_params[:created_at_gt] != ''
          self.date_text += " After #{self.unfiltered_params[:created_at_gt]}"
        elsif self.unfiltered_params[:created_at_lt] != ''
          self.date_text += " Before #{self.unfiltered_params[:created_at_lt]}"
        # if self.unfiltered_params[:created_at_greater_than] != '' && self.unfiltered_params[:created_at_less_than] != ''
        #   self.date_text += " #{I18n.t("adv_report.base.from")} #{self.unfiltered_params[:created_at_greater_than]} to #{self.unfiltered_params[:created_at_less_than]}"
        # elsif self.unfiltered_params[:created_at_greater_than] != ''
        #   self.date_text += " #{I18n.t("adv_report.base.after")} #{self.unfiltered_params[:created_at_greater_than]}"
        # elsif self.unfiltered_params[:created_at_less_than] != ''
        #   self.date_text += " #{I18n.t("adv_report.base.before")} #{self.unfiltered_params[:created_at_less_than]}"
        else
          self.date_text += " #{I18n.t("adv_report.base.all")}"
        end
      else
        self.date_text += " #{I18n.t("adv_report.base.all")}"
      end
    end

    def download_url(base, format, report_type = nil)
      elements = []
      params[:advanced_reporting] ||= {}
      params[:advanced_reporting]["report_type"] = report_type if report_type
      if params
        [:search, :advanced_reporting].each do |type|
          if params[type]
            params[type].each { |k, v| elements << "#{type}[#{k}]=#{v}" }
          end
        end
      end
      base.gsub!(/^\/\//,'/')
      base + '.' + format + '?' + elements.join('&')
    end

    def revenue(order)
      rev = order.item_total
      if !self.product.nil? && product_in_taxon
        rev = order.line_items.select { |li| li.product == self.product }.inject(0) { |a, b| a += b.quantity * b.price }
      elsif !self.taxon.nil?
        rev = order.line_items.select { |li| li.product && li.product.taxons.include?(self.taxon) }.inject(0) { |a, b| a += b.quantity * b.price }
      end
      adjustment_revenue = order.adjustments.sum(:amount)
      rev += adjustment_revenue if rev > 0
      self.product_in_taxon ? rev : 0
    end

    def profit(order)
      profit = order.line_items.inject(0) { |profit, li| profit + (li.variant.price - li.variant.cost_price.to_f)*li.quantity }
      if !self.product.nil? && product_in_taxon
        profit = order.line_items.select { |li| li.product == self.product }.inject(0) { |profit, li| profit + (li.variant.price - li.variant.cost_price.to_f)*li.quantity }
      elsif !self.taxon.nil?
        profit = order.line_items.select { |li| li.product && li.product.taxons.include?(self.taxon) }.inject(0) { |profit, li| profit + (li.variant.price - li.variant.cost_price.to_f)*li.quantity }
      end
      profit += order.adjustments.sum(:amount)
      self.product_in_taxon ? profit : 0
    end

    def units(order)
      units = order.line_items.sum(:quantity)
      if !self.product.nil? && product_in_taxon
        units = order.line_items.select { |li| li.product == self.product }.inject(0) { |a, b| a += b.quantity }
      elsif !self.taxon.nil?
        units = order.line_items.select { |li| li.product && li.product.taxons.include?(self.taxon) }.inject(0) { |a, b| a += b.quantity }
      end
      self.product_in_taxon ? units : 0
    end

    def order_count(order)
      self.product_in_taxon ? 1 : 0
    end

    def date_range
      if self.params[:search][:created_at_gt].to_date == self.params[:search][:created_at_lt].to_date
        self.params[:search][:created_at_gt].to_date.to_s
      else
        "#{self.params[:search][:created_at_gt].to_date} &ndash; #{self.params[:search][:created_at_lt].to_date}"
      end
    end
  end
end
