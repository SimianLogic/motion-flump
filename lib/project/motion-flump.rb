#re-implementing the retina? method from BubbleWrap so i can avoid dependencies
class RetinaHelper
  def self.retina?(screen=UIScreen.mainScreen)
    if screen.respondsToSelector('displayLinkWithTarget:selector:') && screen.scale == 2.0
      return true
    end
    false
  end
end

# NOTES
# => iOS doesn't have a great way to set something's position when the origin is not the center or
#    the top left corner, so I give everything a frame of [[0,0],[0,0]] so that setting the center
#    allows me to set the position exactly how I want. There's probably a better way to do this.
class FlumpBaseView < UIView
  attr_accessor :name
  
  #mostly for repl inspection, typing this is a pain
  def rotation
    valueForKeyPath("layer.transform.rotation.z")
  end
  
  def angle
    rotation * 180.0 / Math::PI
  end
end

#there may be a smarter way to do this in iOS, but after fiddling
# with anchor points for awhile this worked a lot better
class OffsetImageView < FlumpBaseView
  attr_accessor :offset
  attr_accessor :image
  
  def initWithImage(image, offset)
    if initWithFrame([[0,0], [0,0]])
      @image = UIImageView.alloc.initWithImage(image)
      addSubview(@image)
      @image.frame = [[-offset.x, -offset.y], [image.size.width, image.size.height]]
      @offset = offset
    end
    self
  end
  
  def actual_bounds
    CGRectApplyAffineTransform(@image.frame, self.transform)
  end
  
  def actual_frame
    CGRectOffset(actual_bounds, center.x, center.y)
  end
  
  #was expecting to have to do a lot more than this to get touches working...
  #  keep an eye on touch bugs
  def pointInside(point, withEvent:event)
    CGRectContainsPoint(actual_bounds, point)
  end
end

class FlumpView < FlumpBaseView
  #lazy -- why go through the trouble of making this dynamic until I need it?
  FRAME_RATE = 24.0
  
  attr_accessor :movie
  attr_accessor :current_frame
  
  def initWithMovie(movie)
    
    @symbols_cache = {}
    @movie = movie
    
    @frames = @movie.frames
    @duration = @frames / FRAME_RATE
        
    if initWithFrame([[0,0],[0,0]])
      goto(0)
    end
    
    self
  end

  #empirically, it seems as though the POINT in pointInside uses
  #our top left corner and NOT our (0,0) center point as expected...
  # => no problem, just subtract our offset!
  def pointInside(point, withEvent:event)
    CGRectContainsPoint(actual_bounds, point)
  end
  
  def actual_bounds
    rect = nil
    @symbols_cache.values.map(&:actual_frame).each do |r|
      if rect.nil?
        rect = r
      else
        rect = CGRectUnion(rect, r)
      end
    end
    CGRectApplyAffineTransform(rect, self.transform)
    rect
  end
  
  def actual_frame
    CGRectOffset(actual_bounds, center.x, center.y)
  end
  
  def method_missing(meth, *args)
    if sv = subviews.select{ |v| v.name == meth.to_s }.first
      return sv
    else
      super
    end
  end
  
  #delta is in seconds
  def advance_time(delta)
    return unless delta > 0
    return unless @frames > 1
    
    @play_time += delta
    
    #cache this so we can see if we looped past the stop frame
    cached_playtime = @play_time
    
    @play_time %= @duration
    
    new_frame = (@play_time * FRAME_RATE).floor
    new_frame = [[0, new_frame].max, @frames-1].min
    
    #if we hit or passed stop frame, go there and bail
    unless @stop_frame.nil?
      frames_remaining = (@current_frame <= @stop_frame ? @stop_frame - @current_frame : @frames - @current_frame + @stop_frame)
      frames_elapsed = (cached_playtime * FRAME_RATE).floor - @current_frame
      if frames_elapsed > frames_remaining
        if @start_frame.nil?
          #set new_frame first... mucking with is_playing clears stop/start frames
          new_frame = @stop_frame
          cached_handler = @stop_frame_handler
          self.is_playing = false

          unless cached_handler.nil?
            cached_handler.call
          end
          
        else
          #important to reset the play time
          goto(@start_frame) and return
        end
      end
    end
    
    goto(new_frame, false)
  end
  
  def play
    self.is_playing = true
  end
  
  def stop
    self.is_playing = false
  end
  
  #helper method just for testing in REPL
  def advance
    goto((@current_frame + 1) % @frames)
  end
  
  def goto(frame_number, overwrite_playtime=true)
    return if frame_number == @current_frame
    @current_frame = frame_number
    @play_time = frame_number / FRAME_RATE if overwrite_playtime
    
    @movie.layers.each do |layer|
      keyframe = layer.keyframe_for_frame(frame_number)
      keyframe_index = layer.keyframes.index(keyframe)
      
      #two-string keys, allows us to swap clips on one layer
      symbol_key = "#{layer.name}:#{keyframe.ref}"
      insertion_index = nil
      
      #first check to see if something else was in this layer and remove it!
      if @symbols_cache[symbol_key].nil?
        old_symbol = [*@symbols_cache.keys.select{ |key| key.split(":").first == layer.name }].first
        unless old_symbol.nil?
          insertion_index = subviews.index(old_symbol)
          old_symbol.removeFromSuperview
          old_symbol = nil   #do we care about caching these?
        end
      end
      
      #put this down here so if we remove something and don't add something back it should work
      next if keyframe.ref.nil?
      
      #if there was nothing here, isntantiate a new symbol and add it!
      if @symbols_cache[symbol_key].nil?
        new_symbol = $flump.get_view(keyframe.ref)
        new_symbol.name = layer.name
        if insertion_index.nil?
          addSubview(new_symbol)
        else
          insertSubview(new_symbol, atIndex:insertion_index)
        end
        @symbols_cache[symbol_key] = new_symbol
      end
      
        
      # p "TESTING FRAME"
      # p "   -> #{keyframe == layer.keyframes.last}"
      # p "   -> #{keyframe.index} == #{frame_number}"
      # p "   -> #{keyframe.tweened == false}"
        
      #at this point we have the right content, let's set the position!
      #if we're the last keyframe, or at the start of the keyframe, or on a keyframe with no tween... do the easy thing
      if keyframe == layer.keyframes.last || keyframe.index == frame_number || keyframe.tweened == false
        apply_keyframe_data(@symbols_cache[symbol_key], keyframe.x, keyframe.y, keyframe.alpha, keyframe.scale_x, keyframe.scale_y, keyframe.skew_x, keyframe.skew_y, keyframe.pivot_x, keyframe.pivot_y)
      else

        interped = (frame_number - keyframe.index) / keyframe.duration.to_f
        ease = keyframe.ease
        
        if ease != 0
          if ease < 0
            #ease in
            inv = 1 - interped
            t = 1 - inv*inv
            ease = -ease
          else
            t = interped*interped
          end
        end
        
        flview = @symbols_cache[symbol_key]
        
        next_keyframe = layer.keyframes[keyframe_index + 1]
        
        x = keyframe.x + (next_keyframe.x - keyframe.x) * interped;
        y = keyframe.y + (next_keyframe.y - keyframe.y) * interped;
        scale_x = keyframe.scale_x + (next_keyframe.scale_x - keyframe.scale_x) * interped;
        scale_y = keyframe.scale_y + (next_keyframe.scale_y - keyframe.scale_y) * interped;
        skew_x = keyframe.skew_x + (next_keyframe.skew_x - keyframe.skew_x) * interped;
        skew_y = keyframe.skew_y + (next_keyframe.skew_y - keyframe.skew_y) * interped;
        alpha = keyframe.alpha + (next_keyframe.alpha - keyframe.alpha) * interped;

        apply_keyframe_data(@symbols_cache[symbol_key], x, y, alpha, scale_x, scale_y, skew_x, skew_y)        
      end
    end
    frame_number
  end

  #seems like pivot_x/y are ignored, but i'll pass them anyway                    
  def apply_keyframe_data(flview, x, y, alpha, scale_x, scale_y, skew_x, skew_y,pivot_x=nil, pivot_y=nil)
    #position
    # flview.frame = [[keyframe.x, keyframe.y], [flview.bounds.size.width, flview.bounds.size.height]]
    flview.center = [x, y]
    
    #alpha
    flview.alpha = alpha
    
    scale = CGAffineTransformMakeScale(scale_x, scale_y)
    
    skew = CGAffineTransformIdentity
    if skew_x != 0
      if skew_x == skew_y
        skew = CGAffineTransformMakeRotation(skew_x)
      else
        # | cos(skew_y)  -sin(skew_x)  0 |
        # | sin(skew_y)   cos(skew_x)  0 |
        p "TODO: FIX SKEWING MATH"
        skew = CGAffineTransformMake(Math.cos(skew_y), -1*Math.sin(skew_x), Math.sin(skew_y), Math.cos(skew_x),0,0)
      end
    end

    scalerot = CGAffineTransformConcat(scale, skew)
    
    flview.transform = CGAffineTransformIdentity
    # if pivot_x != nil
    #   flview.transform = CGAffineTransformMakeTranslation(-pivot_x, -pivot_y)
    # end
    
    flview.transform = CGAffineTransformConcat(flview.transform, scalerot)

    # if pivot_x != nil
    #   flview.transform = CGAffineTransformConcat(flview.transform, CGAffineTransformMakeTranslation(pivot_x, pivot_y))
    # end
    
  end
  
  def play_once(frame_label, handler=nil)
    goto_and_play(frame_label)
    @stop_frame = @movie.labels[frame_label] + @movie.durations[frame_label]    
    @stop_frame_handler = handler
  end
  
  def loop(frame_label)
    goto_and_play(frame_label)
    @start_frame = @movie.labels[frame_label]
    @stop_frame = @movie.labels[frame_label] + @movie.durations[frame_label]
  end
  
  def goto_and_stop(identifier)
    if identifier.is_a?Fixnum
      goto(identifier)
    else
      goto(@movie.labels[identifier])
    end
    self.is_playing = false
  end
  
  def goto_and_play(identifier)
    if identifier.is_a?Fixnum
      goto(identifier)
    else
      goto(@movie.labels[identifier])
    end
    self.is_playing = true
  end
  
  def is_playing=(new_state)
    @is_playing = new_state
    if @is_playing
      $flump.register(self)
    else
      $flump.unregister(self)
    end
    @stop_frame = nil
    @stop_frame_handler = nil
    @start_frame = nil
  end
  def is_playing
    $flump.is_playing(self)
  end
  
end

class FlumpLibrary
  SHOW_PIVOT = false
  SHOW_BOUNDING_BOX = false
  
  def initialize(asset_path=nil)
    
    #prefix for a directory which contains all your flump animations, i.e. "animations" or "flump"
    @asset_path = asset_path || ""
    @asset_path << "/" if asset_path.split("").last != "/"
    
    #these are all "private" -- use the getters to access their contents    
    @files = {}
    @symbols = {}
    @movies = {}
    @clips = []
    
    #a record of which atlases we've already loaded, just so we don't dupe
    @atlases = {}

    @start_time = NSDate.date
    @last_update = 0
  end
  
  def stop_timer
    @timer.invalidate if (@timer && @timer.isValid)
    @timer = nil
  end
  
  
  def register(flview)
    @clips << flview if @clips.index(flview).nil?
    
    if @timer.nil?
      @last_update = @start_time.timeIntervalSinceNow*-1
      @timer = NSTimer.scheduledTimerWithTimeInterval(1.0/100.0, target:self, selector:'update', userInfo:nil, repeats:true)      
    end
  end
  
  def unregister(flview)
    @clips.delete(flview)
    
    if @clips.empty?
      @timer.invalidate if (@timer && @timer.isValid)
      @timer = nil
    end
  end
  
  def is_playing(flview)
    @clips.index(flview) != nil
  end
  
  def update
    
    time = @start_time.timeIntervalSinceNow * -1
    delta = time - @last_update
    @last_update = time
    
    #if a clip has no parent, remove it from updates (effectively "stops" it)
    dead = []
    @clips.each do |clip|
      if clip.superview.nil?
        dead << clip
        next
      end
      
      clip.advance_time(delta)
    end
    
    dead.each{ |clip| unregister(clip) }
  end
  
  def get_view(ref)
    if @symbols[ref]
      symbol = @symbols[ref]
      if @files[symbol.file_name].nil?
        image = UIImage.imageNamed("#{symbol.atlas_name}/#{symbol.file_name}")
        @files[symbol.file_name] = image
      end

      atlas = @files[symbol.file_name].CGImage
      
      cgimage = CGImageCreateWithImageInRect(atlas, symbol.rect)
      # image = UIImage.imageWithCGImage(cgimage)
      
      img_scale = RetinaHelper.retina? ? 2 : 1
      image = UIImage.imageWithCGImage(cgimage, scale:img_scale, orientation:@files[symbol.file_name].imageOrientation)

      
      # # holder = UIView.alloc.initWithFrame([[0,0], [symbol.width, symbol.height]])
      # view = UIImageView.alloc.initWithImage(image)
       
      view = OffsetImageView.alloc.initWithImage(image, CGPointMake(symbol.origin.x, symbol.origin.y))
      view.layer.anchorPoint = symbol.anchor
      
      if SHOW_PIVOT
        pivot_view = UIView.alloc.initWithFrame([[0,0],[10,10]])
        pivot_view.layer.cornerRadius = 5
        pivot_view.backgroundColor = "#ff0000".to_color
        view.addSubview(pivot_view)
      end
      
      if SHOW_BOUNDING_BOX
        bounding_view = UIView.alloc.initWithFrame([[-symbol.origin.x,-symbol.origin.y],[symbol.rect.size.width,symbol.rect.size.height]])
        bounding_view.layer.borderColor = "#ff0000".to_color.CGColor
        bounding_view.layer.borderWidth = 1.0
        view.addSubview(bounding_view)
      end
      
      return view
    elsif @movies[ref]
      return FlumpView.alloc.initWithMovie(@movies[ref])
    else
      raise "UNRECOGNIZED SYMBOL #{ref}"
    end
  end
  
  def get_symbol(symbol_name)
    @symbols[symbol_name]
  end
  
  def get_movie(movie_name)
    @movies[movie_name]
  end
  
  def movies
    @movies.keys
  end
  
  #pulled from bubble-wrap, want to elminate dependencies
  def parse_json(str_data)
    return nil unless str_data
    data = str_data.respond_to?(:to_data) ? str_data.to_data : str_data
    opts = NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves | NSJSONReadingAllowFragments
    error = Pointer.new(:id)
    obj = NSJSONSerialization.JSONObjectWithData(data, options:opts, error:error)
    raise StandardError, error[0].description if error[0]
    if block_given?
      yield obj
    else 
      obj
    end
  end
  
  def load_atlas(atlas_name)
    #don't load the same atlas twice, we'd get lots of dupe symbol errors
    return unless @atlases[atlas_name].nil?
    @atlases[atlas_name] = true
    
    #assumes the atlas path is /resources/atlas_name
    #could make this a config parameter somewhere...
    path = File.join(NSBundle.mainBundle.resourcePath, "#{@asset_path}#{atlas_name}/library.json")
  	file = File.open(path, 'r')
  	json = file.read

    data = parse_json(json)
    # data = BW::JSON.parse(json)
  	
  	#only load the resolution we need... i.e. why bother with retina if we're non-retina?
    scale_factor = RetinaHelper.retina? ? 2 : 1
    atlases = data["textureGroups"].select{ |tg| tg["scaleFactor"] == scale_factor }.first["atlases"]
    
    atlases.each do |atlas|
      file_name = atlas['file']
      @files[file_name] = nil  #lazy load
      
      atlas["textures"].each do |texture|
        #corresponds to our Library Symbol
        symbol_name = texture["symbol"]

        x,y,w,h = texture["rect"]
        ox, oy = texture["origin"]

        unless @symbols[symbol_name].nil?
          raise "DUPLICATE SYMBOL FOUND: #{symbol_name} IN FILE #{file_name}"
        end

        @symbols[symbol_name] = FlumpSymbol.new(atlas_name, file_name, symbol_name, [ox,oy], [[x,y],[w,h]])
      end#end of texture loop
    end#end of atlas loop
    
    data["movies"].each do |movie|
      @movies[movie["id"]] = FlumpMovie.new(movie)
    end
    
	end#end of load_atlas
end#end of flump_library

class FlumpMovie  
  
  attr_accessor :name
  attr_accessor :layers
  attr_accessor :labels
  attr_accessor :durations
  
  def initialize(data)
    @name = data["id"]
    @layers = []
    
    # in the canonical Flump runtime, @labels is an array of arrays
    #   where every single layer can have it's own label...
    #
    # i always just have one label per keyframe on an empty layer named "frames", so I'm simplifying
    @labels = {}
    @durations = {}
    
    data["layers"].each do |layer|
      flump_layer = FlumpLayer.new(layer)
      if(flump_layer.name == "frames")
        flump_layer.keyframes.each do |keyframe| 
          @labels[keyframe.label] = keyframe.index unless keyframe.label.nil? 
          @durations[keyframe.label] = keyframe.duration
        end
      else
        @layers << flump_layer
      end
    end
  end
  
  #allows us to do flash-style depth searching
  #   i.e. @dragon.movie.face.eyes
  #   this is a _little_ dangerous since we're 
  #   going through the definition and not the
  #   instance, but the instance is pretty dumb
  #   and this helps for debuggin
  def method_missing(meth, *args)
    if layer = @layers.select{ |l| l.name == meth.to_s }.first
      return layer
    else
      super
    end
  end
  
  def frames
    @layers.map(&:frames).max
  end
  
  def flipbook
    @layers.length > 0 && @layers.first.flipbook
  end
  
end

class FlumpLayer
  
  attr_accessor :name
  attr_accessor :keyframes
  attr_accessor :flipbook
  
  def initialize(data)
    @name = data["name"]
    @keyframes = []
    
    data["keyframes"].each do |keyframe|
      @keyframes << FlumpKeyframe.new(keyframe)
    end
    
    @flipbook = data["flipbook"] || false
  end
  
  def keyframe_for_frame(frame)
    raise "INVALID FRAME" if frame.nil?
    @keyframes.each_with_index do |keyframe, i|
      raise "NO INDEX!" if keyframe.index.nil?
      return keyframe if keyframe.index == frame
      if keyframe.index > frame && i > 0
        return @keyframes[i-1]
      end
    end
    nil
  end
  
  #how many total frames are in the movie?
  def frames
    @keyframes.last.index + @keyframes.last.duration
  end
  
end

class FlumpKeyframe
  
  attr_accessor :index, :duration, :ref, :label, :x, :y, :scale_x, :scale_y, :skew_x, :skew_y, :pivot_x, :pivot_y, :visible, :alpha, :tweened, :ease
  def initialize(data)
    @index = data["index"]
    @duration = data["duration"]
    @ref = data["ref"]  #TODO: convert this to symbol id to save space?
    @label = data["label"] #keyframe label, i.e. gotoAndPlay("idle")
    @x, @y = data["loc"]
    @scale_x, @scale_y = data["scale"]
    @skew_x, @skew_y = data["skew"]

    @pivot_x, @pivot_y = data["pivot"]
    scale = RetinaHelper.retina? ? 0.5 : 1
    @pivot_x = @pivot_x.to_i * scale
    @pivot_y = @pivot_y.to_i * scale
    
    @visible = data["visible"]
    @alpha = data["alpha"]
    @tweened = data["tweened"]
    @ease = data["ease"]
  end
  
  def rotation
    self.skew_x
  end
  def alpha
    @alpha || 1.0
  end
  def ease
    @ease || 0.0
  end
  def skew_x
    @skew_x || 0
  end
  def skew_y
    @skew_y || 0
  end
  def scale_x
    @scale_x || 1
  end
  def scale_y
    @scale_y || 1
  end
  
end

class FlumpSymbol
  attr_accessor :atlas_name, :file_name, :name, :origin, :rect
  
  def initialize(atlas_name, file_name, name, origin, rect)
    @atlas_name = atlas_name
    @file_name = file_name
    @name = name
    @rect = CGRectMake(*rect.flatten)
    scale = RetinaHelper.retina? ? 0.5 : 1
    @origin = CGPointMake(origin.first * scale, origin.last * scale)
  end
  
  def width
    rect.size.width
  end
  def height
    rect.size.height
  end
  
  def anchor
    offset_x = @origin.x - @rect.origin.x
    offset_y = @origin.y - @rect.origin.y
    CGPointMake(offset_x / @rect.size.width, offset_y / @rect.size.height)
  end
  
end