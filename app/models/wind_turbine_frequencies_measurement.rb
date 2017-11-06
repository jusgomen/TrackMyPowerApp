class WindTurbineFrequenciesMeasurement < ApplicationRecord
	before_save :default_values
	protected
	def default_values
		self.mag ||= 0
		self.mag_y ||= 0
		self.mag_z ||= 0
		self.freq ||= 0
	end 
end