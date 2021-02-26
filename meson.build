project(
  'switch',
  'vala',
  'c',
  version: '0.1.0',
  meson_version: '>= 0.48.0',
  license: 'GPL3',
)

prefix = get_option('prefix')
datadir = join_paths(prefix, get_option('datadir'))
libdir = join_paths(prefix, get_option('libdir'))
plugindir = join_paths(get_option('prefix'), get_option('libdir'), 'gala', 'plugins')
vapidir = join_paths(meson.source_root(), 'vapi')

add_project_arguments(
  '--vapidir=' + vapidir,
  language: 'vala',
)

gala_dep = dependency('gala')
gdk_dep = dependency('gdk-3.0')
gee_dep = dependency('gee-0.8')
gio_dep = dependency('gio-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
granite_dep = dependency('granite', version: '>=5.5.0')

mutter_dep = []
libmutter_dep = []

vala_flags = []
c_flags = [
  '-DCLUTTER_ENABLE_COMPOSITOR_API',
  '-DCLUTTER_ENABLE_EXPERIMENTAL_API',
  '-DCOGL_ENABLE_EXPERIMENTAL_API',
  '-DCOGL_ENABLE_EXPERIMENTAL_2_0_API'
]

mutter328_dep = dependency('libmutter-2', version: ['>= 3.27', '< 3.29'], required: false)
if mutter328_dep.found()
  libmutter_dep = dependency('libmutter-2', version: '>= 3.27.92')
  mutter_dep = [
    dependency('mutter-cogl-2'), dependency('mutter-cogl-pango-2'),
    dependency('mutter-cogl-path-2'), dependency('mutter-clutter-2')
  ]
endif

mutter330_dep = dependency('libmutter-3', version: ['>= 3.29.4', '< 3.31'], required: false)
if mutter330_dep.found()
  libmutter_dep = dependency('libmutter-3', version: '>= 3.29.4')
  mutter_dep = [
    dependency('mutter-cogl-3'), dependency('mutter-cogl-pango-3'),
    dependency('mutter-cogl-path-3'), dependency('mutter-clutter-3')
  ]
  vala_flags = ['--define', 'HAS_MUTTER330']
endif

mutter332_dep = dependency('libmutter-4', version: ['>= 3.31.2', '< 3.34'], required: false)
if mutter332_dep.found()
  libmutter_dep = dependency('libmutter-4', version: '>= 3.31.2')
  mutter_dep = [
    dependency('mutter-cogl-4'), dependency('mutter-cogl-pango-4'),
    dependency('mutter-cogl-path-4'), dependency('mutter-clutter-4')
  ]
  vala_flags = ['--define', 'HAS_MUTTER330', '--define', 'HAS_MUTTER332']
endif

mutter334_dep = dependency('libmutter-5', version: ['>= 3.34', '< 3.35.1'], required: false)
if mutter334_dep.found()
  libmutter_dep = dependency('libmutter-5', version: '>= 3.34')
  mutter_dep = [
    dependency('mutter-cogl-5'), dependency('mutter-cogl-pango-5'),
    dependency('mutter-cogl-path-5'), dependency('mutter-clutter-5')
  ]
  vala_flags = ['--define', 'HAS_MUTTER330', '--define', 'HAS_MUTTER332', '--define', 'HAS_MUTTER334']
endif

mutter336_dep = dependency('libmutter-6', version: ['>= 3.35.1', '< 3.37'], required: false)
if mutter336_dep.found()
  libmutter_dep = dependency('libmutter-6', version: '>= 3.35.1')
  mutter_dep = [
    dependency('mutter-cogl-6'), dependency('mutter-cogl-pango-6'),
    dependency('mutter-cogl-path-6'), dependency('mutter-clutter-6')
  ]
  vala_flags = ['--define', 'HAS_MUTTER330', '--define', 'HAS_MUTTER332', '--define', 'HAS_MUTTER334', '--define', 'HAS_MUTTER336']
endif

mutter338_dep = dependency('libmutter-7', version: ['>= 3.37', '< 3.39'], required: false)
if mutter338_dep.found()
  libmutter_dep = dependency('libmutter-7', version: '>= 3.37')
  mutter_dep = [
    dependency('mutter-cogl-7'), dependency('mutter-cogl-pango-7'),
    dependency('mutter-clutter-7')
  ]
  vala_flags = ['--define', 'HAS_MUTTER330', '--define', 'HAS_MUTTER332', '--define', 'HAS_MUTTER334', '--define', 'HAS_MUTTER336', '--define', 'HAS_MUTTER338']
endif

if mutter_dep.length() == 0
  error ('No supported mutter library found!')
endif

mutter_typelib_dir = libmutter_dep.get_pkgconfig_variable('typelibdir')

switch_sources = files(
  'lib/Main.vala'
)

shared_library(
  meson.project_name(),
  switch_sources,
  dependencies: [
    gala_dep,
    gdk_dep,
    gee_dep,
    gio_unix_dep,
    granite_dep,
    glib_dep,
    gobject_dep,
    mutter_dep
  ],
  install: true,
  vala_args: vala_flags,
  c_args: c_flags,
  install_dir: plugindir,
  install_rpath: mutter_typelib_dir,
)

subdir('data')

meson.add_install_script('meson/post_install.py')
