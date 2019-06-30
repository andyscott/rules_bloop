load("//bloop:bloop.bzl", "bloop")

bloop(
    name = "bloop",
    targets = [
        "//src/higherkindness/rules_bloop/example/simple:Simple",
	"//src/higherkindness/rules_bloop/example/bazelbuild_rules_scala:Simple",
    ],
    bazelbuild_rules_scala_compiler_jars = [
        "@io_bazel_rules_scala_scala_compiler//jar:jar",
	"@io_bazel_rules_scala_scala_library//jar:jar",
	"@io_bazel_rules_scala_scala_reflect//jar:jar",
    ],
)