require './lib/memprof2'

def testing3
end

def testing2
  a = 'testing'
end

def testing1
  testing2()
  testing3()
end
prof = Memprof2.new
prof.start
testing1()
prof.report
prof.stop



