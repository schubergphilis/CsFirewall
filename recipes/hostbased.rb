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

# Cookbook Name:: CsFirewall
# Recipe:: default

# This recipe is run by those nodes that manage the couldstack firewall rules

Chef::Log.info("Start of CsFirewall::hostbased recipe")

case node['os']
when "linux"
  include_recipe "CsFirewall::iptables"
else
  Chef::Log.fatal "Your os #{node['os']} is currently not supported by CsFirewall::hostbased"
end # case

Chef::Log.info("End of CsFirewall::hostbased recipe")
