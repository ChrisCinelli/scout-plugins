class MemoryProfiler < Scout::Plugin
  def build_report
    
    if solaris?
      solaris_memory
    else
      linux_memory
    end
    
  end
  
  def linux_memory
    mem_info = {}
    `cat /proc/meminfo`.each_line do |line|
      _, key, value = *line.match(/^(\w+):\s+(\d+)\s/)
      mem_info[key] = value.to_i
    end
    
    # memory info is empty - operating system may not support it (why doesn't an exception get raised earlier on mac osx?)
    if mem_info.empty?
      raise "No such file or directory"
    end
    
    mem_total = mem_info['MemTotal'] / 1024
    mem_free = (mem_info['MemFree'] + mem_info['Buffers'] + mem_info['Cached']) / 1024
    mem_used = mem_total - mem_free
    mem_percent_used = (mem_used / mem_total.to_f * 100).to_i

    swap_total = mem_info['SwapTotal'] / 1024
    swap_free = mem_info['SwapFree'] / 1024
    swap_used = swap_total - swap_free
    unless swap_total == 0    
      swap_percent_used = (swap_used / swap_total.to_f * 100).to_i
    end
    
    # will be passed at the end to report to Scout
    report_data = Hash.new

    report_data['Memory Total'] = mem_total
    report_data['Memory Used'] = mem_used
    report_data['% Memory Used'] = mem_percent_used

    report_data['Swap Total'] = swap_total
    report_data['Swap Used'] = swap_used
    unless  swap_total == 0   
      report_data['% Swap Used'] = swap_percent_used
    end
    report(report_data)
        
  rescue Exception => e
    if e.message =~ /No such file or directory/
      error('Unable to find /proc/meminfo',%Q(Unable to find /proc/meminfo. Please ensure your operationg system supports procfs:
         http://en.wikipedia.org/wiki/Procfs)
      )
    else
      raise
    end
  end
  
  # Memory Used and Swap Used come from the prstat command. 
  # Memory Total comes from prtconf
  # Swap Total comes from swap -s
  def solaris_memory
    report_data = Hash.new
    
    prstat = `prstat -c -Z 1 1`
    prstat =~ /(ZONEID[^\n]*)\n(.*)/
    values = $2.split(' ')

    report_data['Memory Used'] = values[3].to_i
    report_data['Swap Used']   = values[2].to_i
    
    prtconf = `/usr/sbin/prtconf | grep Memory`    
    
    prtconf =~ /\d+/
    report_data['Memory Total'] = $&.to_i
    report_data['% Memory Used'] = (report_data['Memory Used'] / report_data['Memory Total'].to_f * 100).to_i
    
    swap = `swap -s`
    swap =~ /\d+k\sused/
    swap_used = $&.to_i
    swap =~ /\d+k\savailable/
    swap_available = $&.to_i
    report_data['Swap Total'] = (swap_used+swap_available)/1024
    unless report_data['Swap Total'] == 0   
      report_data['% Swap Used'] = (report_data['Swap Used'] / report_data['Swap Total'].to_f * 100).to_i      
    end
    
    report(report_data)
  end
  
  # True if on solaris. Only calcuated on the first run (assumes OS does not change).
  def solaris?
    return memory(:solaris) if !memory(:solaris).nil?
    solaris = false
    begin
      solaris = true if `uname` =~ /sun/i
    rescue
    end
    remember(:solaris, solaris)
    return solaris
  end
end
