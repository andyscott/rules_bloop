load("@io_bazel_rules_scala//scala:scala.bzl", "scala_library", "scala_binary", "scala_test")

package(default_visibility = ["//visibility:public"])

scala_library(
    name = "Foo",
    srcs = ["Foo.scala"]
)

scala_library(
    name = "Bar",
    srcs = ["Bar.scala"]
)

scala_binary(
    name = "Simple",
    srcs = ["Simple.scala"],
    main_class = "higherkindness.rules_bloop.example.bazelbuild_rules_scala.Simple",
    deps = [":Foo", ":Bar"]
)