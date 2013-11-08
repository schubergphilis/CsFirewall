#
# Cookbook Name:: CsFirewall
# Recipe:: manager
#
# Copyright 2013, Schuberg Philis
#
# All rights reserved - Do Not Redistribute
#

# This recipe is run by those nodes that manage the couldstack firewall

Chef::Log.info("Start of CsFirewall::prerequisites recipe")

gem_package "cloudstack_helper" do
  action :install
  ignore_failure true
end

Chef::Log.info("End of CsFirewall::prerequisites recipe")
