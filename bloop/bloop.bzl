_BloopyInfo = provider(fields = [
    "bloopies",
    "json_files",
])

def _bloopy_java_import(target, ctx):
    java_info = target[JavaInfo]
    return struct(
        jars = java_info.full_compile_jars.to_list(),
        deps = [],
        srcs = [],
    )

def _bloopy_java_binary(target, ctx):
    java_info = target[JavaInfo]
    return struct(
        jars = [],
        deps = ctx.rule.attr.deps,
        srcs = ctx.rule.attr.srcs,
    )

def _bloopy_java_library(target, ctx):
    java_info = target[JavaInfo]
    return struct(
        jars = [],
        deps = [],
        srcs = ctx.rule.attr.srcs,
    )

def _bloopy_scala_import(target, ctx):
    print("SCALA_IMPORT :: NOT IMPLEMENTED YET")
    return struct(
        jars = [],
        deps = [],
        srcs = [],
    )

def _bloopy_scala_library(target, ctx):
    print("SCALA_LIBRAY :: NOT IMPLEMENTED YET")
    return struct(
        jars = [],
        deps = [],
        srcs = [],
    )

_bloopy_maker = {
    'java_binary': _bloopy_java_binary,
    'java_import': _bloopy_java_import,
    'java_library': _bloopy_java_library,
    'scala_import': _bloopy_scala_import,
    'scala_library': _bloopy_scala_library,
}

def _bloop_aspect_impl(target, ctx):
    if ctx.rule.kind in _bloopy_maker:
        bloopy = _bloopy_maker[ctx.rule.kind](target, ctx)
    else:
        bloopy = struct(
            jars = [],
            deps = [],
            srcs = [],
        )

    transitive_bloopies = []
    parents = []
    if hasattr(ctx.rule.attr, "exports"):
        parents.extend(ctx.rule.attr.exports)
    if hasattr(ctx.rule.attr, "deps"):
        parents.extend(ctx.rule.attr.deps)
    if hasattr(ctx.rule.attr, "dep"):
        parents.append(ctx.rule.attr.dep)
    if hasattr(ctx.rule.attr, "runtime_deps"):
        parents.extend(ctx.rule.attr.runtime_deps)

    bloopies_depset_items = None
    json_files_depset_items = None
    if bloopy != None:
        ROOT = "@@ROOT@@"
        label_basename = _smash_label_to_basename(ctx.label)
        json_file_name = "bloop-%s.json" % label_basename
        json_file = ctx.actions.declare_file(json_file_name)
        ctx.actions.expand_template(
            template = ctx.file._module_json_template,
            output = json_file,
            substitutions = {
                "{NAME}": _quote(label_basename),
                "{DIRECTORY}": _quote("%s%s" % (ROOT, ctx.label.package)),
                "{SOURCES}": _quote_list([
                    "%s%s" % (ROOT, f.path)
                    for t in bloopy.srcs
                    for f in t.files.to_list()
                ]),
                "{DEPENDENCIES}": _quote_list([_smash_label_to_basename(t.label) for t in bloopy.deps]),
                "{CLASSPATH}": _quote_list(
                    [
                        ".bloop/%s/classes" % _smash_label_to_basename(t.label)
                         for t in bloopy.deps
                    ] + [
                        j.path
                        for j in bloopy.jars
                    ]
                ),
                "{OUT}": _quote(".bloop/%s" % label_basename),
                "{CLASSES_DIR}": _quote(".bloop/%s/classes" % label_basename),
            },
        )

        bloopies_depset_items = [(ctx.label, bloopy)]
        json_files_depset_items = [(ctx.label, json_file)]

    return [
        _BloopyInfo(
            bloopies = depset(
                items = bloopies_depset_items,
                transitive = [
                    parent[_BloopyInfo].bloopies
                    for parent in parents
                    if _BloopyInfo in parent
                ],
            ),
            json_files = depset(
                items = json_files_depset_items,
                transitive = [
                    parent[_BloopyInfo].json_files
                    for parent in parents
                    if _BloopyInfo in parent
                ],
            ),
        ),
        OutputGroupInfo(
            bloop = [f for (l, f) in json_files_depset_items],
        ),
    ]

bloop_aspect = aspect(
    implementation = _bloop_aspect_impl,
    attr_aspects = ["exports", "deps", "dep", "runtime_deps"],
    attrs = {
        "_module_json_template": attr.label(
            default = Label("//bloop/private:module-template.json"),
            allow_single_file = True,
        ),
    },
)

def _arg_quoted(filename, protect = "="):
    return filename.replace("\\", "\\\\").replace(protect, "\\" + protect)

def _smash_label_to_basename(l):
    bits = []
    if l.workspace_name != "":
        bits.append(l.workspace_name.strip('//'))
    bits.append(l.package.replace("/", "_"))
    bits.append(l.name.replace("/", "_"))
    return "_".join(bits)

def _quote(s):
    return "\"%s\"" % s

def _quote_list(l):
    guts = ",".join([_quote(e) for e in l])
    return "[%s]" % guts


_SCRIPT_TEMPLATE = """#!/usr/bin/env bash
cd $BUILD_WORKSPACE_DIRECTORY
mkdir -p .bloop

echo "Copying bloop files..."
(set -x;
{COPY_FILES}
)

"""

def _bloop_implementation(ctx):

    json_files = []
    for target in ctx.attr.targets:
        if _BloopyInfo in target:
            for (label, json_file) in target[_BloopyInfo].json_files.to_list():
                json_files.append(json_file)

    script = ctx.actions.declare_file(ctx.label.name)
    script_content = _SCRIPT_TEMPLATE.format(
        COPY_FILES = "\n".join([
            'sed "s?@@ROOT@@?$PWD/?" %s > .bloop/%s' % (f.path, f.basename)
            for f in json_files
        ]),
    )
    ctx.actions.write(script, script_content, is_executable = True)

    runfiles = ctx.runfiles(files = json_files)
    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

bloop = rule(
    implementation = _bloop_implementation,
    attrs = {
        "targets": attr.label_list(
            providers = [],
            aspects = [bloop_aspect],
            default = [],
        ),
        "_build_tar": attr.label(
            default = Label("@bazel_tools//tools/build_defs/pkg:build_tar"),
            cfg = "host",
            executable = True,
            allow_files = True,
        ),
    },
    executable = True,
)
