# nginx.ng.streams_config
#
# Manages the configuration of streams files.

{% from 'nginx/ng/map.jinja' import nginx, sls_block with context %}
{% set stream_states = [] %}

# Simple path concatenation.
# Needs work to make this function on windows.
{% macro path_join(file, root) -%}
  {{ root ~ '/' ~ file }}
{%- endmacro %}

# Retrieves the disabled name of a particular stream
{% macro disabled_name(stream) -%}
  {%- if nginx.lookup.stream_use_symlink -%}
    {{ nginx.streams.managed.get(stream).get('disabled_name', stream) }}
  {%- else -%}
    {{ nginx.streams.managed.get(stream).get('disabled_name', stream ~ nginx.streams.disabled_postfix) }}
  {%- endif -%}
{%- endmacro %}

# Gets the path of a particular stream
{% macro stream_path(stream, state) -%}
  {%- if state == True -%}
    {{ path_join(stream, nginx.streams.managed.get(stream).get('enabled_dir', nginx.lookup.stream_enabled)) }}
  {%- elif state == False -%}
    {{ path_join(disabled_name(stream), nginx.streams.managed.get(stream).get('available_dir', nginx.lookup.stream_available)) }}
  {%- else -%}
    {{ path_join(stream, nginx.streams.managed.get(stream).get('available_dir', nginx.lookup.stream_available)) }}
  {%- endif -%}
{%- endmacro %}

# Gets the current canonical name of a stream
{% macro stream_curpath(stream) -%}
  {{ stream_path(stream, nginx.streams.managed.get(stream).get('available')) }}
{%- endmacro %}

# Creates the sls block that manages symlinking / renaming streams
{% macro manage_status(stream, state) -%}
  {%- set anti_state = {True:False, False:True}.get(state) -%}
  {% if state == True %}
    {%- if nginx.lookup.stream_use_symlink %}
  file.symlink:
    {{ sls_block(nginx.streams.symlink_opts) }}
    - name: {{ stream_path(stream, state) }}
    - target: {{ stream_path(stream, anti_state) }}
    {%- else %}
  file.rename:
    {{ sls_block(nginx.streams.rename_opts) }}
    - name: {{ stream_path(stream, state) }}
    - source: {{ stream_path(stream, anti_state) }}
    {%- endif %}
  {%- elif state == False %}
    {%- if nginx.lookup.stream_use_symlink %}
  file.absent:
    - name: {{ stream_path(stream, anti_state) }}
    {%- else %}
  file.rename:
    {{ sls_block(nginx.streams.rename_opts) }}
    - name: {{ stream_path(stream, state) }}
    - source: {{ stream_path(stream, anti_state) }}
    {%- endif -%}
  {%- endif -%}
{%- endmacro %}

# Makes sure the enabled directory exists
nginx_stream_enabled_dir:
  file.directory:
    {{ sls_block(nginx.streams.dir_opts) }}
    - name: {{ nginx.lookup.stream_enabled }}

# If enabled and available are not the same, create available
{% if nginx.lookup.stream_enabled != nginx.lookup.stream_available -%}
nginx_stream_available_dir:
  file.directory:
    {{ sls_block(nginx.streams.dir_opts) }}
    - name: {{ nginx.lookup.stream_available }}
{%- endif %}

# Manage the actual stream files
{% for stream, settings in nginx.streams.managed.items() %}
{% endfor %}

# Managed enabled/disabled state for streams
{% for stream, settings in nginx.streams.managed.items() %}
{% if settings.config != None %}
{% set conf_state_id = 'stream_conf_' ~ loop.index0 %}
{{ conf_state_id }}:
  file.managed:
    {{ sls_block(nginx.streams.managed_opts) }}
    - name: {{ stream_curpath(stream) }}
    - source: salt://nginx/ng/files/stream.conf
    - template: jinja
    - context:
        config: {{ settings.config|json() }}
{% do stream_states.append(conf_state_id) %}
{% endif %}

{% if settings.enabled != None %}
{% set status_state_id = 'stream_state_' ~ loop.index0 %}
{{ status_state_id }}:
{{ manage_status(stream, settings.enabled) }}
{% if settings.config != None %}
    - require:
      - file: {{ conf_state_id }}
{% endif %}

{% do stream_states.append(status_state_id) %}
{% endif %}
{% endfor %}
