class Place
  include ActiveModel::Model
  attr_accessor :id, :formatted_address, :location, :address_components
  # convenience method for access to client in console
  def self.mongo_client
    Mongoid::Clients.default
  end

  def persisted?
    !@id.nil?
  end

  # convenience method for access to zips collection
  def self.collection
    self.mongo_client['places']
  end

  def self.load_all(f)
    places=JSON.parse(f.read)
    result = collection.insert_many(places)
  end

  def initialize(params)
    @id = params[:_id].to_s
    @formatted_address = params[:formatted_address]
    @address_components = []
    if(!params[:address_components].nil?)
      params[:address_components].each do |ac|
        @address_components << AddressComponent.new(ac)
      end
    end
    @location = Point.new(params[:geometry][:geolocation]) unless params[:geometry][:geolocation].nil?
  end

  def self.find_by_short_name(input)
    self.collection.find("address_components.short_name" => input)
  end

  def self.to_places(input_view)
    results = []
    input_view.each do |v|
      results << Place.new(v)
    end
    results
  end

  def self.find(id)
    temp_id = BSON::ObjectId.from_string(id.to_s)
    result = self.collection.find(:_id=>temp_id).first
    Place.new(result) if !result.nil?
  end

  def self.all(offset=0, limit=nil)
    result = []
    if(!limit.nil?)
      temp = self.collection.find().skip(offset).limit(limit)
    else
      temp = self.collection.find().skip(offset)
    end
    temp.each do |t|
      result << Place.new(t)
    end
    result
  end

  def destroy
    self.class.collection.find(_id: BSON::ObjectId.from_string(@id)).delete_one
  end

  #r.pipeline << {:$sort=>sort} if sort
  def self.get_address_components(sort={:_id=>1},offset=0,limit=nil)
    pipeline=[{:$project=>{:_id=>1, :address_components=>1, :formatted_address=>1, "geometry.geolocation"=>1}},
              {:$unwind =>'$address_components'}]
    pipeline << {:$sort=>sort} if sort
    pipeline << {:$skip=>offset}  if offset && offset > 0
    pipeline <<  {:$limit=>limit} if limit && limit > 0
    self.collection.find.aggregate(pipeline)
  end

  def self.get_country_names
    pipeline = [{:$project=>{:"address_components.long_name"=>1, :"address_components.types"=>1}},
                {:$unwind =>'$address_components'}]
    pipeline << {:$match=>{'address_components.types'=>"country"}}
    pipeline << {:$group=>{:_id =>'$address_components.long_name'}}
    result = self.collection.find.aggregate(pipeline)
    result.to_a.map {|h| h[:_id]}
  end

  def self.find_ids_by_country_code(country_code)
    result = self.collection.find.aggregate([{:$match=>{'address_components.types'=>"country",
                                                        'address_components.short_name'=> country_code}},
                                             {:$project=>{:_id=>1}}]).map {|doc| doc[:_id].to_s}
  end

  def self.create_indexes
    self.collection.indexes.create_one({"geometry.geolocation"=>Mongo::Index::GEO2DSPHERE})
  end

  def self.remove_indexes
    self.collection.indexes.drop_one("geometry.geolocation_2dsphere")
  end

  def self.near(point, max_meters = nil)
    self.collection.find(
        :"geometry.geolocation"=>{:$near=>{
          :$geometry=>point.to_hash,
          :$minDistance=>0,
          :$maxDistance=>max_meters}}
        )
  end

  def near(max_meters = nil)
    self.class.to_places(self.class.near(@location, max_meters))
  end

  def photos(offset=0, limit=nil)
    result = []
    vdoc=Photo.mongo_client.database.fs.find(:"metadata.place"=>BSON::ObjectId.from_string(@id)).skip(offset)
    vdoc = vdoc.limit(limit) if limit
    vdoc.each { |p| result << Photo.new(p) }
    result
  end
end
