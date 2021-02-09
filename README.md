[![License](https://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)
[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/73/badge)](https://bestpractices.coreinfrastructure.org/projects/73)
[![Puppet Forge](https://img.shields.io/puppetforge/v/simp/ds389.svg)](https://forge.puppet.com/simp/ds389)
[![Puppet Forge Downloads](https://img.shields.io/puppetforge/dt/simp/ds389.svg)](https://forge.puppet.com/simp/ds389)
[![Build Status](https://travis-ci.org/simp/pupmod-simp-ds389.svg)](https://travis-ci.org/simp/pupmod-simp-ds389)

#### Table of Contents

<!-- vim-markdown-toc GFM -->

* [Description](#description)
* [This is a SIMP module](#this-is-a-simp-module)
* [Setup](#setup)
  * [Beginning with ds389](#beginning-with-ds389)
    * [Enabling the default instance](#enabling-the-default-instance)
* [Usage](#usage)
  * [Creating additional instances](#creating-additional-instances)
  * [Deleting instances](#deleting-instances)
  * [Enabling the remote admin interface](#enabling-the-remote-admin-interface)
  * [Running the 389DS management console GUI](#running-the-389ds-management-console-gui)
* [Reference](#reference)
* [Limitations](#limitations)
* [Development](#development)
  * [Unit tests](#unit-tests)
  * [Acceptance tests](#acceptance-tests)

<!-- vim-markdown-toc -->

## Description

This module manages the [389 Directory Server][389ds] (389DS), an
enterprise-class open source LDAP server for Linux.  Options are provided to
both create a default LDAP instance and to bootstrap it with SIMP's traditional
LDAP hierarchy.

  ---
  > TLS connections are currently not supported, but [this is on the short list](https://simp-project.atlassian.net/browse/SIMP-8340) of future improvements.
  ---

The module is named `ds389` because Puppet modules cannot start with a digit.

## This is a SIMP module

This module is a component of the [System Integrity Management Platform](https://simp-project.com)

If you find any issues, please submit them via [JIRA](https://simp-project.atlassian.net/).

Please read our [Contribution Guide](https://simp.readthedocs.io/en/stable/contributors_guide/index.html).

This module should be used within the SIMP ecosystem and will be of limited
independent use when included on its own.

## Setup

### Beginning with ds389

To set up a 389DS server, simply `include ds389`. This will create a server with
no active instances and can be fully managed by hand.

#### Enabling the default instance

If you are coming from the `simp-openldap` module, you will probably want to
populate the default LDAP instance and schema.  To do this, add the following to
Hiera:

```yaml
---
ds389::initialize_ds_root: true
ds389::bootstrap_ds_root_defaults: true
```

Once configured, you can query/manage the default instance entries using
something like the following:

```bash
ldapsearch -x \
  -y "/usr/share/puppet_ds389_config/puppet_default_root_ds_pw.txt" \
  -D "cn=Directory Manager" \
  -h `hostname -f` \
  -b "dc=your,dc=domain"
```

You can get the correct entry for the `-b` option using the following:

```bash
puppet apply -e '$dn = simplib::ldap::domain_to_dn($facts["domain"], true); notice("DOMAIN => ${dn}")'
```

## Usage

### Creating additional instances

389DS can host any number of LDAP instances but you need to ensure that all port
numbers are unique! If port numbers overlap, then issues will arise when
managing the services.

You must specify a `base_dn` and a `root_dn` for each instance, since these are
what define both the root of the directory (`base_dn`) and the administrative
user of the directory (`root_dn`). These **can overlap** between instances but
it is recommended that you keep them unique.

```yaml
---
ds389::instances:
  test:
    base_dn: 'dc=test,dc=domain'
    root_dn: 'cn=Test Admin'
    listen_address: '0.0.0.0'
    port: 380
  test2:
    base_dn: 'dc=some other,dc=space'
    root_dn: 'cn=Directory Manager'
    listen_address: '0.0.0.0'
    port: 381
```

To access data on these instances, you need to direct your command to the
appropriate port.

For example, to access the `test` instance:

```bash
ldapsearch -x \
  -y "/usr/share/puppet_ds389_config/puppet_default_root_ds_pw.txt" \
  -D "cn=Directory Manager" \
  -h `hostname -f` \
  -p 380 \
  -b "dc=your,dc=domain"
```

### Deleting instances

LDAP instances are **NOT** automatically purged when they cease being managed by
Puppet. This is a safety precaution, to protect users who may have set up
instances using some other method, like the [management console
GUI][java-console].  Automatic purging could result in the catastrophic
loss of such valid yet unmanaged LDAP instances.

If you wish to remove an instance, you can either do it directly in Puppet:

```puppet
ds389::instance { 'test2':
  ensure => 'absent'
}
```

Or you can do it in Hiera:

```yaml
---
ds389::instances:
  test:
    listen_address: '0.0.0.0'
    port: 380
  test2:
    ensure: absent
```

Just remember that Puppet will attempt to remove this instance every time it
runs! This means that if you create an instance by hand with the name `test2`
then Puppet will remove it at the next run.

### Enabling the remote admin interface

If you wish to use a management interface, you will need to enable the remote
admin interface.

To do this, set the following in Hiera:

```yaml
---
ds389::enable_admin_service: true
```

  ---
  > The admin password will be auto-generated by `simplib::passgen` if one is not
  > set in the `ds389::admin_password` parameter.
  ---

### Running the 389DS management console GUI

The Java-based [389DS management console][java-console] is a thick client UI.
You will probably want to forward the UI itself over SSH to your remote system,
as it is _not_ recommended to expose the admin port to the outside world.

  ---
  > This module does not directly manage the DS management console, because
  > it is [slated by the vendor to change in the near future][console-deprecation].
  ---


Run the following (or use Puppet) to install the necessary packages:

```bash
yum install xauth
yum install 389-console
```

You can then run the following to run the console from a remote system:

```bash
ssh -X 389ds.server.fqdn 389-console -a http://<389ds.server.ip>:9830
```

## Reference

See [REFERENCE.md](./REFERENCE.md) for module API documentation.

For more details about 389DS, please see the [vendor
documentation](https://access.redhat.com/documentation/en-us/red_hat_directory_server/10/html/installation_guide/preparing_for_a_directory_server_installation-installation_overview).

Configuration item details can be found in the [cn=config
documentation](https://access.redhat.com/documentation/en-us/red_hat_directory_server/10/html/configuration_command_and_file_reference/core_server_configuration_reference#cnconfig).


## Limitations

This is still a work in progress and breaking changes may occur until 1.0.0

## Development

Please read our [Contribution Guide](https://simp.readthedocs.io/en/stable/contributors_guide/index.html).

### Unit tests

Unit tests, written in ``rspec-puppet`` can be run by calling:

```shell
bundle exec rake spec
```

### Acceptance tests

To run the system tests, you need [Vagrant](https://www.vagrantup.com/) installed. Then, run:

```shell
bundle exec rake beaker:suites
```

Some environment variables may be useful:

```shell
BEAKER_debug=true
BEAKER_provision=no
BEAKER_destroy=no
BEAKER_use_fixtures_dir_for_modules=yes
```

* `BEAKER_debug`: show the commands being run on the STU and their output.
* `BEAKER_destroy=no`: prevent the machine destruction after the tests finish so you can inspect the state.
* `BEAKER_provision=no`: prevent the machine from being recreated. This can save a lot of time while you're writing the tests.
* `BEAKER_use_fixtures_dir_for_modules=yes`: cause all module dependencies to be loaded from the `spec/fixtures/modules` directory, based on the contents of `.fixtures.yml`.  The contents of this directory are usually populated by `bundle exec rake spec_prep`.  This can be used to run acceptance tests to run on isolated networks.

[389ds]: https://directory.fedoraproject.org/
[console-deprecation]: https://access.redhat.com/documentation/en-us/red_hat_directory_server/10/html/release_notes/deprecated-functionality-10_5_0
[java-console]: https://access.redhat.com/documentation/en-us/red_hat_directory_server/10/html/administration_guide/starting_management_console

