#!/usr/bin/env ruby

# In order for watir to work, you need to install firewatir using these instructions:
# http://watir.com/installation/#mac
# After installation, you need to start firefox with javascript shell enabled
# To do this, you need to start firefox with the -jssh flag
# I set up an alias in ~/.profile below
# alias firewatir="nohup /Applications/Firefox.app/Contents/MacOS/firefox-bin -jssh &"

# Thanks to Zsolt Török on Stack Overflow for the illegal charactesr list. 

# TODO: Get the project ported over to mechanize?

# Debug mode changes no file names, just runs the tests to let you know what they WOULD change to
@debug = true
# Log file
@output_file = '/tmp/movie_rename_output.txt'

#ROOT_DIR = "/Volumes/Media/Downloads"
#ROOT_DIR = "/Volumes/Media/Video/Movies"
ROOT_DIR = "/Users/jhart/Movies"
#ROOT_DIR = "/Users/jhart/Sites/media_management/dummy"
SUBSTITUTIONS = {/[\(\)\.\-_\[\]\}\{]/=>' '} # Punctuation substitions for the movie title
MOVIE_FILE_EXTENSIONS = [/.avi$/, /.mkv$/, /.mp4$/] # Video extensions whose names will be changed - update if I missed some
ILLEGAL_CHARACTERS = [ '/', /\n/, /\r/, /\t/, /\0/, /\f/, '`', '?', '*', '\\', '<', '>', '|', '\"', ':']
BLACKLIST_TERMS = [/\.avi$/,/\.mkv$/,/\.mp4$/,/\d{3,4}p/,/dvdrip/i,/ac3/,/eng/i,/xvid/i,
  /fxm/,/fxg/,/axxo/,/ppvrip/,/www\..*\.(com|org|net)/,/download/i,/iwanna/i,
  /extratorrentrg/,/torrent/,/vice/,/nydic/,/maxspeed/i,/torentz/,/3xforum/,/usabit/,
  /amiable/,/FxM/,/aAF/,/AFO/,/AXIAL/,/UNiVERSAL/,/PFa/,/SiRiUS/,/Rets/,
  /BestDivX/,/NeDiVx/,/ESPiSE/,/iMMORTALS/,/QiM/,/QuidaM/,/COCAiN/,/DOMiNO/,
  /JBW/,/LRC/,/WPi/,/NTi/,/SiNK/,/HLS/,/HNR/,/iKA/,/LPD/,/DMT/,/DvF/,/IMBT/,
  /LMG/,/DiAMOND/,/D0PE/,/NEPTUNE/,/SAPHiRE/,/PUKKA/,/FiCO/,/aXXo/,/VoMiT/,/ViTE/,
  /ALLiANCE/,/mVs/,/XanaX/,/FLAiTE/,/PREVAiL/,/CAMERA/,/VH-PROD/,/BrG/,/replica/,
  /FZERO/,/multisub/,/fps/,/kbps/,/wunseedee/,/ppvrip/,/dvdscr/]
  
# Intialize the logging variables
@failures = []
@messages = []
@successes = {}
def self.initialize_mechanize()
  require 'rubygems'
  require 'mechanize'
  
  @agent = Mechanize.new { |a|
     a.user_agent_alias = 'Mac Safari'
     a.follow_meta_refresh = true
  }
end

def self.initialize_watir()
  require 'rubygems'
  require 'firewatir'
  
  b = Watir::Browser.new

  return b
end

def self.movie_file?(filename)
  # check if it's a movie file first
  movie_file = false
  
  MOVIE_FILE_EXTENSIONS.each do |ext|
    if(filename[ext])
      movie_file = true
    end
  end
  
  if(filename[/s\d\de\d\d/i])
    movie_file = false
    @messages << "TV Show detected on #{filename}"
  end
  
  if(filename[/sample/i])
    movie_file = false
    @messages << "Sample movie detected on #{filename}"
    
  end
  
  return movie_file
end

def self.clean_name_for_search(filename)
  # remove the extension
  filename = File.basename(filename, '.*')
  
  # Let's try removing everything after the 4 digit date
  match = filename[/.*[\[\{\(]?\d{4}[\]\}\)]?/]

  if(match)
    filename = match[0] unless !match[0].kind_of? String
    @messages << "Movie name possibly detected. #{filename}"
  else 
    @messages << "No movie name detected, blacklisting terms on #{filename}"
    
    BLACKLIST_TERMS.each { |term|
      if(filename[term])
        filename = filename.gsub(term, '')
      end
    }
  end
  
  SUBSTITUTIONS.each do |k,v|
    if(filename[k])
      filename = filename.gsub(k,v)
    end
  end
  
  filename
end

def self.fetch_movie_info(movie_title)
  puts "Searching for " + movie_title
   uri = "http://www.google.com/"
   page = @agent.get(uri)

   search_form = page.form_with(:name => "f")
   search_form.field_with(:name => "q").value = movie_title + " site:imdb.com"
   search_results = @agent.submit(search_form)

   title = nil

   search_results.links.each do |link|
     if(link.href[/imdb\.com\/title\//])
       movie_page = link.click
       if(movie_page.title[/(.*)\(\d{4}\) - IMDb/])
         title = movie_page.title[/(.*\(\d{4}\))/]
         break
       end
     end
   end

   return title
end

def self.im_feeling_lucky_search(filename)
  #TODO: URL parsing correctly.
  puts "Searching for #{filename}"
  search_string = CGI::escape(filename + " site:imdb.com")
  uri = "http://www.google.com/#q=#{search_string}&btnI"
  @b.goto uri
  # Wait for the redirect from I'm Feeling Lucky redirect
  sleep 1 until !@b.title[/google/i]
  # Is the first link a IMDB page?
  if(@b.title[/imdb/i])
    if @b.title[/google search/i]
      @failures << "IMDB Search failed on " + filename
      puts "We're stuck in some weird bug of firewatir. This probably needs to be fixed."
      sleep 3 
      return nil
    else
      return @b.title.gsub(/ - imdb/i, '')
    end
  else
    # TODO: See if it's worth my time to follow through here, or just hand rename them
    puts "IMDB Search failed – Title was #{@b.title}"
    @failures << "IMDB Search failed on " + filename
    return nil
  end
end

# This processes an individual file, and passes a filename to clean it up
def self.process_file(filename, directory=nil)
  # If it's already in good format, just return okay.
  
  original_filename = filename
  
  if(filename[/(.*) \(\d\d\d\d\)\.\w\w\w/])
    puts "Already named properly with #{filename}"
    @messages << "Already named properly with #{filename}"
    return nil
  end
  if(movie_file? filename)
    # Grab extension, clean filename
    extension = filename[filename.rindex('.'),filename.length]
    filename = clean_name_for_search(filename)
    
    # Search on Google to get the title name
    #rename_to = im_feeling_lucky_search(filename)
    rename_to = fetch_movie_info(filename)

    if(rename_to)
      directory = File::SEPARATOR + directory rescue ""
   
      # To be safe cross-platform, we remove all potentially invalid characters in filenames
      ILLEGAL_CHARACTERS.each { |char|
        rename_to.gsub!(char, '-')
      }
            
      if(!@debug)
        begin
          # Move the file to it's new name (and up a directory if it was one directory deep)
          File.rename(ROOT_DIR + directory + File::SEPARATOR + original_filename, ROOT_DIR + File::SEPARATOR + rename_to + extension)
          @successes[filename] = rename_to + extension
          puts "#{directory + File::SEPARATOR + filename} => #{rename_to + extension}"
        rescue Exception => e
          puts "Failed - " + e
          @failures << filename
        end
      else
        @successes[filename] = rename_to + extension + "(DEBUG)"
        puts "#{directory + File::SEPARATOR + filename} => #{rename_to + extension}"
      end
      
    end
  else
    @messages << "#{filename} was not a recognized movie file"
  end
end


## MAIN PROGRAM RUNS

#@b = initialize_watir()
#require 'cgi' # For URL encoding
require 'ftools' # To rename files

initialize_mechanize()

d = Dir.new(ROOT_DIR)

d.each { |filename|
  puts "Processing #{filename}"
	if(filename[/^\./])
		#puts "Starts with a period. Skipping #{filename}"
	else
	  # Test for file (as opposed to directory)
	  if(File.ftype(ROOT_DIR + File::SEPARATOR + filename) == 'file')
	    process_file(filename)
    else
      directory = filename
      d1 = Dir.new(ROOT_DIR + File::SEPARATOR + filename)
      d1.each do |folder_filename|
        if(File.ftype(ROOT_DIR + File::SEPARATOR + directory + File::SEPARATOR + folder_filename) == 'file')
          process_file(folder_filename, directory)
        else
          # Too deep. No need to enter two folders deep. (If you do need to, start here)
        end
      end
    end
	end
}

# OUTPUT RESULTS TO A FILE

f = File.new(@output_file,'w')
f.puts
f.puts "======================"
f.puts "Failures"
f.puts "======================"
@failures.each { |failure|
  f.puts failure
} 
f.puts
f.puts "======================"
f.puts "Messages"
f.puts "======================"
@messages.each { |message|
  f.puts message
}
f.puts
f.puts "======================"
f.puts "Successes"
f.puts "(The below files were renamed from the left filename to the right)"
f.puts "If you're in debug mode, the files didn't actually change names"
f.puts "======================"
@successes.each { |k, v|
  f.puts k + "=>" + v
}
  
f.close
  
#END PROGRAM
