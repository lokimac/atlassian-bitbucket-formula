{% from 'atlassian-bitbucket/map.jinja' import bitbucket with context %}

include:
  - java

bitbucket-dependencies:
  pkg.installed:
    - pkgs:
      - git
      - libxslt

bitbucket:
  file.managed:
    - name: /etc/systemd/system/atlassian-bitbucket.service
    - source: salt://atlassian-bitbucket/files/atlassian-bitbucket.service
    - template: jinja
    - defaults:
        config: {{ bitbucket }}

  module.wait:
    - name: service.systemctl_reload
    - watch:
      - file: bitbucket

  group.present:
    - name: {{ bitbucket.group }}

  user.present:
    - name: {{ bitbucket.user }}
    - home: {{ bitbucket.dirs.home }}
    - gid: {{ bitbucket.group }}
    - require:
      - group: bitbucket
      - file: bitbucket-dir

  service.running:
    - name: atlassian-bitbucket
    - enable: True
    - require:
      - user: bitbucket
      - pkg: bitbucket-dependencies

bitbucket-graceful-down:
  service.dead:
    - name: atlassian-bitbucket
    - require:
      - module: bitbucket
    - prereq:
      - file: bitbucket-install

bitbucket-install:
  archive.extracted:
    - name: {{ bitbucket.dirs.extract }}
    - source: {{ bitbucket.url }}
    - source_hash: {{ bitbucket.url_hash }}
    - if_missing: {{ bitbucket.dirs.current_install }}
    - options: z
    - keep: True
    - require:
      - file: bitbucket-extractdir

  file.symlink:
    - name: {{ bitbucket.dirs.install }}
    - target: {{ bitbucket.dirs.current_install }}
    - require:
      - archive: bitbucket-install
    - watch_in:
      - service: bitbucket

bitbucket-server-xsl:
  file.managed:
    - name: {{ bitbucket.dirs.temp }}/server.xsl
    - source: salt://atlassian-bitbucket/files/server.xsl
    - template: jinja
    - require:
      - file: bitbucket-install
      - file: bitbucket-tempdir

  cmd.run:
    - name: 'xsltproc --stringparam pHttpPort "{{ bitbucket.get('http_port', '') }}" --stringparam pHttpScheme "{{ bitbucket.get('http_scheme', '') }}" --stringparam pHttpProxyName "{{ bitbucket.get('http_proxyName', '') }}" --stringparam pHttpProxyPort "{{ bitbucket.get('http_proxyPort', '') }}" --stringparam pAjpPort "{{ bitbucket.get('ajp_port', '') }}" -o {{ bitbucket.dirs.temp }}/server.xml {{ bitbucket.dirs.temp }}/server.xsl server.xml'
    - cwd: {{ bitbucket.dirs.install }}/conf
    - require:
      - file: bitbucket-server-xsl

bitbucket-server-xml:
  file.managed:
    - name: {{ bitbucket.dirs.install }}/conf/server.xml
    - source: {{ bitbucket.dirs.temp }}/server.xml
    - require:
      - cmd: bitbucket-server-xsl
    - watch_in:
      - service: bitbucket

bitbucket-dir:
  file.directory:
    - name: {{ bitbucket.dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

bitbucket-home:
  file.directory:
    - name: {{ bitbucket.dirs.home }}
    - user: {{ bitbucket.user }}
    - group: {{ bitbucket.group }}
    - mode: 755
    - require:
      - file: bitbucket-dir
    - makedirs: True

bitbucket-extractdir:
  file.directory:
    - name: {{ bitbucket.dirs.extract }}
    - use:
      - file: bitbucket-dir

bitbucket-tempdir:
  file.directory:
    - name: {{ bitbucket.dirs.temp }}
    - use:
      - file: bitbucket-dir

bitbucket-scriptdir:
  file.directory:
    - name: {{ bitbucket.dirs.scripts }}
    - use:
      - file: bitbucket-dir

{% for file in [ 'env.sh', 'start.sh', 'stop.sh' ] %}
bitbucket-script-{{ file }}:
  file.managed:
    - name: {{ bitbucket.dirs.scripts }}/{{ file }}
    - source: salt://atlassian-bitbucket/files/{{ file }}
    - user: {{ bitbucket.user }}
    - group: {{ bitbucket.group }}
    - mode: 755
    - template: jinja
    - defaults:
        config: {{ bitbucket }}
    - require:
      - file: bitbucket-scriptdir
      - group: bitbucket
      - user: bitbucket
    - watch_in:
      - service: bitbucket
{% endfor %}

bitbucket-fix-permission:
  file.directory:
    - names:
      - {{ bitbucket.dirs.install }}/bin
      - {{ bitbucket.dirs.install }}/work
      - {{ bitbucket.dirs.install }}/temp
      - {{ bitbucket.dirs.install }}/logs
    - user: {{ bitbucket.user }}
    - group: {{ bitbucket.group }}
    - recurse:
      - user
      - group
    - require:
      - file: bitbucket-install
      - group: bitbucket
      - user: bitbucket
    - require_in:
      - service: bitbucket

bitbucket-config-file:
  file.managed:
    - name: {{ bitbucket.dirs.home }}/shared/bitbucket.properties
    - user: {{ bitbucket.user }}
    - group: {{ bitbucket.group }}
    - replace: False
    - makedirs: True
    - require:
      - file: bitbucket-home

{% for key, value in bitbucket.get('config', {}).items() %}
bitbucket-config-{{ key }}:
  file.replace:
    - name: {{ bitbucket.dirs.home }}/shared/bitbucket.properties
    - pattern: ^{{ key }}[ \t]*=[ \t]*.*$
    - repl: {{ key }}={{ value }}
    - append_if_not_found: True
    - backup: False
    - require:
      - file: bitbucket-config-file
    - watch_in:
      - service: bitbucket
{% endfor %}
