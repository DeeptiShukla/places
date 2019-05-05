class Point
  attr_accessor :longitude, :latitude

  def to_hash
    {type: "Point", coordinates:[@longitude, @latitude]}
  end

  def initialize(params)
    if (params[:type].present?)
      @longitude = params[:coordinates][0]
      @latitude = params[:coordinates][1]
    else
      @latitude = params[:lat]
      @longitude = params[:lng]
    end
  end
end
