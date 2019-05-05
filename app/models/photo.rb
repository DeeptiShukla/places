require 'exifr/jpeg'

class Photo
  attr_accessor :id, :location
  attr_writer :contents

  def self.mongo_client
    Mongoid::Clients.default
  end


  def initialize(params={})
    if !params.empty?
      @id = params[:_id].to_s if params[:_id].present?
      @location = Point.new(params[:metadata][:location]) if params[:metadata][:location].present?
      @place = params[:metadata][:place] if params[:metadata][:place].present?
    else
      @id = nil
      @location = nil
    end
  end

  def persisted?
    !@id.nil?
  end

  def place
    Place.find(@place) if !@place.nil?
  end

  def place=(value)
    case
      when value.is_a?(Place)
        @place=BSON::ObjectId.from_string(value.id)
      when value.is_a?(String)
        @place=BSON::ObjectId.from_string(value)
      when value.is_a?(BSON::ObjectId)
        @place=value
    end
  end

  def save
    if !self.persisted?
      description = {}
      gps = EXIFR::JPEG.new(@contents).gps
      @location = Point.new(:lng => gps.longitude, :lat => gps.latitude)
      description[:content_type] = "image/jpeg"
      description[:metadata] = {}
      description[:metadata][:location] = @location.to_hash
      description[:metadata][:place] = @place
      if @contents
        @contents.rewind
        grid_file = Mongo::Grid::File.new(@contents.read, description)
        id = self.class.mongo_client.database.fs.insert_one(grid_file)
        @id = id.to_s
        return @id
      end
    else
      self.class.mongo_client.database.fs.find(:_id=>BSON::ObjectId(@id))
        .update_one(:$set=>{:"metadata.location"=>@location.to_hash, :"metadata.place" => @place})
    end
  end

  def self.all(skip=0, limit=nil)
    result = self.mongo_client.database.fs.find().skip(skip)
    result=result.limit(limit) if !limit.nil?
    if result.nil?
      return nil
    else
      result.map {|photo| Photo.new(photo)}
    end
  end

  def self.find(id)
    result = self.mongo_client.database.fs.find(:_id=>BSON::ObjectId.from_string(id)).first
    if result.nil?
      nil
    else
      @id = result[:_id].to_s
      @location = result[:metadata][:location]
      Photo.new(result)
    end
  end

  def contents
    stored_file = Photo.mongo_client.database.fs.find_one(:_id=>BSON::ObjectId.from_string(self.id))
    @contents = stored_file.data
  end

  def destroy
    self.class.mongo_client.database.fs.find(:_id=>BSON::ObjectId.from_string(id)).delete_one
  end

  def find_nearest_place_id(max_meters)
    Place.near(@location, max_meters).limit(1).projection(:_id=>1).map {|r| r[:_id]}[0]
  end

  def self.find_photos_for_place(id)
    temp_id = BSON::ObjectId.from_string(id.to_s)
    gridfs = Photo.mongo_client.database.fs.find("metadata.place"=>temp_id)
  end
end
