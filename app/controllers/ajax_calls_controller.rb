class AjaxCallsController < ApplicationController
  require 'date'
  include ActionView::Helpers::DateHelper
  before_action :authenticate
  layout 'blank'

  def load_electrical
    variable = params[:variable]
    units = params[:units]
    @result = ElectricalMeasurement.last[variable] if !ElectricalMeasurement.last.nil?
    if variable.downcase == "energy_med1"
      query = "extract(month from created_at) = ? and extract(year from created_at) = ? and energy_med1 != 0"
      max_current_month = ElectricalMeasurement.where(query, Time.now.month, Time.now.year ).maximum(variable).to_f
      min_current_month = ElectricalMeasurement.where(query, Time.now.month, Time.now.year ).minimum(variable).to_f
      @result = max_current_month - min_current_month
    end
    if variable.downcase == "total_delivered_energy"
      @result = ElectricalMeasurement.maximum("energy_med1")
      timestamp = "Since August 2016"
    end
    @result = "#{@result} #{units(variable)}" if units == "true"
    if variable.downcase == "timestamp"
      @result = "#{time_ago_in_words(ElectricalMeasurement.last.created_at)} ago"
    end
    if @result.blank? || @result.nil?
      @result = 'N/A'
    end
    render json: { result: @result, variable: variable, timestamp: timestamp }, layout: true
  end

  def load_internal
    variable = params[:variable]
    units = params[:units]
    variable = "created_at" if variable.downcase == "last_update"
    @result = InternalConditionsMeasurement.last[variable] if !InternalConditionsMeasurement.last.nil?
    @result = "#{@result.to_i}#{units(variable)}" if units == "true"
    @result = 'N/A' if @result.blank?
    case variable
    when "temperature_int"
      variable = "internal_temperature"
      timestamp = "Control Room"
    when "humidity_int"
      variable = "internal_humidity"
      timestamp = "Control Room"
    when "created_at"
      @result = ElectricalMeasurement.last[variable] if !ElectricalMeasurement.last.nil?
      timestamp = @result.strftime("%F")
      @result = @result.strftime("%T")
      variable = "last_update"
    end
    render json: { result: @result, variable: variable, timestamp: timestamp }, layout: true
  end

  def load_metereological
    variable = params[:variable]
    units = params[:units]
    @result = MeteorologicalMeasurement.last[variable] if !MeteorologicalMeasurement.last.nil?
    timestamp = "#{time_ago_in_words(MeteorologicalMeasurement.last.created_at)} ago" if !MeteorologicalMeasurement.last.nil?
    @result =  "<h3>#{@result.to_i}</h3>" if variable != "temperature"
    if variable.downcase == "timestamp"
      @result = "#{time_ago_in_words(MeteorologicalMeasurement.last.created_at)} ago"
    end
    if @result.blank?
      @result = 'N/A'
    end
    render json: { result: @result, variable: variable, timestamp: timestamp}, layout: true
  end

  def load_stream
    url = Stream.last["url"] if !Stream.last.nil?
    timestamp = "#{time_ago_in_words(Stream.last.created_at)} ago" if !Stream.last.nil?
    render json: { url: url, timestamp: timestamp }
  end

  def voltage_chart
    @result = ElectricalMeasurement.where('created_at >= ?', 1.day.ago.change(hour: 0, min: 0, sec: 0)).order(:created_at).select(:voltage_med1, :created_at)
    timestamp =  @result.pluck(:created_at)
    timestamp.collect! { |element| element.strftime("%F %T") }
    y_data = @result.pluck(:voltage_med1)
    render json: { timestamp: timestamp, y_data: y_data }, layout: true
  end

  def energy_chart
    variable = params[:variable]
    monthly_energy = {}
    query = "extract(month from created_at) = ? and extract(year from created_at) = ? and energy_med1 != 0"
    (1..12).to_a.each do |month|
       min_month = ElectricalMeasurement.where(query, month, Time.now.year ).minimum(variable).to_f
       max_month = ElectricalMeasurement.where(query, month, Time.now.year ).maximum(variable).to_f
       monthly_energy[Date::MONTHNAMES[month]] = max_month - min_month
    end
    render json: { months: monthly_energy.keys, y_data: monthly_energy.values }
  end

  def wind_chart
    output_hash = {}
    cardinals = ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest", "North"]
    2.downto(0).to_a.each do |n_day|
    	start=n_day.day.ago.change(hour: 0, min: 0, sec: 0)
    	stop=n_day.day.ago.change(hour: 23, min: 59, sec: 59)
      max_speed = {}
      (0..8).to_a.each do |norm_direction|
        result = MeteorologicalMeasurement.where("created_at >= ? and created_at <= ? and
            round(wind_direction/45) = #{norm_direction}", start, stop).maximum(:wind_speed)
        if norm_direction == 8
          result = [result.to_f, max_speed[:North]].max
        end
        max_speed[cardinals[norm_direction].to_sym] = result.to_f
      end
      output_hash[n_day] = { result: max_speed, date: start.strftime("%m-%d") }
    end
    cardinals.pop
    output_hash[:labels] = cardinals
    render json: output_hash
  end

  def hsp_chart
    hsps = []
    days = []
    6.downto(0).to_a.each do |n_day|
      start = n_day.day.ago.change(hour: 0, min: 0, sec: 0)
      stop = n_day.day.ago.change(hour: 23, min: 59, sec: 59)
      day_name = start.strftime("%A")
      query = MeteorologicalMeasurement.where("created_at >= ? and created_at <= ?", start, stop).order(:created_at)
      calc = 0.0
      query.select(:solar_radiation).each_with_index do |entry, index|
        if index == 0 || index == query.count-1
          calc = calc + entry.solar_radiation/24.0
        else
          calc = calc + entry.solar_radiation/12.0
        end
      end
      hsps.push(((calc/10.0).round)/100.0)
      days.push(day_name)
    end
    days.pop and days.push("Today")
    render json: { values: hsps, labels: days }
  end

  def refresh_checkboxes_tables
    group = params[:variable]
    group_class = group.classify.constantize
    if group.include? "measurement"
      @column_names = group_class.column_names - ["id", "created_at"]
    end
    debugger
    render "refresh_checkboxes_tables.js", layout: false
  end

  private
    def authenticate
      authenticate_or_request_with_http_basic('Administration') do |username, password|
        username == 'admin' && password == 'uninorte'
      end
    end
end
