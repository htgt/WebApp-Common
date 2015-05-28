WebApp-Common
=============

Common code and files shared between LIMS2 and WGE

## Development

When modifying code within WebAppCommon you must set the specific environment variables so that your LIMS2 / WGE development instances can see your modified code / files.

### Template Toolkit Files
* Default:  '/opt/t87/global/software/perl/lib/perl5/WebAppCommon/shared_templates'
* Custom: `SHARED_WEBAPP_TT_DIR`

```
export SHARED_WEBAPP_TT_DIR=~/workspace/WebApp-Common/shared_templates
```

* To use any new files you place in this directory give it the path from the shared folder.

```
[% INCLUDE 'create_design/diagram_placeholder.tt' %]
```

### Static Files
* Default:  '/opt/t87/global/software/perl/lib/perl5/WebAppCommon/shared_static'
* Custom: `SHARED_WEBAPP_STATIC_DIR`

```
export SHARED_WEBAPP_STATIC_DIR=~/workspace/WebApp-Common/shared_static
```

* To point to any of these static files give it the path from the above shared folder.

```
<script type="text/javascript" src="[% c.uri_for( '/js/diagram.builder.js' ) %]"></script>
```

### Perl Code
* Make sure your local WebAppCommon lib folder is in your PERL5LIB env value.

```
export PERL5LIB=~/workspace/WebApp-Common/lib:$PERL5LIB
```

* The LIMS2 and WGE model both look in the WebAppCommon::Plugin namespace for plugins to load.
* The base classes for the FormValidator code is in WebAppCommon:
    * [WebAppCommon::FormValidator](https://github.com/htgt/WebApp-Common/blob/devel/lib/WebAppCommon/FormValidator.pm) base class for FormValidator code. 
    * [WebAppCommon::FormValidator::Constraint](https://github.com/htgt/WebApp-Common/blob/devel/lib/WebAppCommon/FormValidator/Constraint.pm) stored shared constraints, put any constraints you think might be useful in either site here.
* The rest of the code in the WebAppCommon::Util, WebAppCommon::Crispr and WebAppCommon::Design namespaces are loaded like any other perl module.

## Deployment

Deploy into the the common PERL environment in the t87 vms, in other words **dont** `use lims2-production` or `use wge2` before installing the modules.
