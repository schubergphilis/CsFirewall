module SearchesLib
  def search_to_cidrlist(search='')
    cidrs = Array.new()
    if ( search == '' ) then
      Chef::Log.warn("search_to_cidrlist called, but no search specified, returning 127.0.0.1/32");
      return "127.0.0.1/32"
    end

    nodes = search(:node, search)
    nodes.each do |n|
      cidrs.push "#{n["ipaddress"]}/32"
    end

    if ( cidrs.length == 0 ) then
      Chef::Log.warn("search #{search} did not return any results, returning 127.0.0.1/32")
      return "127.0.0.1/32"
    end

    Chef::Log.info("search #{search} expanded to #{cidrs.join ","}")
    return cidrs.join ","
  end
end
