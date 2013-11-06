CsFirewall Cookbook
===================
This cookbook forces a node to configure the firewall in cloudstack via the 
knife command

Requirements
------------
The knife command has to be installed and runnable as the root user

Attributes
----------
TODO: List you cookbook attributes here.

e.g.
#### CsFirewall::default
<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Default</th>
  </tr>
  <tr>
    <td><tt>['CsFirewall']['bacon']</tt></td>
    <td>Boolean</td>
    <td>whether to include bacon</td>
    <td><tt>true</tt></td>
  </tr>
</table>

Usage
-----
#### CsFirewall::default
TODO: Write usage instructions for each cookbook.

e.g.
Just include `CsFirewall` in your node's `run_list`:

```json
{
  "name":"my_node",
  "run_list": [
    "recipe[CsFirewall]"
  ]
}
```

Contributing
------------
TODO: (optional) If this is a public cookbook, detail the process for contributing. If this is a private cookbook, remove this section.

e.g.
1. Fork the repository on https://github.schubergphilis.com/fbreedijk/CsFirewall
2. Create a named feature branch (like `add_component_x`)
3. Write you change
4. Write tests for your change (if applicable)
5. Run the tests, ensuring they all pass
6. Submit a Pull Request using Github

License and Authors
-------------------
Authors: 
* Frank Breedijk <fbreedijk@schubergphilis.com>
