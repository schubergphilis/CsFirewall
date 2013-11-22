# CHANGELOG for CsFirewall

This file is used to list changes made in each version of CsFirewall.

## 0.6.0

* Support of hostbased iptable firewalls

## 0.5.0

* Egress firewall rules are also supported now

## 0.4.4

* Fixed issue #5 - THree bugs fixed by Thijs Houtenbos
- ListNetWorkAcls may return an empty list, the recipe should not break
- search expension did work for ACLs
- Jobs that return the status 0 are still in prgress, wait for an additional return code

## 0.4.3

* Fixed issue #3 - overwritten jobs by a single job

## 0.4.2

* Fixed issue #2 - cloudstack_helper api is wrapped in function that does error handling

## 0.4.1

* Fixed issue #1 - Matching between cloudstack and chef

## 0.4.0:

* Added support for searches

## 0.3.0: 

* Added the nic_# keyword

## 0.2.0:

* Added ACL support

## 0.1.0:

* Initial release of CsFirewall

