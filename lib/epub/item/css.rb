module Epub
  class CSS < Item

    attr_accessor :css, :sass

    def initialize(epub, id) 
      super(epub, id)

      @type = :css
      @normalized_dir = "OEBPS"
    end

    def standardize
      log "Standardizing css #{@filepath}..."

      # Create the sass from css
      css_to_sass

      # fonts need resizing to an em value to enable scaling
      convert_fonts

      # namespace by the css filename to avoid conflicting identifiers accross sheets (requires html to be namespaced)
      namespace_by_filename

      # Render CSS
      sass_to_css
    end

    def standardize!
      standardize
      save
    end

    def normalize
      log "Normalizing css #{@filepath}..."

      # Create the sass from css
      css_to_sass

      # any refs need rewriting to the normalized paths
      normalize_paths

      # Render CSS
      sass_to_css
    end


    # TODO: Split this up into multiple methods
    # Normalizes the guide by flattening the file paths
    # 
    # @see Epub::File#normalize!
    def normalize!
      normalize
      save
    end


    # Compress the css
    def compress!
      css = YUI::CssCompressor.new.compress(css)
      save
    end

    def to_s
      css.to_s
    end


    private

      def css
        @css ||= read
      end

      # TODO: Work out how to do this without shelling out
      def css_to_sass
        Tempfile.open("css_to_sass") do |file|
          # Write the css
          file.write css

          # Rewind back to the start
          file.rewind

          # Use the std sass command line to convert a CSS file to SASS
          command = "sass-convert #{file.path}"
          self.sass = `#{command}`
        end
        sass
      end

      # Render CSS
      def sass_to_css
        self.css = Sass::Engine.new(sass).render
      end
      
      # Adds underscores to all ids and classes
      def prefix_css_selectors(prefix = "_")
        selector_regex = /^\s*?(?!\/\*)+?[^:]*?(?!:\s)([\.#][^,\s]*[:]?[^\s,])$/

        new_sass = ""
        sass.each_line do |line|
          # Skip blank lines
          next if line =~ /^\s*$/

          line = line.gsub(selector_regex) do |str|
            # Add the underscores
            str.gsub!(/([#.])/, "\\1#{prefix}")
          end
          new_sass << line
        end

        sass = new_sass
      end

      # Convert a css size rule value to ems, the supported formats are:
      # * point (24pt)
      # * pixels (24px)
      # * percent (24%)
      # * by name (xx-small, x-small, small, medium, large, x-large, xx-large)
      #
      # @param [String] css size rule
      # @return [String] css size rule in ems
      # see http://www.websemantics.co.uk/resources/font_size_conversion_chart/
      def self.val_to_em(rule_value)
        # Convert CSS names to px or em values
        case rule_value
          when /smaller/  then "0.8em"
          when /larger/   then "1.2em"
          when /xx-small/ then "8px"
          when /x-small/  then "10px"
          when /small/    then "13px"
          when /medium/   then "16px"
          when /large/    then "18px"
          when /x-large/  then "24px"
          when /xx-large/ then "32px"
          else rule_value
        end
      end

      # CSS directives must be top levl
      # We namespace the css so these will bork
      # So loop through identifying directives and remove them an anything indented inside
      def move_css_directives
        css_directives = ""
        new_sass = ""
        directive_indent = nil

        # Go through the lines rewriting paths as appropriate
        sass.each_line do |line|
          sass_line = SassLine.new(@epub, self, line, directive_indent)

          if sass_line.inside_css_directive?
            css_directives += "#{" " * directive_indent}#{sass_line.to_s.strip}\n"
            next
          elsif sass_line.is_css_directive?
            css_directives += "#{sass_line.to_s.strip}\n"
            directive_indent = sass_line.indent
          else
            directive_indent = nil
            new_sass += "#{sass_line.to_s}\n"
          end

          if sass_line.missing_item?
            create_manifest_entry(sass_line.old_src)
          end
        end

        self.sass = "#{css_directives}\n\n#{new_sass}"
      end


      # rewrite internal paths to normalized paths
      def normalize_paths
        new_sass = ""
        sass.each_line do |line|
          line = SassLine.new(@epub, self, line)
          line.normalize_paths if line.has_path?
          new_sass += "#{line.to_s}\n"
        end

        self.sass = new_sass
      end


      # Convert all fonts to ems
      def convert_fonts
        out = ""
        sass.each_line do |line|
          line.gsub!(/(\s*)(word-spacing|letter-spacing|font-size|line-height|margin-[^\s]+|margin|padding-[\s]+|padding)\s*:(.*)/) do |m|
            #    indent rule:  value
            m = "#{$1}#{$2}: #{CSS.val_to_em($3)}"
          end
          out << line
        end
        self.sass = out
      end


      # Indent all lines with two spaces
      def indent_sass
        self.sass.gsub!(/\n/, "\n  ")
      end

      # Replace body css rule and add it to the above rule using the sass '&'
      def rename_body
        self.sass.gsub!("  body\n", "  &\n")
      end

      # Add a wrapper to the sytlesheet so multiple stylesheets with same identifiers don't conflict
      def namespace_by_filename
        rename_body
        indent_sass
        self.sass = ".epub_#{self.filename_without_ext}\n  #{sass}"

        # remove the @char style css directives (can't be indented)
        move_css_directives
      end

  end
end