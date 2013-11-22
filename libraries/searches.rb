# Author:: Frank Breedijk <fbreedijk@schubergphilis.com>
# Copyright:: Copyright (c) 2013
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module SearchesLib
  @@cached_searches = Hash.new()

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
    return cidrs.sort.join(",")
  end

  def expand_search(rule='')
    exp = rule
    while ( exp =~ /\{([^\}]*)\}/ ) do
      expanded = @@cached_searches[$1]
      if ( expanded == nil ) then
        expanded = search_to_cidrlist($1)
        @@cached_searches[$1] = expanded
      end
      exp.gsub!(/\{#{$1}\}/,expanded)
    end # while
    if ( rule != exp ) then
      Chef::Log.info("Expanded #{rule} to #{exp}")
    end
    return exp
  end #expand_search

end
