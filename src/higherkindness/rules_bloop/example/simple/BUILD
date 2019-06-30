package(default_visibility = ["//visibility:public"])

java_library(
	name = "Foo",
	srcs = ["Foo.java"],
)

java_library(
	name = "Bar",
	srcs = ["Bar.java"],
)

java_binary(
	name = "Simple",
	srcs = ["Simple.java"],
	deps = [":Foo", ":Bar"],
)