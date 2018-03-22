require 'objspace'

class Memprof2
  def start
    ObjectSpace.trace_object_allocations_start

    @call_trace = TracePoint.new(:call, :return) do |tp|
      unless tp.path.include?('memprof2')
        @call_trace = [] if @trace.nil?
        @trace = [] if @trace.nil?

        if tp.event == :call
          @call_trace << [tp.event, tp.lineno]
        elsif @call_trace.length >= 1
          children = []
          while @call_trace.last[0] != :call
            children << @call_trace.pop
          end
          @call_trace << {file: tp.path, start: @call_trace.pop[1], end: tp.lineno, method: tp.method_id, children: children}
        end
      end
    end
    @call_trace.enable
  end

  def stop
    ObjectSpace.trace_object_allocations_stop
    ObjectSpace.trace_object_allocations_clear
  end

  def run(&block)
    ObjectSpace.trace_object_allocations(&block)
  end

  def report(opts = {})
    ObjectSpace.trace_object_allocations_stop
    do_report(opts)
  ensure
    ObjectSpace.trace_object_allocations_start
  end

  def do_report(opts={})
    configure(opts)
    results = collect_info
    # File.open(@out, 'a') do |io|
    #   results.each do |location, memsize|
    #     io.puts "#{memsize} #{location}"
    #   end
    # end
  end

  def configure(opts = {})
    @rvalue_size = GC::INTERNAL_CONSTANTS[:RVALUE_SIZE]
    if @trace = opts[:trace]
      raise ArgumentError, "`trace` option must be a Regexp object" unless @trace.is_a?(Regexp)
    end
    if @ignore = opts[:ignore]
      raise ArgumentError, "`ignore` option must be a Regexp object" unless @ignore.is_a?(Regexp)
    end
    @out = opts[:out] || "/dev/stdout"
    self
  end

  def collect_info
    results = {}
    ObjectSpace.each_object do |o|
      next unless (file = ObjectSpace.allocation_sourcefile(o))
      next if file == __FILE__
      next if (@trace  and @trace !~ file)
      next if (@ignore and @ignore =~ file)

      line = ObjectSpace.allocation_sourceline(o)
      if RUBY_VERSION >= "2.2.0"
        # Ruby 2.2.0 takes into account sizeof(RVALUE)
        # https://bugs.ruby-lang.org/issues/8984
        memsize = ObjectSpace.memsize_of(o)
      else
        # Ruby < 2.2.0 does not have ways to get memsize correctly, but let me make a bid as much as possible
        # https://twitter.com/sonots/status/544334978515869698
        memsize = ObjectSpace.memsize_of(o) + @rvalue_size
      end
      memsize = @rvalue_size if memsize > 100_000_000_000 # compensate for API bug
      klass = o.class.name rescue "BasicObject"
      location = "#{file}:#{line}:#{klass}"
      results[location] ||= {mem: 0, file: file, line: line, class: klass}
      results[location][:mem] += memsize
    end

    results.each {|r| add_to_trace(r[1])}
    puts @call_trace.inspect
  end

  def add_to_trace(result, parent=@call_trace)
    return false if parent == []
    parent.each do |trace|
      if trace[:file] == result[:file] && result[:line] < trace[:end] && result[:line] > trace[:start]
        if !add_to_trace(result, trace[:children])
          trace[:allocations] ||= []
          trace[:allocations] << result
          return true
        end
        return false
      end
      add_to_trace(result, trace[:children])
    end
  end
end


