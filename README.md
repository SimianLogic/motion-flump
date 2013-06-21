# motion-flump

I <3 Flash (for making the arts)

I <3 RubyMotion (for making the apps)

MotionFlump is a RubyMotion runtime for Flump, built using native views. Flump is a toolchain for exporting vector animations out from Flash into gpu-friendly formats. It's really cool and can be found here:   

  https://github.com/threerings/flump

MotionFlump is not a direct port of their runtime (built for Starling), but takes into account some of my own thoughts on how to build games. Also, I am lazy.

Not all flump features are currently implemented -- only the minimum subset needed to render the animations for the game I'm currently working on (see the lazy comment). As I get more time, I'll incorporate their demo movies and start getting broader coverage. I may also write tests & sample code at some point if other people start using it.

Flump requires some sane defaults for setting up animations in Flash, and this runtime has a few more conventions for easy's sake. For example, instead of having arrays of frameLabels, I only check for a layer named "frames" and pull frameLabels from that frame, which saves having to do a lot of array searching for the most common frame tasks. Having worked in the Flash game business for several years, I've never needed to have multiple frame labels on different layers...

## Installation

motion-flump is not fully baked yet, so I'm not planning to publish it. you can clone the repo locally, then run:

    gem build motion-flump.gemspec
    gem install motion-flump

## Usage

Add this to your rakefile:

      gem 'motion-flump'
    
Within your application, you can do things like:

    #at some point I may turn FlumpLibrary into a proper Singleton, but for now this is waaaaay more convenient
  
    $flump = FlumpLibrary.new
    $flump.load_atlas("flump_atlas_name")
  
    clip = $flump.get_view("exported_animation_name")
    addSubview(clip)
  
    #note that "center" actually corresponds to the (0,0) point from the Flash animation, not the true center
    clip.center = [new_x, new_y]
    clip.goto_and_play("frame_label")
    clip.goto_and_stop("frame_label")
    clip.loop("looping_animation_name")
    clip.play_once("animation_name", lambda{ p "animation complete!" } 
  
## Classes

### Core
*FlumpLibrary* - this is the main class. you load all your metadata into it and request animations from it

### Display
*FlumpView* - the workhorse. this corresponds to an exported animation

*OffsetImageView* - hacky way of getting a UIImageView with a specific origin instead of T/L or center. used for symbols

*FlumpBaseView* - just adds a couple of REPL convenience methods

### Definitions (Molds in Flump runtime, Factories elsewhere)
*FlumpMovie* - i.e. movieclip

*FlumpLayer* - a representation of a single layer from your flash animation

*FlumpKeyframe* - keyframe data for a layer

*FlumpSymbol* - i.e. Shape, a representation of a single image from the texture atlas



## Not Yet Implemented
1. FlipBooks aren't yet supported
2. ??? probably other stuff I'm missing

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
