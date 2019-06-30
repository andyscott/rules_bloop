_BloopyInfo = provider(fields = [
    "bloopies",
])

def _get_scala_version(target, ctx):
    # this is a total hack
    java_info = target[JavaInfo]
    scala_jars = [
        dep
        for dep in java_info.transitive_runtime_deps
        if dep.is_source and "rules_scala" in dep.owner.workspace_name
    ]
    if len(scala_jars) == 0:
        return None

    print(scala_jars)

    res = scala_jars[0].basename
    res = res[:res.rfind('.')]
    res = res[res.rfind('-') + 1:]
    return res

def _bloopy_java_binary(target, ctx):
    return struct(
        jars = [],
        deps = ctx.rule.attr.deps,
        srcs = ctx.rule.attr.srcs,
        scala = None
    )

def _bloopy_java_library(target, ctx):
    return struct(
        jars = [],
        deps = [],
        srcs = ctx.rule.attr.srcs,
        scala = None
    )

def _bloopy_scala_library(target, ctx):
    java_info = target[JavaInfo]
    return struct(
        jars = [dep for dep in java_info.transitive_runtime_deps if dep.is_source],
        deps = ctx.rule.attr.deps,
        srcs = ctx.rule.attr.srcs,
        scala = _get_scala_version(target, ctx)
    )

def _bloopy_scala_binary(target, ctx):
    java_info = target[JavaInfo]
    return struct(
        jars = [dep for dep in java_info.transitive_runtime_deps if dep.is_source],
        deps = ctx.rule.attr.deps,
        srcs = ctx.rule.attr.srcs,
        scala = _get_scala_version(target, ctx)
    )

_bloopy_maker = {
    'java_binary': _bloopy_java_binary,
    #'java_import': _bloopy_java_import,
    'java_library': _bloopy_java_library,
    'scala_binary': _bloopy_scala_binary,
    #'scala_import': _bloopy_scala_import,
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
    if bloopy != None:
        bloopies_depset_items = [(ctx.label, bloopy)]

    return [
        _BloopyInfo(
            bloopies = depset(
                items = bloopies_depset_items,
                transitive = [
                    parent[_BloopyInfo].bloopies
                    for parent in parents
                    if _BloopyInfo in parent
                ],
            )
        )
    ]

bloop_aspect = aspect(
    implementation = _bloop_aspect_impl,
    attr_aspects = ["exports", "deps", "dep", "runtime_deps"],
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


def _make_bloop_json(ctx, label, bloopy):
    label_basename = _smash_label_to_basename(label)
    json_file_name = "bloop-%s.json" % label_basename
    json_file = ctx.actions.declare_file(json_file_name)

    more_files = []
    more_files.extend(bloopy.jars)

    scala_blob = ""
    if bloopy.scala != None:
        scala_blob = ', "scala" : ' + struct(
            organization = "org.scala-lang",
            name = "scala-compiler",
            version = bloopy.scala,
            jars = [
                "@@RUNFILES_ROOT@@/%s" % j.path
                for j in ctx.files.bazelbuild_rules_scala_compiler_jars
            ],
            options = [],
        ).to_json()

    ctx.actions.expand_template(
        template = ctx.file._module_json_template,
        output = json_file,
        substitutions = {
            "{NAME}": _quote(label_basename),
            "{DIRECTORY}": _quote("@@WORKSPACE_ROOT@@/%s" % label.package),
            "{SOURCES}": _quote_list([
                "@@WORKSPACE_ROOT@@/%s" % f.path
                for t in bloopy.srcs
                for f in t.files.to_list()
            ]),
            "{DEPENDENCIES}": _quote_list([_smash_label_to_basename(t.label) for t in bloopy.deps]),
            "{CLASSPATH}": _quote_list(
                [
                    ".bloop/%s/classes" % _smash_label_to_basename(t.label)
                    for t in bloopy.deps
                ] + [
                    "@@RUNFILES_ROOT@@/%s" % j.path
                    for j in bloopy.jars
                ]
            ),
            "{OUT}": _quote(".bloop/%s" % label_basename),
            "{CLASSES_DIR}": _quote(".bloop/%s/classes" % label_basename),
            "{SCALA_BLOB}": scala_blob
        },
    )

    return (json_file, more_files)

_SCRIPT_TEMPLATE = """#!/usr/bin/env bash
set -e

RUNFILES_ROOT=$PWD
cd $BUILD_WORKSPACE_DIRECTORY
WORKSPACE_ROOT=$PWD
mkdir -p .bloop

echo "Copying bloop files..."
(set -x;
{COPY_FILES}
)

"""

def _bloop_implementation(ctx):

    all_files = []
    json_files = []
    for target in ctx.attr.targets:
        if _BloopyInfo in target:
            for (label, bloopy) in target[_BloopyInfo].bloopies.to_list():
                (json_file, more_files) = _make_bloop_json(ctx, label, bloopy)
                json_files.append(json_file)
                all_files.extend(more_files)

    all_files.extend(ctx.files.bazelbuild_rules_scala_compiler_jars)
    all_files.extend(json_files)

    print(ctx.var)

    script = ctx.actions.declare_file(ctx.label.name)
    script_content = _SCRIPT_TEMPLATE.format(
        COPY_FILES = "\n".join([
            'sed "s?@@WORKSPACE_ROOT@@?$WORKSPACE_ROOT/?g" %s | sed "s?@@RUNFILES_ROOT@@?$RUNFILES_ROOT/?g" > .bloop/%s' % (f.path, f.basename)
            for f in json_files
        ]),
    )
    ctx.actions.write(script, script_content, is_executable = True)

    runfiles = ctx.runfiles(files = all_files)
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
        "bazelbuild_rules_scala_compiler_jars": attr.label_list(
            mandatory = False,
            allow_files = True,
        ),
        "_module_json_template": attr.label(
            default = Label("//bloop/private:module-template.json"),
            allow_single_file = True,
        ),
    },
    executable = True,
)
