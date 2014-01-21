#
# Author:: Frank Breedijk <fbreedijk@schubergphilis.com>
# Copyright:: Copyright (c) 2013, Schuberg Philis B.V.
# License:: Apache License, Version 2.0
#
#/ Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Generic cloudstack firewall attributes
default['cloudstack']['firewall']['fwcleanup']  = false
default['cloudstack']['firewall']['forwardcleanup']  = false
default['cloudstack']['firewall']['egresscleanup']  = false
default['cloudstack']['firewall']['aclcleanup']  = false
default['cloudstack']['firewall']['cleanup']  = false
default['cloudstack']['firewall']['iptables']['INPUT'] = 'ACCEPT'
default['cloudstack']['firewall']['iptables']['OUTPUT'] = 'ACCEPT'
default['cloudstack']['firewall']['iptables']['FORWARD'] = 'DROP'
